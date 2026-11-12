// Speaking an answer: the microphone is recorded and transcribed on this PC
// (Soloza's speech worker and models), and the timing of each stretch of
// speech gives the real pace and pauses. No audio is kept or sent anywhere.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../terra/speech/speech_models.dart';
import '../terra/speech/speech_worker.dart';
import '../terra/speech/wav.dart';

enum VoicePhase { idle, starting, recording, finishing }

class VoiceState {
  const VoiceState({this.phase = VoicePhase.idle, this.level = 0, this.seconds = 0, this.text = '', this.host});
  final VoicePhase phase;

  /// Loudness now, 0 to 1, for the meter.
  final double level;
  final int seconds;

  /// What has been recognised so far.
  final String text;

  /// The widget that started the recording, so only it shows the controls.
  final Object? host;

  bool get active => phase != VoicePhase.idle;

  VoiceState copyWith({VoicePhase? phase, double? level, int? seconds, String? text}) =>
      VoiceState(phase: phase ?? this.phase, level: level ?? this.level, seconds: seconds ?? this.seconds, text: text ?? this.text, host: host);
}

/// A finished spoken answer.
class VoiceResult {
  const VoiceResult({required this.text, required this.seconds, required this.speechSeconds, required this.longestPause, required this.pauses});
  final String text;

  /// From the first word to the last, pauses included.
  final int seconds;

  /// Time actually spent speaking.
  final int speechSeconds;

  /// The longest silence inside the answer, in seconds, and how many
  /// silences ran two seconds or more.
  final int longestPause, pauses;
}

/// Pause figures from where each stretch of speech sat in the recording.
VoiceResult summarise(String text, List<(int startMs, int lengthMs)> segments) {
  if (segments.isEmpty) return VoiceResult(text: text, seconds: 0, speechSeconds: 0, longestPause: 0, pauses: 0);
  final sorted = [...segments]..sort((a, b) => a.$1.compareTo(b.$1));
  var longest = 0, count = 0, speech = 0;
  for (var i = 0; i < sorted.length; i++) {
    speech += sorted[i].$2;
    if (i > 0) {
      final gap = sorted[i].$1 - (sorted[i - 1].$1 + sorted[i - 1].$2);
      if (gap > longest) longest = gap;
      if (gap >= 2000) count++;
    }
  }
  final span = sorted.last.$1 + sorted.last.$2 - sorted.first.$1;
  return VoiceResult(text: text, seconds: (span / 1000).round(), speechSeconds: (speech / 1000).round(), longestPause: (longest / 1000).round(), pauses: count);
}

/// Where microphone audio comes from: PCM16 mono at 16 kHz. Replaced in tests.
abstract class MicSource {
  Future<Stream<Uint8List>> start();
  Future<void> stop();
}

class _RecordMic implements MicSource {
  final _rec = AudioRecorder();

  @override
  Future<Stream<Uint8List>> start() => _rec.startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: captureSampleRate, numChannels: 1));

  @override
  Future<void> stop() async {
    await _rec.stop();
    await _rec.dispose();
  }
}

final micSourceProvider = Provider<MicSource Function()>((ref) => _RecordMic.new);

SpeechPaths speechPaths(SpeechModelStore store) => SpeechPaths(
      vad: store.pathOf(vadModel, 'silero_vad.onnx'),
      encoder: store.pathOf(englishModel, 'encoder.int8.onnx'),
      decoder: store.pathOf(englishModel, 'decoder.int8.onnx'),
      joiner: store.pathOf(englishModel, 'joiner.int8.onnx'),
      tokens: store.pathOf(englishModel, 'tokens.txt'),
      nemo: true,
    );

class VoiceController extends Notifier<VoiceState> {
  SpeechWorker? _worker;
  StreamSubscription<SpeechEvent>? _events;
  StreamSubscription<Uint8List>? _audio;
  MicSource? _mic;
  Timer? _tick, _cap;
  final _watch = Stopwatch();
  final _parts = <String>[];
  final _segments = <(int, int)>[];
  Completer<String>? _done;
  var _session = 0;

  /// The longest one answer may run before it stops by itself.
  static const maxLength = Duration(minutes: 5);

  @override
  VoiceState build() {
    ref.onDispose(() {
      _tick?.cancel();
      _cap?.cancel();
      _audio?.cancel();
      _events?.cancel();
      _mic?.stop();
      _worker?.dispose();
    });
    return const VoiceState();
  }

  /// Starts recording for [host]. Returns null once it is recording, else why not.
  Future<String?> start(Object host) async {
    if (state.active) return 'A recording is already running.';
    if (!ref.read(speechModelsProvider.notifier).ready) return 'Install the speech model in Settings first (a one-time download, kept on this PC).';
    state = VoiceState(phase: VoicePhase.starting, host: host);
    try {
      final worker = _worker ??= await SpeechWorker.spawn();
      _events ??= worker.events.listen(_onEvent);
      final session = ++_session;
      _parts.clear();
      _segments.clear();
      worker.begin(session, speechPaths(ref.read(speechModelStoreProvider)), speechThreads());
      final mic = _mic = ref.read(micSourceProvider)();
      final stream = await mic.start();
      _audio = stream.listen((pcm) {
        worker.audio(session, pcm);
        if (state.phase == VoicePhase.recording) state = state.copyWith(level: pcmLevel(pcm));
      }, onError: (Object _) => stop());
    } on Object catch (e) {
      await _release();
      state = const VoiceState();
      final s = '$e';
      return s.contains('ermission') || s.contains('ccess')
          ? 'Windows blocked the microphone. Allow it in Windows Settings, Privacy, Microphone, "Let desktop apps access your microphone".'
          : 'The microphone couldn\'t start ($s).';
    }
    _watch
      ..reset()
      ..start();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.phase == VoicePhase.recording) state = state.copyWith(seconds: _watch.elapsed.inSeconds);
    });
    _cap = Timer(maxLength, stop);
    state = state.copyWith(phase: VoicePhase.recording);
    return null;
  }

  void _onEvent(SpeechEvent e) {
    if (e.session != _session) return;
    switch (e) {
      case SpeechSegment():
        _parts.add(e.text);
        _segments.add((e.startMs, e.lengthMs));
        if (state.active) state = state.copyWith(text: joinSegments(_parts));
      case SpeechDone():
        if (!(_done?.isCompleted ?? true)) _done!.complete(e.text);
      case SpeechFailed():
        if (!(_done?.isCompleted ?? true)) _done!.completeError(e.message);
    }
  }

  Future<void> _release() async {
    _tick?.cancel();
    _cap?.cancel();
    _watch.stop();
    await _audio?.cancel();
    _audio = null;
    try {
      await _mic?.stop();
    } on Object {
      // The device went away.
    }
    _mic = null;
  }

  /// Stops and returns the answer, or null when nothing was recording.
  Future<VoiceResult?> stop() async {
    if (state.phase != VoicePhase.recording) return null;
    state = state.copyWith(phase: VoicePhase.finishing, level: 0);
    await _release();
    _done = Completer<String>();
    _worker?.finish(_session);
    String text;
    try {
      text = await _done!.future.timeout(const Duration(minutes: 2));
    } on Object {
      text = joinSegments(_parts);
    }
    final result = summarise(text, _segments);
    state = const VoiceState();
    return result;
  }

  /// Drops the recording if [host] started it (its page is going away).
  void cancelFor(Object host) {
    if (state.active && identical(state.host, host)) {
      // After this frame: a provider can't change while widgets are being torn down.
      Future<void>.microtask(cancel);
    }
  }

  /// Drops the recording.
  Future<void> cancel() async {
    if (!state.active) return;
    _session++;
    await _release();
    state = const VoiceState();
  }
}

final voiceProvider = NotifierProvider<VoiceController, VoiceState>(VoiceController.new);
