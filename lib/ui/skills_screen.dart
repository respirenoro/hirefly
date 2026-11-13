import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_client.dart';
import '../ai/prompts.dart';
import '../data/content.dart';
import '../data/db.dart';
import '../engine/export.dart';
import '../engine/inbox.dart';
import '../engine/sandbox.dart';
import 'chat.dart';
import 'sandbox_screen.dart';
import 'shell.dart';
import 'ui.dart';

/// One skill: lessons, hands-on labs, outside courses, and interview questions.
class SkillScreen extends ConsumerStatefulWidget {
  const SkillScreen(this.moduleId, {super.key, this.tab});
  final String moduleId;
  final String? tab;

  @override
  ConsumerState<SkillScreen> createState() => _SkillScreenState();
}

class _SkillScreenState extends ConsumerState<SkillScreen> {
  late String _tab = widget.tab ?? 'lessons';

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(contentProvider).modules.firstWhere((m) => m.id == widget.moduleId);
    final progress = ref.watch(lessonProgressProvider);
    final lessons = m.lessons.toList();
    final done = lessons.where((l) => lessonDone(progress[l.id])).length;
    final next = lessons.where((l) => !lessonDone(progress[l.id])).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageTop(
        title: m.title,
        kicker: '$done of ${lessons.length} lessons${m.labs.isEmpty ? '' : '  ·  ${m.labs.length} labs'}',
        actions: [
          ...ref.backToRole(),
          if (m.id == 'sql') JBtn('SQL sandbox', icon: 'layers', onTap: () => ref.go('sandbox')),
          if (next != null) JBtn(done == 0 ? 'Start' : 'Continue', icon: 'play', primary: true, onTap: () => ref.go('lesson', m.id, next.id)),
        ],
        below: JSeg<String>(
          items: [
            const JSegItem('lessons', 'Lessons'),
            if (m.labs.isNotEmpty) const JSegItem('labs', 'Labs'),
            if (m.resources.isNotEmpty || m.pathway != null) const JSegItem('resources', 'Courses and advice'),
            if (m.interviewQuestions.isNotEmpty) const JSegItem('interview', 'Interview questions'),
          ],
          value: _tab,
          onChanged: (v) => setState(() => _tab = v),
        ),
      ),
      Expanded(
        child: switch (_tab) {
          'labs' => _Labs(m),
          'resources' => _Resources(m),
          'interview' => _InterviewQuestions(m),
          _ => _Lessons(m, done: done),
        },
      ),
    ]);
  }
}

class _Lessons extends ConsumerWidget {
  const _Lessons(this.m, {required this.done});
  final SkillModule m;
  final int done;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final progress = ref.watch(lessonProgressProvider);
    final total = m.lessons.length;
    return Sheet(children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.tagline, style: context.quote),
          const SizedBox(height: 10),
          const Label('What you are backing up'),
          Text(m.claim, style: readStyle(context).copyWith(color: p.textMuted)),
          if (m.unverified.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Label('Check before you rely on it'),
            Bullets(m.unverified),
          ],
          const SizedBox(height: 12),
          Bar(total == 0 ? 0 : done / total, color: p.ratingHigh),
        ]),
      ),
      for (final u in m.units) ...[
        const SizedBox(height: 22),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Heading(u.title, sub: u.summary.isEmpty ? null : u.summary)),
          if (u.lessons.any((l) => !lessonDone(progress[l.id])))
            JBtn('I know this: test out', quiet: true, onTap: () => showDialog<void>(context: context, builder: (_) => _TestOut(unit: u))),
        ]),
        const SizedBox(height: 8),
        Container(
          decoration: p.panel(),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final l in u.lessons)
              JLi(
                text: l.title,
                leading: LineIcon(
                  switch (progress[l.id]?['state']) { 'done' || 'tested-out' => 'check-circle', 'started' => 'clock', _ => 'dot' },
                  size: 14,
                  color: lessonDone(progress[l.id]) ? p.ratingHigh : (progress[l.id] != null ? p.accent : p.textFaint),
                ),
                trailing: switch (progress[l.id]?['state']) { 'tested-out' => 'tested out', 'done' => 'done', 'started' => 'started', _ => '${l.minutes} min' },
                onTap: () => ref.go('lesson', m.id, l.id),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 8),
      Text('', style: t.bodySmall),
    ]);
  }
}

class _Labs extends ConsumerWidget {
  const _Labs(this.m);
  final SkillModule m;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final done = {for (final d in ref.watch(docsProvider(('lab', null))).value ?? const <Doc>[]) d.id};
    final store = ref.read(storeProvider);
    return Sheet(children: [
      Panel(
        raised: true,
        child: Row(children: [
          Expanded(child: Text('Labs are done in the real tool, on a free tier, with HireFly\'s practice data: 1,019 shifts, 906 assignments and 734 support tickets from a fictional pharmacist-staffing product. Each one ends in something you can see and truthfully talk about.', style: readStyle(context))),
          const SizedBox(width: 14),
          JBtn('Get the practice data', icon: 'download', primary: true, onTap: () async {
            await showInExplorer(await exportPracticeData());
            if (context.mounted) say(context, 'Copied to Documents\\HireFly\\practice-data: five CSV files and practice.sql.');
          }),
        ]),
      ),
      for (final lab in m.labs) ...[
        const SizedBox(height: 14),
        Panel(
          edge: done.contains(lab['id']) ? p.ratingHigh.withValues(alpha: .45) : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${lab['title']}', style: t.headlineSmall)),
              Text('${lab['minutes'] ?? 30} min', style: context.mono.copyWith(color: p.textFaint)),
            ]),
            const SizedBox(height: 4),
            Text('${lab['goal'] ?? ''}', style: readStyle(context).copyWith(color: p.textMuted)),
            if ('${lab['setup'] ?? ''}'.trim().isNotEmpty) ...[const SizedBox(height: 12), const Label('Set up'), Md('${lab['setup']}')],
            const SizedBox(height: 12),
            const Label('Steps'),
            for (final (i, s) in (lab['steps'] as List? ?? const []).indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 24, child: Text('${i + 1}', style: context.mono.copyWith(color: p.textFaint, height: 1.9))),
                  Expanded(child: Md('$s')),
                ]),
              ),
            if ((lab['check'] as List? ?? const []).isNotEmpty) ...[
              const SizedBox(height: 8),
              const Label('It worked if'),
              Bullets([for (final c in lab['check'] as List) '$c'], color: P.good),
            ],
            if ('${lab['talkTrack'] ?? ''}'.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              const Label('What you can now say'),
              Text('${lab['talkTrack']}', style: context.quote),
            ],
            const SizedBox(height: 12),
            done.contains(lab['id'])
                ? Row(children: [const Pill('Done', color: P.good), const SizedBox(width: 8), JBtn('Not done', quiet: true, onTap: () => store.delete('${lab['id']}'))])
                : JBtn('I did this', icon: 'check', onTap: () => store.put('lab', {'at': nowUtc().toIso8601String()}, id: '${lab['id']}')),
          ]),
        ),
      ],
    ]);
  }
}

/// Which outside course to use, when, and when these lessons are the better
/// use of the time: a verdict, a plan for the time you have, then each course.
class _Resources extends ConsumerStatefulWidget {
  const _Resources(this.m);
  final SkillModule m;

  @override
  ConsumerState<_Resources> createState() => _ResourcesState();
}

class _ResourcesState extends ConsumerState<_Resources> {
  int? _plan;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final m = widget.m;
    final path = m.pathway;
    final plans = [for (final x in (path?['plans'] as List? ?? const [])) x as Json];
    // Opened from a role with a date: start on the plan that fits the days left.
    final roleId = ref.read(navProvider.notifier).fromRole;
    final role = roleId == null ? null : ref.watch(docProvider(roleId)).value;
    final days = role == null ? null : daysLeft(role.data);
    final pick = (_plan ?? (days == null ? 1 : (days <= 3 ? 0 : (days <= 21 ? 1 : 2)))).clamp(0, plans.isEmpty ? 0 : plans.length - 1);
    const rank = {'core': 0, 'worthwhile': 1, 'optional': 2};
    final resources = [...m.resources]..sort((a, b) => (rank[a['priority']] ?? 3).compareTo(rank[b['priority']] ?? 3));
    Widget side(String title, List items, Color color) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Label(title), Bullets([for (final i in items) '$i'], color: color)]),
        );
    return Sheet(children: [
      if (path != null) ...[
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${path['summary']}', style: context.quote),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              side('HireFly is the better choice when', path['hireflyBetter'] as List? ?? const [], p.ratingHigh),
              const SizedBox(width: 24),
              side('An outside course or the real tool is better when', path['externalBetter'] as List? ?? const [], p.accent),
            ]),
          ]),
        ),
        if (plans.isNotEmpty) ...[
          const SizedBox(height: 22),
          Heading('Your plan', sub: days == null ? 'Pick the time you have.' : 'Chosen for ${role!.data['role']}: ${days <= 0 ? 'the interview is today or past' : '$days day${days == 1 ? '' : 's'} left'}.'),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: JSeg<int>(items: [for (final (i, pl) in plans.indexed) JSegItem(i, '${pl['when']}')], value: pick, onChanged: (v) => setState(() => _plan = v))),
          const SizedBox(height: 10),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('About ${plans[pick]['hours']} hours', style: context.mono.copyWith(color: p.textFaint)),
              const SizedBox(height: 8),
              for (final (i, s) in (plans[pick]['steps'] as List).indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 24, child: Text('${i + 1}', style: context.mono.copyWith(color: p.textFaint, height: 1.9))),
                    Expanded(child: Text('$s', style: readStyle(context))),
                  ]),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 22),
        const Heading('Outside courses and references', sub: 'From the people who make the tool, most useful first. Links open in your browser.'),
      ] else
        Text('The best free material from the people who make the tool. Links open in your browser.', style: readStyle(context).copyWith(color: p.textMuted)),
      for (final r in resources) ...[
        const SizedBox(height: 10),
        Panel(
          onTap: isWebLink('${r['url']}') ? () => openWebLink('${r['url']}') : null,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r['title']}', style: t.titleLarge),
                const SizedBox(height: 2),
                Text('${r['why'] ?? ''}', style: readStyle(context).copyWith(color: p.textMuted)),
                if ('${r['useWhen'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text.rich(TextSpan(children: [
                    TextSpan(text: 'Use it when  ', style: t.bodySmall?.copyWith(color: p.textFaint)),
                    TextSpan(text: '${r['useWhen']}', style: readStyle(context)),
                  ])),
                ],
                if ('${r['versus'] ?? ''}'.isNotEmpty)
                  Text.rich(TextSpan(children: [
                    TextSpan(text: 'Against HireFly  ', style: t.bodySmall?.copyWith(color: p.textFaint)),
                    TextSpan(text: '${r['versus']}', style: readStyle(context)),
                  ])),
                const SizedBox(height: 4),
                Text('${r['url']}', style: context.mono.copyWith(color: p.ink, fontSize: 11.5)),
              ]),
            ),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (r['priority'] != null)
                Pill(switch (r['priority']) { 'core' => 'Do this', 'worthwhile' => 'Worth a week', _ => 'Optional' }, color: switch (r['priority']) { 'core' => P.warn, 'worthwhile' => P.accent, _ => P.muted }),
              const SizedBox(height: 6),
              Text('${r['source'] ?? ''}', style: t.bodySmall),
              Text([
                '${r['kind'] ?? ''}',
                if (r['minutes'] is num) (r['minutes'] as num) >= 90 ? '${((r['minutes'] as num) / 60).toStringAsFixed(1)} h' : '${r['minutes']} min',
                if (r['free'] == false) 'paid',
              ].where((s) => s.isNotEmpty).join('  ·  '), style: t.bodySmall),
            ]),
          ]),
        ),
      ],
    ]);
  }
}

class _InterviewQuestions extends StatefulWidget {
  const _InterviewQuestions(this.m);
  final SkillModule m;

  @override
  State<_InterviewQuestions> createState() => _InterviewQuestionsState();
}

class _InterviewQuestionsState extends State<_InterviewQuestions> {
  final _open = <String>{};

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Sheet(children: [
      Text('Answer aloud first, then open the model answer.', style: readStyle(context).copyWith(color: p.textMuted)),
      const SizedBox(height: 8),
      for (final q in widget.m.interviewQuestions)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text('${q['prompt']}', style: t.titleLarge)),
                const SizedBox(width: 10),
                JBtn(_open.contains(q['id']) ? 'Hide' : 'Model answer', quiet: true, onTap: () => setState(() => _open.contains(q['id']) ? _open.remove(q['id']) : _open.add('${q['id']}'))),
              ]),
              if (_open.contains(q['id'])) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${q['strongAnswer']}', style: context.quote)),
            ]),
          ),
        ),
    ]);
  }
}

/// The unit's placement questions. A lesson whose question you get right is
/// marked as known.
class _TestOut extends ConsumerStatefulWidget {
  const _TestOut({required this.unit});
  final Unit unit;

  @override
  ConsumerState<_TestOut> createState() => _TestOutState();
}

class _TestOutState extends ConsumerState<_TestOut> {
  late final _qs = [for (final l in widget.unit.lessons) for (final e in l.exercises) if (e.placement && e.type != 'open') (l, e)];
  final _right = <String, bool>{};

  Future<void> _finish() async {
    final store = ref.read(storeProvider);
    var passed = 0;
    for (final (l, e) in _qs) {
      if (_right[e.id] == true && (await store.get(l.id))?.data['state'] != 'done') {
        await store.put('lesson', {'state': 'tested-out', 'exercises': {e.id: {'ok': true}}}, id: l.id);
        passed++;
      }
    }
    if (!mounted) return;
    Navigator.pop(context);
    final missed = _qs.length - _right.values.where((v) => v).length;
    say(context, missed == 0 ? 'All correct. This unit is marked as known.' : '$passed lesson${passed == 1 ? '' : 's'} marked as known. $missed left to study, where you missed the question.');
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Test out: ${widget.unit.title}', style: Theme.of(context).textTheme.titleLarge),
        content: SizedBox(
          width: 640,
          child: SelectionArea(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('One question per lesson. A lesson you get right is marked as known; the others stay on your list.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.palette.textMuted)),
                for (final (_, e) in _qs) Padding(padding: const EdgeInsets.only(top: 18), child: ExerciseCard(e, quiet: true, onResult: (ok, _) => setState(() => _right[e.id] = ok))),
              ]),
            ),
          ),
        ),
        actions: [
          JBtn('Cancel', quiet: true, onTap: () => Navigator.pop(context)),
          JBtn('Finish', primary: true, onTap: _right.length == _qs.length ? _finish : null),
        ],
      );
}

class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen(this.moduleId, this.lessonId, {super.key});
  final String moduleId, lessonId;

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  bool _tutor = false, _thinking = false;

  late final SkillModule _m = ref.read(contentProvider).modules.firstWhere((m) => m.id == widget.moduleId);
  late final Lesson _l = _m.lessons.firstWhere((l) => l.id == widget.lessonId);
  String get _thread => 'tutor-${_l.id}';

  Future<void> _result(Exercise e, bool ok, String answer) async {
    final store = ref.read(storeProvider);
    final old = (await store.get(_l.id))?.data ?? const {};
    final ex = {...(old['exercises'] as Json? ?? const {}), e.id: {'ok': ok, 'answer': answer}};
    final all = _l.exercises.every((x) => ex.containsKey(x.id));
    await store.put('lesson', {...old, 'exercises': ex, 'state': old['state'] == 'done' || all ? 'done' : (old['state'] ?? 'started')}, id: _l.id);
  }

  Future<void> _ask(String text) async {
    final store = ref.read(storeProvider);
    await store.put('chat', {'role': 'user', 'text': text, 'at': nowUtc().toIso8601String()}, parent: _thread);
    setState(() => _thinking = true);
    final turns = [for (final d in await store.list('chat', parent: _thread)) AiTurn(d.data['role'] as String, d.data['text'] as String)];
    final content = ref.read(contentProvider);
    if (!mounted) return;
    final reply = await tryAi(context, () => ref.read(aiClientProvider).chat(task: 'tutor', stable: tutorContext(content), instructions: lessonForTutor(_m, _l), turns: turns));
    if (reply != null) await store.put('chat', {'role': 'assistant', 'text': reply, 'at': nowUtc().toIso8601String()}, parent: _thread);
    if (mounted) setState(() => _thinking = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lessons = _m.lessons.toList();
    final i = lessons.indexOf(_l);
    final unit = _m.units.firstWhere((u) => u.lessons.contains(_l));
    final progress = ref.watch(docProvider(_l.id)).value?.data;
    final saved = progress?['exercises'] as Json? ?? const {};
    final chat = ref.watch(docsProvider(('chat', _thread))).value ?? const <Doc>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageTop(
        title: _l.title,
        kicker: '${unit.title}  ·  lesson ${i + 1} of ${lessons.length}  ·  ${_l.minutes} min',
        onBack: () => ref.go('skill', _m.id),
        backLabel: _m.title,
        actions: [
          ...ref.backToRole(),
          if (_m.id == 'sql') JBtn('SQL sandbox', icon: 'layers', onTap: () => ref.go('sandbox')),
          JBtn(_tutor ? 'Hide the tutor' : 'Ask the tutor', icon: 'school', onTap: () => setState(() => _tutor = !_tutor)),
        ],
      ),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Sheet(width: 780, children: [
              Md(_l.body),
              const SizedBox(height: 20),
              Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Label('Key points'), Bullets(_l.keyPoints, color: P.accent)])),
              if (_l.interviewAngle.isNotEmpty) ...[
                const SizedBox(height: 12),
                Panel(raised: true, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Label('In the interview'), Md(_l.interviewAngle)])),
              ],
              const SizedBox(height: 26),
              const Heading('Practice'),
              for (final e in _l.exercises)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Panel(child: ExerciseCard(e, key: ValueKey(e.id), saved: saved[e.id] as Json?, onResult: (ok, answer) => _result(e, ok, answer))),
                ),
              const SizedBox(height: 24),
              Row(children: [
                if (!lessonDone(progress)) JBtn('Mark as complete', icon: 'check', onTap: () => ref.read(storeProvider).put('lesson', {...?progress, 'state': 'done'}, id: _l.id)) else const Pill('Lesson complete', color: P.good),
                const Spacer(),
                if (i + 1 < lessons.length)
                  JBtn('Next: ${lessons[i + 1].title}', primary: true, trailingIcon: 'right', onTap: () => ref.go('lesson', _m.id, lessons[i + 1].id))
                else
                  JBtn('Back to ${_m.title}', primary: true, onTap: () => ref.go('skill', _m.id)),
              ]),
            ]),
          ),
          if (_tutor)
            Container(
              width: 400,
              decoration: BoxDecoration(border: Border(left: BorderSide(color: p.border))),
              child: Column(children: [
                Expanded(
                  child: ChatList(
                    messages: [for (final d in chat) ChatMessage.of(d.data, them: 'Tutor')],
                    typing: _thinking ? 'The tutor' : null,
                    empty: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text('Ask about anything in this lesson: why something works, another example, or to be quizzed. Needs a Claude API key.', textAlign: TextAlign.center, style: readStyle(context).copyWith(color: p.textMuted)),
                    ),
                  ),
                ),
                Composer(enabled: !_thinking, hint: 'Ask the tutor', onSend: _ask),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

/// One exercise. Multiple choice and short answers are checked here. A SQL
/// answer is run and compared with the model query's result. Any other open
/// answer is graded by the coach, or by you against the model answer.
class ExerciseCard extends ConsumerStatefulWidget {
  const ExerciseCard(this.exercise, {super.key, required this.onResult, this.saved, this.quiet = false});
  final Exercise exercise;
  final void Function(bool ok, String answer) onResult;
  final Json? saved;

  /// In a placement test: record the answer without showing whether it was right.
  final bool quiet;

  @override
  ConsumerState<ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends ConsumerState<ExerciseCard> {
  late final _text = TextEditingController(text: widget.exercise.type == 'mcq' ? '' : '${widget.saved?['answer'] ?? ''}');
  final _runner = GlobalKey<SqlRunnerState>();
  int? _choice;
  bool? _ok;
  bool _busy = false, _showModel = false;
  Json? _grade;
  String? _sqlVerdict;

  @override
  void initState() {
    super.initState();
    if (widget.saved != null) {
      _ok = widget.saved!['ok'] as bool?;
      _choice = int.tryParse('${widget.saved!['answer']}');
      _showModel = widget.exercise.type == 'open' && widget.exercise.sqlite == null;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done(bool ok, String answer) {
    setState(() => _ok = ok);
    widget.onResult(ok, answer);
  }

  Future<void> _checkSql() async {
    final e = widget.exercise;
    final mine = await _runner.currentState?.run();
    if (mine == null || !mounted) return;
    final box = await ref.read(sandboxProvider('practice').future);
    final verdict = compareResults(mine, box.run(e.sqlite!, limit: 100000), ordered: e.ordered);
    setState(() {
      _sqlVerdict = verdict ?? '';
      if (verdict == null) _showModel = true;
    });
    _done(verdict == null, _runner.currentState?.text ?? '');
  }

  Future<void> _gradeOpen() async {
    final e = widget.exercise;
    if (_text.text.trim().isEmpty) return say(context, 'Write your answer first.');
    if (!(await ref.read(aiClientProvider).settings()).hasKey) {
      setState(() => _showModel = true);
      return;
    }
    setState(() => _busy = true);
    if (!mounted) return;
    final r = await tryAi(
      context,
      () => ref.read(aiClientProvider).structured(
            task: 'grade',
            stable: tutorContext(ref.read(contentProvider)),
            instructions: gradeInstructions,
            turns: [AiTurn.user(jsonEncode({'exercise': e.prompt, 'modelAnswer': e.answerText, 'rubric': e.rubric, 'learnerAnswer': _text.text.trim()}))],
            schema: gradeSchema,
            effort: 'low',
          ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _grade = r;
      _showModel = true;
    });
    if (r != null) _done((r['score'] as num) >= 7, _text.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final e = widget.exercise;
    final answered = _ok != null;
    final reveal = answered && !widget.quiet;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Md(e.prompt),
      const SizedBox(height: 10),
      if (e.type == 'mcq')
        for (var i = 0; i < e.choices.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Tappable(
              label: e.choices[i],
              selected: _choice == i,
              pressScale: 1,
              onTap: reveal
                  ? null
                  : () {
                      setState(() => _choice = i);
                      _done(i == e.answerIndex, '$i');
                    },
              child: Container(
                key: Key('choice-${e.id}-$i'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: reveal && i == e.answerIndex ? p.ratingHigh.withValues(alpha: .13) : (_choice == i ? (reveal ? p.danger.withValues(alpha: .13) : p.accentSoft) : p.s2),
                  borderRadius: BorderRadius.circular(p.radius),
                  border: Border.all(color: reveal && i == e.answerIndex ? p.ratingHigh.withValues(alpha: .5) : (_choice == i ? (reveal ? p.danger : p.accent).withValues(alpha: .5) : p.border)),
                ),
                child: Row(children: [
                  LineIcon(reveal && i == e.answerIndex ? 'check-circle' : (_choice == i ? (reveal ? 'close' : 'check') : 'dot'), size: 14, color: reveal && i == e.answerIndex ? p.ratingHigh : (_choice == i ? (reveal ? p.danger : p.accent) : p.textFaint)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(e.choices[i], style: readStyle(context))),
                ]),
              ),
            ),
          )
      else if (e.type == 'short')
        Row(children: [
          Expanded(child: TextField(controller: _text, enabled: !reveal, onSubmitted: (v) => _done(e.matches(v), v), decoration: const InputDecoration(hintText: 'Your answer'))),
          const SizedBox(width: 8),
          JBtn(widget.quiet && answered ? 'Recorded' : 'Check', onTap: reveal ? null : () => _done(e.matches(_text.text), _text.text)),
        ])
      else if (e.sqlite != null) ...[
        SqlRunner(
          key: _runner,
          database: 'practice',
          initial: '${widget.saved?['answer'] ?? ''}',
          extra: [
            JBtn('Check against the expected result', icon: 'check', onTap: _checkSql),
            JBtn('Show the model answer', quiet: true, onTap: () => setState(() => _showModel = true)),
          ],
        ),
        if (_sqlVerdict != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_sqlVerdict!.isEmpty ? 'Correct: your result matches the expected one.' : _sqlVerdict!, style: readStyle(context).copyWith(color: _sqlVerdict!.isEmpty ? p.ratingHigh : p.ratingLow).weight(500)),
          ),
      ] else ...[
        TextField(controller: _text, minLines: 4, maxLines: 16, style: TextStyle(fontFamily: context.fonts.numbers, fontSize: 13.5, height: 1.5, color: p.text), decoration: writeField('Write your answer')),
        const SizedBox(height: 10),
        Row(children: [
          BusyButton(busy: _busy, onPressed: _gradeOpen, label: 'Check my answer'),
          const SizedBox(width: 8),
          JBtn('Show the model answer', quiet: true, onTap: () => setState(() => _showModel = true)),
        ]),
      ],
      if (reveal && e.type != 'open') ...[
        const SizedBox(height: 8),
        Text(_ok! ? 'Correct.' : 'Not quite.${e.type == 'short' ? ' Answer: ${e.answerText ?? e.accept.firstOrNull ?? ''}' : ''}', style: readStyle(context).copyWith(color: _ok! ? p.ratingHigh : p.ratingLow).weight(600)),
        if (e.explanation.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Md(e.explanation)),
      ],
      if (_grade != null) ...[
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [ScoreBadge((_grade!['score'] as num).toDouble()), const SizedBox(width: 14), Expanded(child: Text('${_grade!['feedback']}', style: readStyle(context)))]),
        if ((_grade!['missed'] as List).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Bullets([for (final m in _grade!['missed'] as List) '$m'], color: P.warn)),
      ],
      if (e.type == 'open' && _showModel) ...[
        const SizedBox(height: 12),
        const Label('Model answer'),
        Md(e.answerText ?? ''),
        if (e.rubric.isNotEmpty) ...[const SizedBox(height: 8), const Label('It must contain'), Bullets(e.rubric)],
        if (_grade == null && e.sqlite == null) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            JBtn(_ok == true ? 'Marked: I had it' : 'I had it', onTap: () => _done(true, _text.text.trim())),
            JBtn(_ok == false ? 'Marked: I missed things' : 'I missed things', onTap: () => _done(false, _text.text.trim())),
          ]),
        ],
      ],
      if (e.type == 'open' && e.sqlite != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Runs on the practice data in SQLite.', style: t.bodySmall)),
    ]);
  }
}
