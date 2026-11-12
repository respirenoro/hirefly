import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_client.dart';
import '../data/content.dart';
import '../data/db.dart';
import '../engine/delivery.dart';
import '../engine/engine.dart';
import '../engine/export.dart';
import '../engine/inbox.dart';
import '../engine/intake.dart';
import '../engine/sessions.dart';
import '../engine/voice.dart';
import '../terra/read_aloud.dart';
import 'home_screen.dart';
import 'mock_view.dart';
import 'prepare_view.dart';
import 'shell.dart';
import 'ui.dart';
import 'voice_bar.dart';

const categoryNames = {
  'background': 'Your background',
  'motivation': 'Why this role',
  'self': 'About you',
  'behavioral': 'Tell me about a time',
  'situational': 'What would you do',
  'role': 'Role knowledge',
  'curveball': 'Curveballs',
  'closing': 'Closing',
};

/// Windows' own voices, for hearing a question asked (Soloza's read-aloud host).
final speakerProvider = Provider<ReadAloud>((ref) {
  final r = ReadAloud();
  ref.onDispose(r.dispose);
  return r;
});

/// Speaks [text]; the first call starts the voice host. Says why when it can't.
Future<void> speakAloud(WidgetRef ref, BuildContext context, String text) async {
  final r = ref.read(speakerProvider);
  final problem = r.isRunning ? null : await r.start();
  if (problem != null) {
    if (context.mounted) say(context, problem);
    return;
  }
  r.speak(text);
}

/// One role: overview, prepare, practise, mock. Everything saves as it
/// happens, so leaving at any point loses nothing.
class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen(this.id, {super.key, this.tab});
  final String id;

  /// The tab to open on; `new` is a role just created (its brief gets built).
  final String? tab;

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  late String _tab = const {'prepare', 'practice', 'mock'}.contains(widget.tab) ? widget.tab! : 'overview';
  bool _briefing = false;

  @override
  void initState() {
    super.initState();
    if (widget.tab == 'new') WidgetsBinding.instance.addPostFrameCallback((_) => _brief(quiet: true));
  }

  Future<void> _brief({bool quiet = false}) async {
    if (_briefing) return;
    if (!(await ref.read(aiClientProvider).settings()).hasKey) {
      if (!quiet && mounted) say(context, 'Add your Claude API key in Settings first.');
      return;
    }
    final session = await ref.read(storeProvider).get(widget.id);
    if (session == null || !mounted) return;
    setState(() => _briefing = true);
    await tryAi(context, () => ref.read(sessionsProvider).buildBrief(session));
    if (mounted) setState(() => _briefing = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(docProvider(widget.id)).value;
    if (session == null) return const SizedBox.shrink();
    final items = [...ref.watch(docsProvider(('item', widget.id))).value ?? const <Doc>[]]
      ..sort((a, b) => (a.data['order'] as int).compareTo(b.data['order'] as int));
    final mocks = ref.watch(docsProvider(('mock', widget.id))).value ?? const <Doc>[];
    final s = session.data;
    final days = daysUntil(s['interviewDate']);
    final company = '${s['company']}'.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageTop(
        title: '${s['role']}',
        kicker: [if (company.isNotEmpty) company else 'General practice', if (days != null) countdown(days)].join('  ·  '),
        actions: [
          ScoreBadge(sessionRating([for (final i in items) i.data], [for (final m in mocks) m.data])),
          const SizedBox(width: 6),
          JBtn('Cheat sheet', icon: 'download', onTap: () async {
            final f = await exportCheatSheet(session, items);
            await showInExplorer(f);
            if (context.mounted) say(context, 'Saved to Documents\\HireFly\\cheat-sheets. Open it in a browser to read or print.');
          }),
          JBtn('Details', icon: 'pen', onTap: () => ref.go('new-role', session.id)),
        ],
        below: JSeg<String>(
          items: const [JSegItem('overview', 'Overview'), JSegItem('prepare', 'Prepare'), JSegItem('practice', 'Practice'), JSegItem('mock', 'Mock interview')],
          value: _tab,
          onChanged: (v) => setState(() => _tab = v),
        ),
      ),
      Expanded(
        child: switch (_tab) {
          'prepare' => PrepareView(session: session, items: items),
          'practice' => PracticeView(session: session, items: items),
          'mock' => MockView(session: session, items: items, mocks: mocks),
          _ => _Overview(session: session, items: items, mocks: mocks, briefing: _briefing, onBrief: _brief, onTab: (v) => setState(() => _tab = v)),
        },
      ),
    ]);
  }
}

/// "Too much / want more": the learner's say over the pace.
class PaceBar extends ConsumerWidget {
  const PaceBar(this.session, {super.key});
  final Doc session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = (session.data['intensity'] as int).clamp(1, 5);
    Future<void> set(int to) async {
      await ref.read(sessionsProvider).setIntensity(session, to);
      if (context.mounted) say(context, 'Pace is now ${intensityNames[to.clamp(1, 5)]}: about ${planSize(to)} baseline questions.');
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('Pace: ${intensityNames[level]}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.palette.textMuted)),
      const SizedBox(width: 10),
      JBtn('Too much', onTap: level > 1 ? () => set(level - 1) : null),
      const SizedBox(width: 6),
      JBtn('Want more', onTap: level < 5 ? () => set(level + 1) : null),
    ]);
  }
}

class _Overview extends ConsumerWidget {
  const _Overview({required this.session, required this.items, required this.mocks, required this.briefing, required this.onBrief, required this.onTab});
  final Doc session;
  final List<Doc> items, mocks;
  final bool briefing;
  final VoidCallback onBrief;
  final ValueChanged<String> onTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final data = [for (final i in items) i.data];
    final active = data.where(isActive).toList();
    final progress = sessionProgress(data, [for (final m in mocks) m.data]);
    final brief = session.data['brief'] as Json?;
    final skipped = items.where((d) => !isActive(d.data)).toList();
    final byComp = <String, List<double>>{};
    for (final i in data) {
      final b = bestOf(i);
      if (b != null) byComp.putIfAbsent(i['competency'] as String, () => []).add(b);
    }
    final comps = [for (final e in byComp.entries) (e.key, e.value.reduce((a, b) => a + b) / e.value.length)]..sort((a, b) => a.$2.compareTo(b.$2));
    int count(String state) => active.where((i) => i['state'] == state).length;
    final strong = active.where((i) => (bestOf(i) ?? 0) >= 7).length;
    Widget stat(String n, String label, String tab) => Expanded(
          child: Tappable(
            label: '$n $label',
            onTap: () => onTab(tab),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n, style: context.mono.copyWith(fontSize: 22)),
                Text(label, style: t.bodySmall),
              ]),
            ),
          ),
        );
    return Sheet(children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${(progress * 100).round()}% prepared', style: t.headlineSmall)),
            PaceBar(session),
          ]),
          const SizedBox(height: 10),
          Bar(progress),
          const SizedBox(height: 14),
          Row(children: [
            stat('${count('new')}', 'not started', 'prepare'),
            stat('${count('drafted')}', 'drafted', 'prepare'),
            stat('${count('ready')}', 'marked ready', 'prepare'),
            stat('$strong', 'said well from memory', 'practice'),
            stat('${mocks.length}', 'mock interview${mocks.length == 1 ? '' : 's'}', 'mock'),
          ]),
        ]),
      ),
      if (comps.isNotEmpty) ...[
        const SizedBox(height: 20),
        const Label('Where you stand, weakest first'),
        Panel(
          child: Wrap(spacing: 22, runSpacing: 8, children: [
            for (final (c, v) in comps)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(c.replaceAll('-', ' '), style: t.bodyMedium?.copyWith(color: p.textMuted)),
                const SizedBox(width: 7),
                Text(scoreText(v), style: context.mono.copyWith(color: scoreColor(v))),
              ]),
          ]),
        ),
      ],
      const SizedBox(height: 22),
      Row(children: [
        const Expanded(child: Heading('Role brief')),
        BusyButton(busy: briefing, onPressed: onBrief, label: brief == null ? 'Build the brief and tailored questions' : 'Rebuild'),
      ]),
      const SizedBox(height: 10),
      if (brief == null)
        Panel(
          child: Text(
            briefing
                ? 'Reading the posting, your resume and your research. This takes about a minute; the plan is usable meanwhile.'
                : 'The brief explains what this job is screening for, where you are strong, where you will be pressed and how to answer honestly. It also adds questions specific to this posting and your resume. It needs a Claude API key.',
            style: readStyle(context).copyWith(color: p.textMuted),
          ),
        )
      else
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${brief['summary']}', style: context.quote),
            const SizedBox(height: 16),
            const Label('What they are screening for'),
            Bullets([for (final e in brief['whatTheyWant'] as List) '$e']),
            const SizedBox(height: 12),
            const Label('Your edge'),
            Bullets([for (final e in brief['yourEdge'] as List) '${e['point']}: ${e['evidence']}'], color: P.good),
            const SizedBox(height: 12),
            const Label('Where you will be pressed, and the honest answer'),
            Bullets([for (final e in brief['gaps'] as List) '${e['gap']}: ${e['howToAnswer']}'], color: P.warn),
            const SizedBox(height: 12),
            const Label('Why this company'),
            Text('${brief['whyThisCompany']}', style: readStyle(context)),
            const SizedBox(height: 12),
            const Label('Questions to ask them'),
            Bullets([for (final e in brief['questionsToAsk'] as List) '$e']),
          ]),
        ),
      if ('${session.data['research'] ?? ''}'.trim().isEmpty && '${session.data['company']}'.trim().isNotEmpty) ...[
        const SizedBox(height: 12),
        Panel(
          raised: true,
          onTap: () => ref.go('new-role', session.id),
          child: Text('No company research yet. Paste their About page, product pages or recent news under Details, then rebuild the brief: "why this company" and your questions for them get much sharper.', style: readStyle(context)),
        ),
      ],
      _RoleSkills(session),
      if (skipped.isNotEmpty) ...[
        const SizedBox(height: 22),
        Label('Left out of the plan (${skipped.length})'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(children: [
            for (final d in skipped)
              Row(children: [
                Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('${d.data['prompt']}', style: t.bodyMedium?.copyWith(color: p.textMuted)))),
                Pill(switch (d.data['skipReason']) { 'strong' => 'Already strong', 'pace' => 'Pace', _ => 'Skipped by you' }),
                const SizedBox(width: 6),
                JBtn('Put back', quiet: true, onTap: () => ref.read(sessionsProvider).setSkipped(d, false)),
              ]),
          ]),
        ),
      ],
    ]);
  }
}

/// The skill modules the posting calls for, with where the learner stands in
/// each and the plan that fits the time left. Skills open from here, and
/// their pages offer the way back to this role.
class _RoleSkills extends ConsumerWidget {
  const _RoleSkills(this.session);
  final Doc session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final content = ref.watch(contentProvider);
    final progress = ref.watch(lessonProgressProvider);
    final skills = [
      for (final (id, why) in skillsFor(session.data))
        if (content.modules.any((m) => m.id == id)) (content.modules.firstWhere((m) => m.id == id), why),
    ];
    if (skills.isEmpty) return const SizedBox.shrink();
    final days = daysLeft(session.data);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Heading('Skills this role calls for', sub: 'Found in the posting. Questions on each are in your plan; the lessons and labs are a click away, and bring you back here.'),
        const SizedBox(height: 10),
        for (final (m, why) in skills)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Builder(builder: (context) {
                final lessons = m.lessons.toList();
                final done = lessons.where((l) => lessonDone(progress[l.id])).length;
                final next = lessons.where((l) => !lessonDone(progress[l.id])).firstOrNull;
                final plan = planFor(m, days);
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(m.title, style: t.titleLarge),
                    const SizedBox(width: 10),
                    Expanded(child: Text('posting says: ${why.take(4).join(', ')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall)),
                    Text('$done/${lessons.length}', style: context.mono.copyWith(color: p.textFaint)),
                    const SizedBox(width: 10),
                    if (m.pathway != null) JBtn('Plan', quiet: true, onTap: () => ref.go('skill', m.id, 'resources')),
                    if (next != null) JBtn(done == 0 ? 'Start' : 'Continue', icon: 'play', onTap: () => ref.go('lesson', m.id, next.id)) else const Pill('Complete', color: P.good),
                  ]),
                  const SizedBox(height: 8),
                  Bar(lessons.isEmpty ? 0 : done / lessons.length, color: p.ratingHigh),
                  if (plan != null && done < lessons.length) ...[
                    const SizedBox(height: 8),
                    Text('${days == null ? 'With about two weeks' : (days <= 3 ? 'With $days day${days == 1 ? '' : 's'} left' : 'With $days days left')}, about ${plan['hours']} hours: ${(plan['steps'] as List).first}', style: t.bodyMedium?.copyWith(color: p.textMuted)),
                  ],
                ]);
              }),
            ),
          ),
      ]),
    );
  }
}

/// Answer from memory, one question at a time, weakest and newest first. No
/// notes are shown, the answer is timed, and its pace and filler words are
/// reported, so it can be typed or spoken with Windows voice typing.
class PracticeView extends ConsumerStatefulWidget {
  const PracticeView({super.key, required this.session, required this.items});
  final Doc session;
  final List<Doc> items;

  @override
  ConsumerState<PracticeView> createState() => _PracticeViewState();
}

class _PracticeViewState extends ConsumerState<PracticeView> {
  final _answer = TextEditingController();
  final _watch = Stopwatch();
  Timer? _tick;
  String? _currentId;
  Json? _eval;
  Delivery? _delivery;
  VoiceResult? _spoken;
  bool _revealed = false, _busy = false;
  int _done = 0;

  @override
  void dispose() {
    _tick?.cancel();
    _answer.dispose();
    super.dispose();
  }

  Doc? get _current {
    final byId = {for (final d in widget.items) d.id: d};
    if (_currentId != null && byId[_currentId] != null) return byId[_currentId];
    final q = drillQueue(widget.items, DateTime.now());
    return q.isEmpty ? null : q.first;
  }

  void _startClock() {
    if (_watch.isRunning) return;
    _watch.start();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopClock() {
    _watch.stop();
    _tick?.cancel();
  }

  void _next() => setState(() {
        _stopClock();
        _watch.reset();
        _currentId = null;
        _eval = null;
        _delivery = null;
        _spoken = null;
        _revealed = false;
        _answer.clear();
        _done++;
      });

  Future<void> _record(Doc item, double score, {Json? eval}) async {
    final dropped = await ref.read(sessionsProvider).recordAttempt(item, score: score, mode: 'drill', answer: _answer.text.trim(), eval: {...?eval, 'delivery': _delivery?.toJson()});
    if (dropped > 0 && mounted) {
      say(context, 'You are consistently strong here, so $dropped untouched question${dropped == 1 ? ' was' : 's were'} dropped from the plan. Overview lists them if you want any back.');
    }
  }

  Future<void> _check(Doc item) async {
    if (_answer.text.trim().isEmpty) return say(context, 'Answer first: type it, or use Speak my answer.');
    _stopClock();
    setState(() {
      _currentId = item.id;
      // A spoken answer is timed by its audio; a typed one by the clock.
      final v = _spoken;
      _delivery = v == null ? analyse(_answer.text, seconds: _watch.elapsed.inSeconds) : analyse(_answer.text, seconds: v.seconds, longestPause: v.longestPause, pauses: v.pauses);
    });
    if (!(await ref.read(aiClientProvider).settings()).hasKey) {
      setState(() => _revealed = true);
      return;
    }
    setState(() => _busy = true);
    if (!mounted) return;
    final r = await tryAi(context, () => ref.read(sessionsProvider).coach(widget.session, item, _answer.text.trim(), mode: 'drill'));
    if (!mounted) return;
    if (r != null) await _record(item, (r['score'] as num).toDouble().clamp(0, 10), eval: r);
    setState(() {
      _busy = false;
      _eval = r;
      _revealed = r == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final item = _current;
    if (item == null) {
      final any = widget.items.any((d) => isActive(d.data));
      return EmptyBody(
        any ? 'Nothing is due right now.' : 'This role has no questions in its plan yet.',
        any ? 'Every question has been answered well recently; they come back when they are due. Sit a mock interview, or raise the pace on Overview for more questions.' : null,
      );
    }
    final d = item.data;
    final left = drillQueue(widget.items, DateTime.now()).length;
    final draft = '${d['draft']}'.trim();
    final open = _eval == null && !_revealed && !_busy;
    final secs = _watch.elapsed.inSeconds;
    return Sheet(width: 820, children: [
      Row(children: [
        Pill(categoryNames[d['category']] ?? '${d['category']}'),
        const SizedBox(width: 10),
        Text('$left due  ·  $_done done this sitting', style: t.bodySmall),
        const Spacer(),
        if (_done > 0 && _done % 5 == 0) PaceBar(widget.session),
      ]),
      const SizedBox(height: 14),
      Text('${d['prompt']}', style: t.headlineMedium),
      const SizedBox(height: 10),
      Row(children: [
        JBtn('Hear it asked', icon: 'audio', onTap: () => speakAloud(ref, context, '${d['prompt']}')),
        const SizedBox(width: 8),
        VoiceBar(
          enabled: open,
          onText: (text) => setState(() => _answer.text = text),
          onDone: (r) => setState(() {
            _spoken = r;
            _stopClock();
          }),
        ),
        const SizedBox(width: 12),
        if (_spoken == null && !ref.watch(voiceProvider).active) Text(clock(secs), style: context.mono.copyWith(fontSize: 15, color: secs > 150 ? p.ratingLow : (secs >= 45 ? p.ratingHigh : p.textMuted))),
        const SizedBox(width: 10),
        Expanded(child: Text(!open ? '' : (_spoken == null ? 'Speak it or type it. Aim for 1:00 to 2:00.' : 'Spoken: ${clock(_spoken!.seconds)}. Fix any misheard words, then check.'), style: t.bodySmall)),
      ]),
      const SizedBox(height: 12),
      TextField(
        key: const Key('practice-answer'),
        controller: _answer,
        minLines: 7,
        maxLines: 18,
        enabled: open,
        style: readStyle(context),
        onChanged: (v) {
          if (v.trim().isNotEmpty) _startClock();
        },
        decoration: writeField('Answer from memory, as you would say it aloud. Your prepared answer stays hidden until you check.'),
      ),
      const SizedBox(height: 12),
      if (open || _busy)
        Row(children: [
          BusyButton(busy: _busy, filled: true, icon: 'check', onPressed: () => _check(item), label: 'Check my answer'),
          const SizedBox(width: 8),
          JBtn('Skip for now', quiet: true, onTap: _busy ? null : _next),
        ]),
      if (_delivery != null && !_busy) ...[_DeliveryPanel(_delivery!), const SizedBox(height: 12)],
      if (_eval != null) ...[
        CoachResult(_eval!),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerLeft, child: JBtn('Next question', primary: true, trailingIcon: 'right', onTap: _next)),
      ],
      if (_revealed) ...[
        const Label('Your prepared answer'),
        Panel(child: Text(draft.isEmpty ? 'You have not prepared this one yet. Write it on the Prepare tab.' : draft, style: readStyle(context))),
        const SizedBox(height: 12),
        const Label('A strong answer contains'),
        Bullets([for (final g in d['guide'] as List? ?? const []) '$g']),
        const SizedBox(height: 12),
        Text('How close were you?', style: t.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final (label, score) in const [('Missed it', 3.0), ('Rough', 6.0), ('Good', 8.0), ('Nailed it', 9.5)])
            JBtn(label, onTap: () async {
              await _record(item, score);
              _next();
            }),
        ]),
      ],
    ]);
  }
}

class _DeliveryPanel extends StatelessWidget {
  const _DeliveryPanel(this.d);
  final Delivery d;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    Widget fig(String n, String label) => Padding(
          padding: const EdgeInsets.only(right: 26),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(n, style: context.mono.copyWith(fontSize: 17)), Text(label, style: t.bodySmall)]),
        );
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Label('Delivery'),
        Row(children: [
          fig('${d.words}', 'words'),
          if (d.seconds != null) fig(clock(d.seconds!), d.spoken ? 'spoken' : 'time taken'),
          if (!d.spoken) fig(clock(d.spokenSeconds), 'at speaking pace'),
          if (d.spoken) fig('${d.longestPause}s', 'longest pause'),
          if (d.wpm != null) fig('${d.wpm}', 'words a minute'),
          fig('${d.fillerCount}', 'fillers'),
          fig('${d.hedgeCount}', 'hedges'),
        ]),
        if (d.notes.isNotEmpty) ...[const SizedBox(height: 10), Bullets(d.notes, color: p.ratingLow)],
      ]),
    );
  }
}

/// A centred line for a page with nothing to show.
class EmptyBody extends StatelessWidget {
  const EmptyBody(this.what, [this.next, Key? key]) : super(key: key);
  final String what;
  final String? next;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(what, textAlign: TextAlign.center, style: t.titleMedium),
          if (next != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(next!, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: context.palette.textMuted))),
        ]),
      ),
    );
  }
}

/// The coach's verdict on one answer.
class CoachResult extends StatelessWidget {
  const CoachResult(this.eval, {super.key, this.onUse});
  final Json eval;

  /// Offered on the rewritten answer when it can replace a draft.
  final ValueChanged<String>? onUse;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    List<String> list(String k) => [for (final e in eval[k] as List? ?? const []) '$e'];
    Widget section(String title, List<String> items, Color color) =>
        items.isEmpty ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Label(title), Bullets(items, color: color)]));
    final improved = '${eval['improved'] ?? ''}'.trim();
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ScoreBadge((eval['score'] as num).toDouble(), large: true),
          const SizedBox(width: 18),
          Expanded(child: Padding(padding: const EdgeInsets.only(top: 4), child: Text('${eval['verdict']}', style: readStyle(context)))),
        ]),
        section('Say it honestly', list('overclaims'), P.bad),
        section('Fix first', list('fixes'), P.warn),
        section('Only you can supply', list('missing'), P.accent),
        section('Keep', list('strengths'), P.good),
        if (improved.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(children: [
            const Expanded(child: Label('A stronger version')),
            if (onUse != null) JBtn('Use this as my draft', quiet: true, onTap: () => onUse!(improved)),
          ]),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: p.s2, borderRadius: BorderRadius.circular(p.radius)),
            child: Text(improved, style: context.quote),
          ),
        ],
        if ('${eval['followUp'] ?? ''}'.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          const Label('Expect this next'),
          Text('${eval['followUp']}', style: readStyle(context).copyWith(fontStyle: FontStyle.italic)),
        ],
      ]),
    );
  }
}

/// Stories from the bank that fit a competency.
List<Json> storiesFor(List<Json> stories, String competency) =>
    [for (final s in stories) if ((s['competencies'] as List? ?? const []).contains(competency)) s];

extension ContentLookup on Content {
  Question? question(String? id) => id == null ? null : questionById[id];
}
