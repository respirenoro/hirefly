import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_client.dart';
import 'ui.dart';
import 'voice_bar.dart';

/// The key, the model and the monthly cap (after Soloza's Settings → AI).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _key = TextEditingController(), _cap = TextEditingController();
  String _model = defaultModel;
  bool _loaded = false, _hadKey = false;

  @override
  void initState() {
    super.initState();
    ref.read(aiClientProvider).settings().then((s) {
      if (!mounted) return;
      setState(() {
        _cap.text = s.monthlyCapUsd.toStringAsFixed(2);
        _model = s.model;
        _hadKey = s.hasKey;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _key.dispose();
    _cap.dispose();
    super.dispose();
  }

  Future<void> _save({bool removeKey = false}) async {
    final ai = ref.read(aiClientProvider);
    final old = await ai.settings();
    final cap = double.tryParse(_cap.text.trim());
    if (cap == null || cap < 0) {
      if (mounted) say(context, 'The monthly cap must be a dollar amount, such as 5.');
      return;
    }
    final typed = _key.text.trim();
    await ai.saveSettings(old.copyWith(claudeKey: removeKey ? () => null : (typed.isEmpty ? null : () => typed), monthlyCapUsd: cap, model: _model));
    _key.clear();
    if (!mounted) return;
    setState(() => _hadKey = removeKey ? false : (_hadKey || typed.isNotEmpty));
    say(context, 'Saved.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final spent = (ref.watch(aiMonthSpendProvider).value ?? 0) / 1000000;
    final note = t.bodyMedium?.copyWith(color: p.textMuted);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const PageTop(title: 'Settings'),
      if (_loaded)
        Expanded(
          child: Sheet(width: 620, children: [
            const Label('Claude API key'),
            TextField(controller: _key, obscureText: true, decoration: InputDecoration(hintText: _hadKey ? 'A key is saved. Paste a new one to replace it.' : 'Paste your key from console.anthropic.com')),
            const SizedBox(height: 6),
            Text('The key stays in HireFly\'s database on this PC and is sent only to Anthropic. The coach, the interviewer, tailored questions, exercise grading and the tutor use it; everything else works without one.', style: note),
            const SizedBox(height: 22),
            const Label('Model'),
            JSeg<String>(
              items: const [JSegItem('claude-opus-5-5', 'Opus 5.5'), JSegItem('claude-sonnet-5-5', 'Sonnet 5.5'), JSegItem('claude-haiku-5-5', 'Haiku 5.5')],
              value: _model,
              onChanged: (v) => setState(() => _model = v),
            ),
            const SizedBox(height: 6),
            Text(modelNames[_model] ?? '', style: note),
            const SizedBox(height: 22),
            const Label('Monthly cap, US dollars'),
            SizedBox(width: 160, child: TextField(controller: _cap, keyboardType: const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(height: 6),
            Text('Spent this month: \$${spent.toStringAsFixed(2)}. Calls stop for the rest of the month once the cap is reached.', style: note),
            const SizedBox(height: 24),
            Row(children: [
              JBtn('Save', primary: true, onTap: _save),
              const SizedBox(width: 8),
              if (_hadKey) JBtn('Remove the key', quiet: true, danger: true, onTap: () => _save(removeKey: true)),
            ]),
            const JDivi(),
            const VoiceSettings(),
          ]),
        ),
    ]);
  }
}
