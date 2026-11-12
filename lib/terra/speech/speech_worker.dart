import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'wav.dart';

/// From Soloza's `core/capture/speech_worker.dart`. Added here: each segment
/// reports where it sits in the recording, so pauses can be measured.
bool isCjk(int c) => (c >= 0x3000 && c <= 0x9fff) || (c >= 0xff00 && c <= 0xffef) || (c >= 0xf900 && c <= 0xfaff);

/// Model files a transcription needs (plain strings so they cross isolates).
class SpeechPaths {
  const SpeechPaths({required this.vad, required this.encoder, required this.decoder, required this.joiner, required this.tokens, required this.nemo});
  final String vad, encoder, decoder, joiner, tokens;

  /// NeMo transducers (Parakeet) need their model type named.
  final bool nemo;

  List<Object> toMessage() => [vad, encoder, decoder, joiner, tokens, nemo];
  static SpeechPaths fromMessage(List<Object?> m) =>
      SpeechPaths(vad: m[0]! as String, encoder: m[1]! as String, decoder: m[2]! as String, joiner: m[3]! as String, tokens: m[4]! as String, nemo: m[5]! as bool);
}

/// Audio decoded around a detected speech segment: a little before it (the
/// detector notices speech a beat late and the first syllable is lost
/// without it), a little after, never overlapping the previous segment.
/// Spike: 0.6 s before and 0.2 s after made every test segment exact.
(int, int) segmentWindow({required int start, required int length, required int total, required int prevEnd}) {
  const before = captureSampleRate * 6 ~/ 10, after = captureSampleRate * 2 ~/ 10;
  final from = math.max(math.max(0, start - before), math.min(prevEnd, start));
  final to = math.min(total, start + length + after);
  return (from, math.max(from, to));
}

/// Joins recognised segments into one passage: a space between words,
/// none between Japanese characters.
String joinSegments(Iterable<String> parts) {
  final b = StringBuffer();
  for (final s in parts.map((s) => s.trim()).where((s) => s.isNotEmpty)) {
    if (b.isNotEmpty) {
      final prev = b.toString();
      if (!(isCjk(prev.codeUnitAt(prev.length - 1)) && isCjk(s.codeUnitAt(0)))) b.write(' ');
    }
    b.write(s);
  }
  return b.toString();
}

/// Events from the worker for one session.
sealed class SpeechEvent {
  const SpeechEvent(this.session);
  final int session;
}

/// A finished piece of speech, recognised while the recording goes on.
class SpeechSegment extends SpeechEvent {
  const SpeechSegment(super.session, this.text, {this.startMs = 0, this.lengthMs = 0});
  final String text;

  /// Where the speech sits in the recording.
  final int startMs, lengthMs;
}

class SpeechDone extends SpeechEvent {
  const SpeechDone(super.session, this.text);
  final String text;
}

class SpeechFailed extends SpeechEvent {
  const SpeechFailed(super.session, this.message);
  final String message;
}

/// The recogniser in its own isolate: it takes audio while you speak,
/// cuts it at pauses with a voice detector and recognises each piece, so
/// text appears as you talk and silence never reaches the recogniser (it
/// invents words on silence). The models stay loaded between recordings.
class SpeechWorker {
  SpeechWorker._(this._isolate, this._to, this._from, this.events);

  final Isolate _isolate;
  final SendPort _to;
  final ReceivePort _from;
  final Stream<SpeechEvent> events;

  static Future<SpeechWorker> spawn() async {
    final from = ReceivePort();
    final isolate = await Isolate.spawn(_workerMain, from.sendPort, debugName: 'speech');
    final broadcast = from.asBroadcastStream();
    final to = await broadcast.first as SendPort;
    final events = broadcast.where((m) => m is List).map<SpeechEvent>((m) {
      final l = m as List;
      final s = l[1] as int;
      return switch (l[0]) {
        'seg' => SpeechSegment(s, l[2] as String, startMs: l[3] as int, lengthMs: l[4] as int),
        'done' => SpeechDone(s, l[2] as String),
        _ => SpeechFailed(s, l[2] as String),
      };
    }).asBroadcastStream();
    return SpeechWorker._(isolate, to, from, events);
  }

  /// Starts a live session; the models load if they aren't already.
  void begin(int session, SpeechPaths paths, int threads) => _to.send(['begin', session, paths.toMessage(), threads]);

  /// PCM16 little-endian mono 16 kHz.
  void audio(int session, Uint8List pcm) => _to.send(['audio', session, TransferableTypedData.fromList([pcm])]);

  /// Ends the session; a [SpeechDone] follows with the whole text.
  void finish(int session) => _to.send(['finish', session]);

  /// Recognises a WAV file we recorded (an interrupted recording).
  void file(int session, SpeechPaths paths, int threads, String path) => _to.send(['file', session, paths.toMessage(), threads, path]);

  void dispose() {
    _isolate.kill(priority: Isolate.immediate);
    _from.close();
  }
}

/// Threads for the recogniser: half the cores, at most four.
int speechThreads() => math.max(1, math.min(4, Platform.numberOfProcessors ~/ 2));

// ---- worker side (top-level: the isolate captures nothing else) ----

void _workerMain(SendPort out) {
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  final w = _Worker(out);
  inbox.listen((m) => w.handle(m as List));
}

class _Worker {
  _Worker(this.out);
  final SendPort out;

  var _bound = false;
  String? _key;
  so.OfflineRecognizer? _rec;
  so.VoiceActivityDetector? _vad;
  String? _vadPath;
  int _session = -1;
  var _buf = Float32List(captureSampleRate * 60);
  var _n = 0;
  var _prevEnd = 0;
  final _parts = <String>[];

  void handle(List m) {
    final session = m[1] as int;
    try {
      switch (m[0]) {
        case 'begin':
          _load(SpeechPaths.fromMessage(m[2] as List), m[3] as int);
          _reset(session);
        case 'audio':
          if (session != _session) return;
          final bytes = (m[2] as TransferableTypedData).materialize().asUint8List();
          _feed(pcm16ToFloat(bytes));
        case 'finish':
          if (session != _session) return;
          _vad!.flush();
          _drain();
          out.send(['done', session, joinSegments(_parts)]);
          _session = -1;
        case 'file':
          _load(SpeechPaths.fromMessage(m[2] as List), m[3] as int);
          _reset(session);
          final samples = readPcm16Wav(File(m[4] as String).readAsBytesSync());
          if (samples == null) throw const FormatException('Not a recording this app made.');
          const step = 1600;
          for (var i = 0; i < samples.length; i += step) {
            _feed(Float32List.sublistView(samples, i, math.min(samples.length, i + step)));
          }
          _vad!.flush();
          _drain();
          out.send(['done', session, joinSegments(_parts)]);
          _session = -1;
      }
    } on Object catch (e) {
      out.send(['fail', session, '$e']);
      _session = -1;
    }
  }

  void _load(SpeechPaths p, int threads) {
    if (!_bound) {
      so.initBindings();
      _bound = true;
    }
    final key = '${p.encoder}|$threads';
    if (_key != key) {
      _rec?.free();
      _rec = null;
      _rec = so.OfflineRecognizer(so.OfflineRecognizerConfig(
        model: so.OfflineModelConfig(
          transducer: so.OfflineTransducerModelConfig(encoder: p.encoder, decoder: p.decoder, joiner: p.joiner),
          tokens: p.tokens,
          modelType: p.nemo ? 'nemo_transducer' : '',
          numThreads: threads,
          debug: false,
        ),
      ));
      _key = key;
    }
    _vadPath = p.vad;
  }

  /// A fresh detector per session, so its sample positions start at zero
  /// like our buffer (the model is tiny; this takes milliseconds).
  void _newVad() {
    _vad?.free();
    _vad = so.VoiceActivityDetector(
      config: so.VadModelConfig(
        sileroVad: so.SileroVadModelConfig(model: _vadPath!, minSilenceDuration: 0.4, minSpeechDuration: 0.25, maxSpeechDuration: 20),
        sampleRate: captureSampleRate,
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: 60,
    );
  }

  void _reset(int session) {
    _session = session;
    _newVad();
    _n = 0;
    _prevEnd = 0;
    _parts.clear();
  }

  void _feed(Float32List s) {
    if (_n + s.length > _buf.length) {
      final bigger = Float32List(math.max(_buf.length * 2, _n + s.length));
      bigger.setRange(0, _n, _buf);
      _buf = bigger;
    }
    _buf.setRange(_n, _n + s.length, s);
    _n += s.length;
    _vad!.acceptWaveform(s);
    _drain();
  }

  void _drain() {
    final vad = _vad!, rec = _rec!;
    while (!vad.isEmpty()) {
      final seg = vad.front();
      vad.pop();
      final (from, to) = segmentWindow(start: seg.start, length: seg.samples.length, total: _n, prevEnd: _prevEnd);
      _prevEnd = seg.start + seg.samples.length;
      if (to <= from) continue;
      final stream = rec.createStream();
      try {
        stream.acceptWaveform(samples: Float32List.sublistView(_buf, from, to), sampleRate: captureSampleRate);
        rec.decode(stream);
        final text = rec.getResult(stream).text.trim();
        if (text.isNotEmpty) {
          _parts.add(text);
          out.send(['seg', _session, text, seg.start * 1000 ~/ captureSampleRate, seg.samples.length * 1000 ~/ captureSampleRate]);
        }
      } finally {
        stream.free();
      }
    }
  }
}
