// Speaking an answer, end to end, with real audio and the real recogniser.
// A Windows voice reads a known answer into a WAV file (with a silence in the
// middle); that audio is played into the app in place of the microphone, and
// the transcript and timing must come back right. Then the real microphone is
// opened briefly to prove audio arrives from it.
//
// Needs the speech models on this PC; set HIREFLY_SPEECH_MODELS to their
// folder. Skipped otherwise.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:project_hirefly/engine/delivery.dart';
import 'package:project_hirefly/engine/voice.dart';
import 'package:project_hirefly/terra/read_aloud.dart' show base64Encode16;
import 'package:project_hirefly/terra/speech/speech_models.dart';
import 'package:project_hirefly/terra/speech/wav.dart';
import 'package:record/record.dart';

/// Plays a recorded WAV as if it were the microphone, in real-time-sized chunks.
class _FileMic implements MicSource {
  _FileMic(this.pcm);
  final Uint8List pcm;
  StreamController<Uint8List>? _out;

  @override
  Future<Stream<Uint8List>> start() async {
    final out = _out = StreamController<Uint8List>();
    unawaited(() async {
      const chunk = captureSampleRate * 2 ~/ 10; // 100 ms
      for (var i = 0; i < pcm.length && !out.isClosed; i += chunk) {
        out.add(Uint8List.sublistView(pcm, i, i + chunk > pcm.length ? pcm.length : i + chunk));
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
    }());
    return out.stream;
  }

  @override
  Future<void> stop() async => _out?.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final models = Directory(Platform.environment['HIREFLY_SPEECH_MODELS'] ?? r'C:\speech_models');
  final have = File(p.join(models.path, englishModel.id, 'encoder.int8.onnx')).existsSync();

  testWidgets('a spoken answer is transcribed on this PC with its pace and pauses', (t) async {
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    final tmp = await t.runAsync(() => Directory.systemTemp.createTemp('hirefly_voice_'));
    final wav = File(p.join(tmp!.path, 'answer.wav'));
    // 16 kHz, 16-bit, mono: what the recogniser takes. Six seconds of silence in the middle.
    final script = '''
Add-Type -AssemblyName System.Speech
\$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
\$f = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
\$s.SetOutputToWaveFile('${wav.path}', \$f)
\$p = New-Object System.Speech.Synthesis.PromptBuilder
\$p.AppendText('Our scheduling software coordinated contracted pharmacists to pharmacies facing staffing shortages.')
\$p.AppendBreak([TimeSpan]::FromSeconds(6))
\$p.AppendText('I rewrote the documentation, and ticket inflow dropped by about thirty five percent.')
\$s.Speak(\$p)
\$s.Dispose()
''';
    final made = await t.runAsync(() => Process.run('powershell', ['-NoProfile', '-NonInteractive', '-EncodedCommand', base64Encode16(script)]));
    expect(made!.exitCode, 0, reason: '${made.stderr}');
    final samples = readPcm16Wav(wav.readAsBytesSync());
    expect(samples, isNotNull, reason: 'the synthesised file is not 16 kHz mono PCM16');
    final bytes = wav.readAsBytesSync();
    final pcm = Uint8List.sublistView(bytes, 44);

    final box = ProviderContainer(overrides: [
      speechModelDirProvider.overrideWithValue(models),
      micSourceProvider.overrideWithValue(() => _FileMic(pcm)),
    ]);
    addTearDown(box.dispose);
    expect(box.read(speechModelsProvider.notifier).ready, isTrue);
    final voice = box.read(voiceProvider.notifier);

    final host = Object();
    final problem = await t.runAsync(() => voice.start(host));
    expect(problem, isNull);
    expect(box.read(voiceProvider).phase, VoicePhase.recording);
    // Words arrive while "speaking", before the recording is stopped.
    await t.runAsync(() async {
      final until = DateTime.now().add(const Duration(seconds: 60));
      while (box.read(voiceProvider).text.isEmpty && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      // Let the rest of the file play in.
      await Future<void>.delayed(Duration(milliseconds: pcm.length ~/ 3200 * 5 + 500));
    });
    expect(box.read(voiceProvider).text, isNotEmpty, reason: 'no live transcript');
    final r = (await t.runAsync(voice.stop))!;
    debugPrint('TRANSCRIPT ${r.text}');
    debugPrint('TIMING seconds=${r.seconds} speech=${r.speechSeconds} longestPause=${r.longestPause} pauses=${r.pauses}');

    final said = r.text.toLowerCase();
    for (final w in ['scheduling', 'pharmacists', 'staffing', 'documentation', 'ticket', 'percent']) {
      expect(said, contains(w), reason: 'missing "$w"');
    }
    expect(r.longestPause, inInclusiveRange(4, 8));
    expect(r.pauses, greaterThanOrEqualTo(1));
    expect(r.speechSeconds, lessThan(r.seconds));
    final d = analyse(r.text, seconds: r.seconds, longestPause: r.longestPause, pauses: r.pauses);
    expect(d.spoken, isTrue);
    expect(d.words, inInclusiveRange(20, 30));
    expect(d.notes.any((n) => n.startsWith('Longest pause')), isTrue);
    expect(box.read(voiceProvider).phase, VoicePhase.idle);
    tmp.deleteSync(recursive: true);
  }, skip: !have);

  testWidgets('the real microphone delivers audio', (t) async {
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    final got = await t.runAsync(() async {
      final rec = AudioRecorder();
      var n = 0;
      try {
        final stream = await rec.startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: captureSampleRate, numChannels: 1));
        final sub = stream.listen((b) => n += b.length);
        await Future<void>.delayed(const Duration(seconds: 2));
        await sub.cancel();
      } on Object catch (e) {
        debugPrint('MIC error $e');
      } finally {
        await rec.stop();
        await rec.dispose();
      }
      return n;
    });
    debugPrint('MIC bytes in 2 s: $got');
    expect(got, greaterThan(captureSampleRate), reason: 'no audio from the default microphone');
  });
}
