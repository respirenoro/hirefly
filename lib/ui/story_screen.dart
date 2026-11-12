import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_client.dart';
import '../ai/prompts.dart';
import '../data/content.dart';
import '../data/db.dart';
import '../engine/delivery.dart';
import '../engine/voice.dart';
import 'chat.dart';
import 'session_screen.dart';
import 'ui.dart';
import 'voice_bar.dart';

/// What the role was, why it mattered, and how to present it.
class DossierScreen extends ConsumerWidget {
  const DossierScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The document opens with its own title; the page shows it once.
    final text = ref.watch(contentProvider).dossier.replaceFirst(RegExp(r'^# .*\n+'), '');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const PageTop(title: 'Know your role'),
      Expanded(child: Sheet(width: 800, children: [Md(text)])),
    ]);
  }
}

/// The themes behavioral interviews return to, and the question that asks for each.
const storyThemes = [
  ('conflict', 'A disagreement', 'Tell me about a time you disagreed with someone at work.'),
  ('failure', 'A failure or mistake', 'Tell me about a time you failed.'),
  ('initiative', 'Initiative', 'Tell me about something you did that nobody asked you to do.'),
  ('leadership', 'Leading others', 'Tell me about a time you led a group to a result.'),
  ('pressure', 'Pressure or a deadline', 'Tell me about a time you worked under real pressure.'),
  ('customer-focus', 'A difficult customer', 'Tell me about a difficult customer and how it ended.'),
  ('prioritization', 'Competing priorities', 'Tell me about a time you had more to do than time to do it.'),
  ('problem-solving', 'A hard problem', 'Tell me about the hardest problem you solved.'),
  ('process-improvement', 'Improving a process', 'Tell me about a process you made better.'),
  ('learning', 'Learning fast', 'Tell me about a time you had to learn something quickly.'),
  ('communication', 'Explaining something hard', 'Tell me about explaining something technical to a non-technical person.'),
  ('stakeholders', 'Pushback from a stakeholder', 'Tell me about a time someone senior pushed back on you.'),
  ('teamwork', 'Working in a team', 'Tell me about a time a team you were on worked well, and your part in it.'),
  ('feedback', 'Hard feedback', 'Tell me about feedback that was hard to hear.'),
  ('ambiguity', 'Unclear requirements', 'Tell me about a time you had to act without clear direction.'),
  ('attention-to-detail', 'Catching an error', 'Tell me about a time your attention to detail prevented a problem.'),
  ('adaptability', 'A sudden change', 'Tell me about a time plans changed on you.'),
  ('ethics', 'Doing the right thing', 'Tell me about a time doing the right thing cost you something.'),
  ('data', 'Deciding with data', 'Tell me about a decision you made from data.'),
  ('quality', 'Protecting quality', 'Tell me about a time you held the line on quality.'),
];

bool storyWritten(Json s) => '${s['action'] ?? ''}'.trim().isNotEmpty && '${s['result'] ?? ''}'.trim().isNotEmpty;
bool storyHasGaps(Json s) => (s['open'] as List? ?? const []).isNotEmpty && '${s['notes'] ?? ''}'.trim().isEmpty;
String storySpoken(Json s) => [for (final k in ['situation', 'task', 'action', 'result']) '${s[k] ?? ''}'.trim()].where((x) => x.isNotEmpty).join(' ');

/// The story bank: which interview themes you can answer, the stories
/// themselves, and a workshop for building, checking and telling each one.
class StoriesScreen extends ConsumerStatefulWidget {
  const StoriesScreen({super.key});

  @override
  ConsumerState<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends ConsumerState<StoriesScreen> {
  String? _open;

  Future<void> _add({String? competency, String? label, String? question}) async {
    final id = 'story-${newId()}';
    await ref.read(storeProvider).put(
        'story',
        {
          'title': label ?? 'New story',
          'bestFor': [?question],
          'competencies': [?competency],
          'situation': '',
          'task': '',
          'action': '',
          'result': '',
          'open': const <String>[],
        },
        id: id);
    setState(() => _open = id);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final stories = ref.watch(storiesProvider);
    final open = stories.where((s) => s['id'] == _open).firstOrNull;
    if (open != null) return _StoryWorkshop(key: ValueKey(open['id']), story: open, onBack: () => setState(() => _open = null));

    final bank = ref.watch(contentProvider).questions;
    final written = stories.where(storyWritten).toList();
    bool covered(String c) => written.any((s) => (s['competencies'] as List? ?? const []).contains(c));
    final missing = storyThemes.where((th) => !covered(th.$1)).toList();
    final told = stories.where((s) => s['toldScore'] != null).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageTop(
        title: 'Your stories',
        kicker: '${written.length} written  ·  ${storyThemes.length - missing.length} of ${storyThemes.length} interview themes covered  ·  $told told aloud',
        actions: [JBtn('Add a story', icon: 'plus', onTap: _add)],
      ),
      Expanded(
        child: Sheet(width: 900, children: [
          Panel(
            raised: true,
            child: Text(
              'Behavioral interviews draw on the same twenty themes. Eight to ten good stories cover all of them, because one story answers many questions. Build each one here: get interviewed about it, have it checked, then tell it against the clock until it comes out clean.',
              style: readStyle(context),
            ),
          ),
          const SizedBox(height: 22),
          const Heading('Themes you can answer', sub: 'A theme is covered when a written story carries it.'),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (c, label, question) in storyThemes)
              Tooltip(
                message: covered(c) ? '$question\nAnswered by: ${written.where((s) => (s['competencies'] as List? ?? const []).contains(c)).map((s) => s['title']).join(', ')}' : '$question\nNo story yet. Click to start one.',
                child: Tappable(
                  label: label,
                  onTap: covered(c) ? () => setState(() => _open = '${written.firstWhere((s) => (s['competencies'] as List? ?? const []).contains(c))['id']}') : () => _add(competency: c, label: label, question: question),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: covered(c) ? p.ratingHigh.withValues(alpha: .10) : p.s2,
                      borderRadius: BorderRadius.circular(p.radius),
                      border: Border.all(color: covered(c) ? p.ratingHigh.withValues(alpha: .4) : p.border),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      LineIcon(covered(c) ? 'check' : 'plus', size: 12, color: covered(c) ? p.ratingHigh : p.textFaint),
                      const SizedBox(width: 7),
                      Text(label, style: t.bodyMedium?.copyWith(color: covered(c) ? p.text : p.textMuted)),
                      const SizedBox(width: 8),
                      Text('${bank.where((q) => q.competency == c).length}', style: context.mono.copyWith(color: p.textFaint, fontSize: 11)),
                    ]),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Text('The number is how many bank questions ask for that theme.${missing.isEmpty ? '' : ' Not covered yet: ${missing.map((m) => m.$2.toLowerCase()).join(', ')}.'}', style: t.bodySmall),
          const SizedBox(height: 22),
          const Heading('Stories'),
          for (final s in stories)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Panel(
                onTap: () => setState(() => _open = '${s['id']}'),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${s['title']}', style: t.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        storyWritten(s) ? ('${s['headline'] ?? ''}'.trim().isNotEmpty ? '${s['headline']}' : 'For: ${(s['bestFor'] as List? ?? const []).join('  ·  ')}') : 'Not written yet',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyMedium?.copyWith(color: storyWritten(s) ? p.textMuted : p.ratingLow),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  if (storyHasGaps(s)) const Padding(padding: EdgeInsets.only(right: 8), child: Pill('needs your details', color: P.warn)),
                  if (s['checkScore'] != null) Padding(padding: const EdgeInsets.only(right: 10), child: ScoreBadge((s['checkScore'] as num).toDouble())),
                  if (storyWritten(s)) Text('${clock(analyse(storySpoken(s)).spokenSeconds)} spoken', style: context.mono.copyWith(color: p.textFaint)),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }
}

/// One story: write it, see which questions it answers, and tell it aloud.
class _StoryWorkshop extends ConsumerStatefulWidget {
  const _StoryWorkshop({super.key, required this.story, required this.onBack});
  final Json story;
  final VoidCallback onBack;

  @override
  ConsumerState<_StoryWorkshop> createState() => _StoryWorkshopState();
}

class _StoryWorkshopState extends ConsumerState<_StoryWorkshop> {
  static const _fields = ['title', 'headline', 'situation', 'task', 'action', 'result', 'notes'];
  late final _c = {for (final f in _fields) f: TextEditingController(text: '${widget.story[f] ?? ''}')};
  late final Set<String> _comps = {for (final c in widget.story['competencies'] as List? ?? const []) '$c'};
  final _tell = TextEditingController();
  final _watch = Stopwatch();
  Timer? _tick, _debounce;
  String _tab = 'write';
  bool _checking = false, _interviewing = false, _thinking = false, _writing = false, _telling = false;
  VoiceResult? _spoken;
  Delivery? _delivery;
  Json? _tellCheck;

  String get _id => widget.story['id'] as String;
  String get _thread => 'story-int-$_id';
  Store get _store => ref.read(storeProvider);

  @override
  void dispose() {
    _tick?.cancel();
    _debounce?.cancel();
    for (final c in _c.values) {
      c.dispose();
    }
    _tell.dispose();
    super.dispose();
  }

  Json get _current => {...widget.story, for (final f in _fields) f: _c[f]!.text.trim(), 'competencies': _comps.toList()};

  Future<void> _save([Json extra = const {}]) async {
    _debounce?.cancel();
    final old = (await _store.get(_id))?.data ?? const {};
    await _store.put('story', {...old, for (final f in _fields) f: _c[f]!.text.trim(), 'competencies': _comps.toList(), ...extra}, id: _id);
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _save);
    setState(() {});
  }

  String _context() => careerContext(ref.read(contentProvider), ref.read(storiesProvider));

  Future<bool> _needKey() async {
    if ((await ref.read(aiClientProvider).settings()).hasKey) return false;
    if (mounted) say(context, 'This needs a Claude API key (Settings). You can still write the story yourself and tell it against the clock.');
    return true;
  }

  // ---- the story interview --------------------------------------------------

  Future<void> _interviewTurn([String? answer]) async {
    if (answer != null) await _store.put('chat', {'role': 'user', 'text': answer, 'at': nowUtc().toIso8601String()}, parent: _thread);
    setState(() => _thinking = true);
    final said = await _store.list('chat', parent: _thread);
    if (!mounted) return;
    final reply = await tryAi(
      context,
      () => ref.read(aiClientProvider).chat(
            task: 'story-interview',
            stable: _context(),
            instructions: storyInterviewInstructions(_current),
            turns: [AiTurn.user(storyInterviewOpening(_current)), for (final d in said) AiTurn(d.data['role'] as String, d.data['text'] as String)],
          ),
    );
    if (!mounted) return;
    setState(() => _thinking = false);
    if (reply == null) return;
    if (reply.trim().toUpperCase().startsWith('READY')) return _writeUp();
    await _store.put('chat', {'role': 'assistant', 'text': reply.trim(), 'at': nowUtc().toIso8601String()}, parent: _thread);
  }

  Future<void> _startInterview() async {
    if (await _needKey()) return;
    await _save();
    setState(() => _interviewing = true);
    if ((await _store.list('chat', parent: _thread)).isEmpty) await _interviewTurn();
  }

  Future<void> _writeUp() async {
    final said = await _store.list('chat', parent: _thread);
    if (!said.any((d) => d.data['role'] == 'user')) return;
    setState(() => _writing = true);
    if (!mounted) return;
    final r = await tryAi(
      context,
      () => ref.read(aiClientProvider).structured(
            task: 'story-write',
            stable: _context(),
            instructions: storyWriteInstructions,
            turns: [
              AiTurn.user('Story so far: ${storyInterviewOpening(_current)}\n\nInterview:\n${[for (final d in said) '${d.data['role'] == 'user' ? 'CANDIDATE' : 'COACH'}: ${d.data['text']}'].join('\n\n')}'),
            ],
            schema: storyWriteSchema,
          ),
    );
    if (!mounted) return;
    setState(() {
      _writing = false;
      if (r != null) {
        for (final f in ['title', 'headline', 'situation', 'task', 'action', 'result']) {
          if ('${r[f] ?? ''}'.trim().isNotEmpty) _c[f]!.text = '${r[f]}';
        }
        _interviewing = false;
      }
    });
    if (r != null) {
      await _save({'open': r['stillMissing']});
      if (mounted) say(context, 'Written up from your answers. Read it, correct anything that is off, then check it.');
    }
  }

  // ---- checking and telling -------------------------------------------------

  Future<void> _check() async {
    if (!storyWritten(_current)) return say(context, 'Write at least the action and the result first, or use "Interview me".');
    if (await _needKey()) return;
    await _save();
    setState(() => _checking = true);
    if (!mounted) return;
    final r = await tryAi(
      context,
      () => ref.read(aiClientProvider).structured(task: 'story-check', stable: _context(), instructions: storyCheckInstructions, turns: [AiTurn.user(storyInterviewOpening(_current))], schema: storyCheckSchema),
    );
    if (r != null) await _save({'check': r, 'checkScore': (r['score'] as num).toDouble().clamp(0, 10)});
    if (mounted) setState(() => _checking = false);
  }

  void _startTelling() {
    setState(() {
      _telling = true;
      _delivery = null;
      _tellCheck = null;
      _spoken = null;
      _tell.clear();
    });
    _watch
      ..reset()
      ..start();
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _doneTelling() async {
    if (_tell.text.trim().isEmpty) return say(context, 'Tell the story first: type it, or use Speak my answer.');
    _watch.stop();
    _tick?.cancel();
    final v = _spoken;
    setState(() => _delivery = v == null ? analyse(_tell.text, seconds: _watch.elapsed.inSeconds) : analyse(_tell.text, seconds: v.seconds, longestPause: v.longestPause, pauses: v.pauses));
    if (!(await ref.read(aiClientProvider).settings()).hasKey) return;
    setState(() => _checking = true);
    final question = ((_current['bestFor'] as List? ?? const []).firstOrNull ?? 'Tell me about ${_current['title']}').toString();
    if (!mounted) return;
    final r = await tryAi(
      context,
      () => ref.read(aiClientProvider).structured(
            task: 'story-tell',
            stable: _context(),
            instructions: coachInstructions,
            turns: [AiTurn.user(coachUser({'prompt': question, 'intent': 'Whether the candidate can tell this story clearly from memory: scene, their own part, what they did, the result.'}, _tell.text.trim(), mode: 'drill'))],
            schema: coachSchema,
          ),
    );
    if (r != null) await _save({'toldScore': (r['score'] as num).toDouble().clamp(0, 10), 'toldAt': nowUtc().toIso8601String()});
    if (mounted) {
      setState(() {
        _checking = false;
        _tellCheck = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final s = widget.story;
    final seeded = ref.read(contentProvider).stories.any((x) => x['id'] == _id);
    final spoken = analyse(storySpoken(_current));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageTop(
        title: _c['title']!.text.trim().isEmpty ? 'Untitled story' : _c['title']!.text.trim(),
        kicker: storyWritten(_current) ? '${spoken.words} words  ·  about ${clock(spoken.spokenSeconds)} spoken' : 'Not written yet',
        onBack: widget.onBack,
        backLabel: 'Your stories',
        actions: [
          if (s['checkScore'] != null) ScoreBadge((s['checkScore'] as num).toDouble()),
          if (!seeded)
            JBtn('Delete', quiet: true, danger: true, onTap: () async {
              if (await confirm(context, 'Delete this story?', 'It is removed from your story bank.')) {
                await _store.delete(_id);
                widget.onBack();
              }
            }),
        ],
        below: JSeg<String>(
          items: const [JSegItem('write', 'Write it'), JSegItem('questions', 'Questions it answers'), JSegItem('tell', 'Tell it')],
          value: _tab,
          onChanged: (v) => setState(() => _tab = v),
        ),
      ),
      Expanded(
        child: switch (_tab) {
          'questions' => _questions(context),
          'tell' => _tellView(context),
          _ => _interviewing ? _interviewView(context) : _writeView(context, p, t),
        },
      ),
    ]);
  }

  Widget _writeView(BuildContext context, Palette p, TextTheme t) {
    final s = widget.story;
    final open = [for (final o in s['open'] as List? ?? const []) '$o'];
    final rules = [for (final o in s['guardrails'] as List? ?? const []) '$o'];
    final check = s['check'] as Json?;
    Widget field(String f, String label, {int lines = 3, String hint = ''}) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Label(label),
            TextField(key: Key('story-$f'), controller: _c[f], minLines: lines == 1 ? 1 : lines, maxLines: lines == 1 ? 1 : 14, onChanged: _changed, style: readStyle(context), decoration: writeField(hint)),
          ]),
        );
    return Sheet(width: 860, children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        BusyButton(busy: _writing, filled: true, icon: 'chat', onPressed: _startInterview, label: storyWritten(_current) ? 'Interview me to sharpen it' : 'Interview me to build it'),
        BusyButton(busy: _checking, icon: 'sparkle', onPressed: _check, label: 'Check this story'),
        Text('Saves as you type.', style: t.bodySmall),
      ]),
      field('title', 'Title', lines: 1),
      field('headline', 'The one-sentence version', lines: 1, hint: 'For when they want the short answer first.'),
      field('situation', 'Situation: where, when, what was going on', hint: 'Two sentences. What the software or the team was, and what was wrong.'),
      field('task', 'Task: what was yours to do', lines: 2),
      field('action', 'Action: what you did, step by step', lines: 5, hint: 'Say "I". Three or four concrete steps.'),
      field('result', 'Result: what changed, with a number if you have one', lines: 2, hint: 'Then one sentence on what you took from it.'),
      if (open.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Label('Only you can answer'),
        Bullets(open, color: P.warn),
      ],
      field('notes', open.isEmpty ? 'Anything else that is true and useful' : 'Your answers to the questions above, and anything else that is true'),
      const SizedBox(height: 16),
      const Label('Themes this story carries'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (c, label, _) in storyThemes)
          Tappable(
            label: label,
            toggled: _comps.contains(c),
            onTap: () {
              setState(() => _comps.contains(c) ? _comps.remove(c) : _comps.add(c));
              _save();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: _comps.contains(c) ? p.accentSoft : p.s2,
                borderRadius: BorderRadius.circular(p.radius),
                border: Border.all(color: _comps.contains(c) ? p.accent.withValues(alpha: .45) : p.border),
              ),
              child: Text(label, style: t.labelLarge?.copyWith(color: _comps.contains(c) ? p.text : p.textMuted)),
            ),
          ),
      ]),
      if (rules.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Label('Keep it honest'),
        Bullets(rules, color: P.bad),
      ],
      if (check != null) ...[
        const SizedBox(height: 20),
        const Heading('The coach\'s read'),
        const SizedBox(height: 8),
        CoachResult(check),
      ],
    ]);
  }

  Widget _interviewView(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final chat = ref.watch(docsProvider(('chat', _thread))).value ?? const <Doc>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 6),
        child: Row(children: [
          Expanded(child: Text('Answer in your own words. The coach asks one thing at a time and never supplies a fact; "I don\'t remember" is a fine answer.', style: t.bodyMedium?.copyWith(color: p.textMuted))),
          BusyButton(busy: _writing, icon: 'pen', onPressed: chat.any((d) => d.data['role'] == 'user') ? _writeUp : null, label: 'Write it up now'),
          const SizedBox(width: 8),
          JBtn('Back to the story', quiet: true, onTap: () => setState(() => _interviewing = false)),
        ]),
      ),
      Expanded(child: ChatList(messages: [for (final d in chat) ChatMessage.of(d.data, them: 'Coach')], typing: _thinking ? 'The coach' : null)),
      Composer(enabled: !_thinking && !_writing, hint: 'Your answer', onSend: _interviewTurn, onVoice: (_) {}),
    ]);
  }

  Widget _questions(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final bank = ref.watch(contentProvider).questions.where((q) => _comps.contains(q.competency)).toList()
      ..sort((a, b) => b.frequency.compareTo(a.frequency));
    if (_comps.isEmpty) return const EmptyBody('No themes chosen yet.', 'On "Write it", mark the themes this story carries; the questions it can answer appear here.');
    return Sheet(width: 860, children: [
      Text('${bank.length} questions in the bank ask for a theme this story carries. For each, change only the first sentence: answer the question asked, then tell the same story.', style: readStyle(context).copyWith(color: p.textMuted)),
      const SizedBox(height: 10),
      for (final q in bank.take(40))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text(q.prompt, style: t.titleLarge)),
                const SizedBox(width: 10),
                Pill(q.competency.replaceAll('-', ' ')),
                if (q.frequency == 3) const Padding(padding: EdgeInsets.only(left: 6), child: Pill('asked often', color: P.warn)),
              ]),
              const SizedBox(height: 4),
              Text(q.intent, style: readStyle(context).copyWith(color: p.textMuted)),
            ]),
          ),
        ),
      if (bank.length > 40) Text('And ${bank.length - 40} more.', style: t.bodySmall),
    ]);
  }

  Widget _tellView(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final secs = _watch.elapsed.inSeconds;
    final s = widget.story;
    final question = ((_current['bestFor'] as List? ?? const []).firstOrNull ?? 'Tell me about ${_current['title']}').toString();
    if (!_telling) {
      return Sheet(width: 820, children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Heading('Tell it from memory'),
            const SizedBox(height: 6),
            Text('The written story is hidden and the clock runs. Aim for 1:30 to 2:00. Speak it or type it; either way you get your time, pace and filler words, and with a key the coach compares what you said with what you wrote.', style: readStyle(context).copyWith(color: p.textMuted)),
            const SizedBox(height: 12),
            Row(children: [
              JBtn('Start', icon: 'play', primary: true, onTap: storyWritten(_current) ? _startTelling : null),
              const SizedBox(width: 12),
              if (!storyWritten(_current)) Text('Write the story first.', style: t.bodyMedium?.copyWith(color: p.ratingLow)),
              if (s['toldScore'] != null) ...[Text('Last time: ', style: t.bodyMedium?.copyWith(color: p.textMuted)), ScoreBadge((s['toldScore'] as num).toDouble())],
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        const Label('Check yourself against these when no coach is on'),
        const Bullets([
          'The scene took two sentences, and said what the software or team was.',
          'You said what was yours to do.',
          'You gave at least three things you did, with "I".',
          'You ended on what changed, with a number or a before-and-after.',
          'You could have stopped there. You did not trail off.',
        ]),
      ]);
    }
    final open = _delivery == null && !_checking;
    return Sheet(width: 820, children: [
      Text(question, style: t.headlineMedium),
      const SizedBox(height: 10),
      Row(children: [
        VoiceBar(
          enabled: open,
          onText: (text) => setState(() => _tell.text = text),
          onDone: (r) => setState(() {
            _spoken = r;
            _watch.stop();
          }),
        ),
        const SizedBox(width: 12),
        if (_spoken == null && !ref.watch(voiceProvider).active) Text(clock(secs), style: context.mono.copyWith(fontSize: 15, color: secs > 150 ? p.ratingLow : (secs >= 60 ? p.ratingHigh : p.textMuted))),
      ]),
      const SizedBox(height: 12),
      TextField(key: const Key('story-tell'), controller: _tell, minLines: 8, maxLines: 20, enabled: open, style: readStyle(context), decoration: writeField('Tell the story as you would in the room.')),
      const SizedBox(height: 12),
      if (open || _checking)
        Row(children: [
          BusyButton(busy: _checking, filled: true, icon: 'check', onPressed: _doneTelling, label: 'Done'),
          const SizedBox(width: 8),
          JBtn('Cancel', quiet: true, onTap: () => setState(() => _telling = false)),
        ]),
      if (_delivery != null && !_checking) ...[
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Label('Delivery'),
            Text(
              [
                '${_delivery!.words} words',
                if (_delivery!.seconds != null) clock(_delivery!.seconds!),
                if (_delivery!.wpm != null) '${_delivery!.wpm} words a minute',
                '${_delivery!.fillerCount} fillers',
                '${_delivery!.hedgeCount} hedges',
                if (_delivery!.spoken) 'longest pause ${_delivery!.longestPause}s',
              ].join('  ·  '),
              style: context.mono,
            ),
            if (_delivery!.notes.isNotEmpty) ...[const SizedBox(height: 8), Bullets(_delivery!.notes, color: p.ratingLow)],
          ]),
        ),
        const SizedBox(height: 12),
        if (_tellCheck != null) CoachResult(_tellCheck!),
        const SizedBox(height: 12),
        const Label('What you wrote'),
        Panel(child: Text(storySpoken(_current), style: readStyle(context))),
        const SizedBox(height: 12),
        Row(children: [
          JBtn('Tell it again', icon: 'refresh', primary: true, onTap: _startTelling),
          const SizedBox(width: 8),
          JBtn('Finish', quiet: true, onTap: () => setState(() => _telling = false)),
        ]),
      ],
    ]);
  }
}
