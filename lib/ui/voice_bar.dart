import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/delivery.dart';
import '../engine/voice.dart';
import '../terra/speech/speech_models.dart';
import 'shell.dart';
import 'ui.dart';

/// "Speak my answer": records the microphone, shows the words as they are
/// recognised, and hands back the text with its timing when stopped.
class VoiceBar extends ConsumerStatefulWidget {
  const VoiceBar({super.key, required this.onText, required this.onDone, this.enabled = true});

  /// The words recognised so far, while speaking.
  final ValueChanged<String> onText;
  final ValueChanged<VoiceResult> onDone;
  final bool enabled;

  @override
  ConsumerState<VoiceBar> createState() => _VoiceBarState();
}

class _VoiceBarState extends ConsumerState<VoiceBar> {
  /// Identifies this bar as the one that started a recording.
  final _host = Object();
  late final VoiceController _voice;

  @override
  void initState() {
    super.initState();
    // Fetched now: `ref` can't be used once the widget is being torn down.
    _voice = ref.read(voiceProvider.notifier);
  }

  @override
  void dispose() {
    // Leaving the page drops a recording this bar started. The controller
    // checks the host itself: `ref` can't be used while disposing.
    _voice.cancelFor(_host);
    super.dispose();
  }

  Future<void> _start() async {
    if (!ref.read(speechModelsProvider.notifier).ready) {
      say(context, 'Speaking needs the speech model: a one-time setup in Settings, under Voice.');
      ref.go('settings');
      return;
    }
    final problem = await _voice.start(_host);
    if (problem != null && mounted) say(context, problem);
  }

  Future<void> _stop() async {
    final r = await _voice.stop();
    if (r == null || !mounted) return;
    if (r.text.trim().isEmpty) return say(context, 'No speech was heard. Check the microphone Windows is using, then try again.');
    widget.onText(r.text);
    widget.onDone(r);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final v = ref.watch(voiceProvider);
    final mine = identical(v.host, _host);
    ref.listen(voiceProvider, (_, next) {
      if (identical(next.host, _host) && next.phase == VoicePhase.recording && next.text.isNotEmpty) widget.onText(next.text);
    });
    if (!mine || v.phase == VoicePhase.idle) {
      return JBtn('Speak my answer', icon: 'mic', onTap: widget.enabled && !v.active ? _start : null);
    }
    if (v.phase == VoicePhase.starting) return Text('Starting the microphone…', style: t.bodyMedium?.copyWith(color: p.textMuted));
    if (v.phase == VoicePhase.finishing) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6)),
        const SizedBox(width: 10),
        Text('Finishing the transcript…', style: t.bodyMedium?.copyWith(color: p.textMuted)),
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      JBtn('Stop', icon: 'stop', primary: true, onTap: _stop),
      const SizedBox(width: 10),
      Container(width: 8, height: 8, decoration: BoxDecoration(color: p.danger, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Text(clock(v.seconds), style: context.mono.copyWith(fontSize: 15)),
      const SizedBox(width: 12),
      Semantics(
        label: 'Microphone level',
        value: '${(v.level * 100).round()}',
        child: SizedBox(
          width: 90,
          height: 4,
          child: ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: v.level, backgroundColor: p.s3, color: p.ratingHigh)),
        ),
      ),
      const SizedBox(width: 12),
      JBtn('Discard', quiet: true, onTap: _voice.cancel),
    ]);
  }
}

/// Settings, Voice: the on-device speech model.
class VoiceSettings extends ConsumerWidget {
  const VoiceSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final states = ref.watch(speechModelsProvider);
    final models = ref.read(speechModelsProvider.notifier);
    final installing = states.values.whereType<ModelInstalling>().toList();
    final ready = speechModels.every((m) => states[m.id] is ModelReady);
    final error = states.values.whereType<ModelMissing>().map((m) => m.error).whereType<String>().firstOrNull;
    final total = speechModels.fold<int>(0, (a, m) => a + m.bytes);
    final note = t.bodyMedium?.copyWith(color: p.textMuted);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Label('Voice'),
      Text(
        'Speaking your answers uses a speech model that runs on this PC. Your voice is never sent anywhere and no audio is kept; only the words you said are saved with the answer.',
        style: note,
      ),
      const SizedBox(height: 10),
      if (ready)
        Row(children: [
          const Pill('Installed', color: P.good),
          const SizedBox(width: 10),
          JBtn('Remove', quiet: true, danger: true, onTap: () async {
            if (await confirm(context, 'Remove the speech model?', 'It frees about ${(total / 1e6).round()} MB. Speaking answers stops working until it is installed again.', yes: 'Remove')) {
              for (final m in speechModels) {
                await models.remove(m);
              }
            }
          }),
        ])
      else if (installing.isNotEmpty) ...[
        SizedBox(width: 360, child: Bar(installing.fold<int>(0, (a, m) => a + m.done) / installing.fold<int>(1, (a, m) => a + m.total))),
        const SizedBox(height: 8),
        Row(children: [
          Text('${(installing.fold<int>(0, (a, m) => a + m.done) / 1e6).round()} of ${(installing.fold<int>(0, (a, m) => a + m.total) / 1e6).round()} MB', style: context.mono),
          const SizedBox(width: 10),
          JBtn('Pause', quiet: true, onTap: () => speechModels.forEach(models.cancel)),
        ]),
      ] else
        Wrap(spacing: 8, runSpacing: 8, children: [
          JBtn('Download (${(total / 1e6).round()} MB)', icon: 'download', primary: true, onTap: () async {
            final err = await models.installAll();
            if (err != null && context.mounted) say(context, err);
          }),
          JBtn('Use models already on this PC', icon: 'folder', onTap: () async {
            final dir = await getDirectoryPath(confirmButtonText: 'Use this folder');
            if (dir == null) return;
            final err = await models.importFrom(Directory(dir));
            if (context.mounted) say(context, err ?? 'The speech model is installed.');
          }),
        ]),
      if (error != null && installing.isEmpty && !ready) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error, style: t.bodyMedium?.copyWith(color: p.ratingLow))),
      const SizedBox(height: 8),
      Text(
        'English: ${englishModel.credit}. Speech detector: ${vadModel.credit}. "Use models already on this PC" takes a folder holding one subfolder per model, as HireFly itself lays them out.',
        style: t.bodySmall,
      ),
    ]);
  }
}
