import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_client.dart';
import '../ai/prompts.dart';
import '../data/content.dart';
import '../engine/inbox.dart';
import '../engine/skill_builder.dart';
import 'ui.dart';

/// Asks the assistant for a new skill module and saves it to the learner's
/// folder. Without a key it explains the other route: a Claude Code session.
class NewSkillScreen extends ConsumerStatefulWidget {
  const NewSkillScreen({super.key});

  @override
  ConsumerState<NewSkillScreen> createState() => _NewSkillScreenState();
}

class _NewSkillScreenState extends ConsumerState<NewSkillScreen> {
  final _skill = TextEditingController(), _claim = TextEditingController(), _level = TextEditingController(), _roles = TextEditingController();
  bool _busy = false;
  String? _progress, _saved, _error;

  @override
  void dispose() {
    for (final c in [_skill, _claim, _level, _roles]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _build() async {
    final skill = _skill.text.trim();
    if (skill.isEmpty) return say(context, 'Name the skill first.');
    final content = ref.read(contentProvider), ai = ref.read(aiClientProvider), home = ref.read(hireflyHomeProvider);
    setState(() {
      _busy = true;
      _saved = _error = null;
      _progress = 'Starting';
    });
    try {
      final stable = moduleStable(await rootBundle.loadString('assets/content/authoring.md'), content);
      final builder = SkillBuilder(
        home: home,
        takenIds: {...Content.moduleIds, for (final m in content.modules) m.id},
        ask: ({required task, required instructions, required schema}) =>
            ai.structured(task: task, stable: stable, instructions: instructions, turns: const [AiTurn.user('Write it now.')], schema: schema, effort: 'high'),
      );
      final id = await builder.build(
        SkillRequest(skill: skill, claim: _claim.text.trim(), level: _level.text.trim(), roles: _roles.text.trim()),
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) setState(() => _saved = id);
    } on AiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on SkillBuildFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hasKey = ref.watch(aiSettingsProvider).value?.hasKey ?? false;
    final home = ref.watch(hireflyHomeProvider).path;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const PageTop(title: 'New skill', kicker: 'A module of lessons, exercises and interview answers, written for your record'),
      Expanded(
        child: Sheet(width: 760, children: [
          Text(
            'HireFly can write a module for a skill it does not cover yet. It follows the same standard as the bundled modules: definitions interviewers ask by name, worked examples, the traps, and answers that stay within what you can honestly claim.',
            style: t.bodyLarge,
          ),
          const SizedBox(height: 18),
          TextField(key: const Key('skill-name'), controller: _skill, enabled: !_busy, decoration: const InputDecoration(labelText: 'Skill (for example Salesforce, Postman, Tableau)')),
          const SizedBox(height: 14),
          const Label('What your resume says about it'),
          TextField(key: const Key('skill-claim'), controller: _claim, enabled: !_busy, minLines: 2, maxLines: 5, decoration: writeField('Paste the resume line or lines that mention this skill.')),
          const SizedBox(height: 14),
          const Label('Your real level, and what you must not claim'),
          TextField(key: const Key('skill-level'), controller: _level, enabled: !_busy, minLines: 2, maxLines: 5, decoration: writeField('For example: logged cases in it daily for a year; never an administrator; no certification.')),
          const SizedBox(height: 14),
          TextField(controller: _roles, enabled: !_busy, decoration: const InputDecoration(labelText: 'Roles you are aiming at (optional)')),
          const SizedBox(height: 20),
          if (hasKey) ...[
            Row(children: [
              BusyButton(key: const Key('build-skill'), busy: _busy, filled: true, label: 'Write the module', onPressed: _build),
              const SizedBox(width: 14),
              if (_busy && _progress != null) Expanded(child: Text(_progress!, style: t.bodyMedium)),
            ]),
            const SizedBox(height: 10),
            Text(
              'This makes six or seven requests and takes a few minutes. The assistant inside the app cannot open web pages, so the module has no outside links and carries a list of what to check. For a module researched against current documentation, use a Claude Code session (below).',
              style: t.bodySmall,
            ),
          ] else
            Panel(
              child: Text('Writing a module here needs a Claude API key (Settings). Without one, use a Claude Code session, described below.', style: t.bodyMedium),
            ),
          if (_error != null) ...[const SizedBox(height: 14), Panel(child: Text(_error!, style: t.bodyMedium))],
          if (_saved != null) ...[
            const SizedBox(height: 14),
            Panel(
              child: Text(
                'Saved to $home\\content\\skills\\$_saved. Close and reopen HireFly to see it under Skills. Read its list of things to check before you rely on it.',
                key: const Key('skill-saved'),
                style: t.bodyMedium,
              ),
            ),
          ],
          const SizedBox(height: 26),
          const Heading('With a Claude Code session'),
          const SizedBox(height: 6),
          Text(
            'In a project that has the hirefly-module skill installed, say "build a HireFly module for <skill>". The session researches current documentation, exam outlines and interview questions, writes the module to the same folder with checked links and labs, and runs the checker. No API key is used.',
            style: t.bodyMedium,
          ),
        ]),
      ),
    ]);
  }
}
