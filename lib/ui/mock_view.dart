import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_client.dart';
import '../data/content.dart';
import '../data/db.dart';
import '../engine/delivery.dart';
import '../engine/engine.dart';
import '../engine/sessions.dart';
import '../engine/voice.dart';
import 'chat.dart';
import 'session_screen.dart';
import 'ui.dart';

/// Questions in one mock, by pace.
int mockLength(int intensity) => const [0, 5, 7, 9, 12, 15][intensity.clamp(1, 5)];

/// Seconds allowed per answer in a timed mock.
const answerLimit = 120;

/// The mock's running order: opens with background and motivation, closes with
/// the closing question, and fills the middle with the weakest and least
/// practised questions, spread across categories.
List<Doc> mockPlan(List<Doc> items, int intensity) {
  final active = items.where((d) => isActive(d.data)).toList();
  final n = mockLength(intensity);
  Doc? first(String cat) => active.where((d) => d.data['category'] == cat).firstOrNull;
  final open = [?first('background'), ?first('motivation')];
  final close = first('closing');
  final middle = active.where((d) => !open.contains(d) && d != close).toList()
    ..sort((a, b) => ((a.data['last'] as num?) ?? -1).compareTo((b.data['last'] as num?) ?? -1));
  final byCat = <String, List<Doc>>{};
  for (final d in middle) {
    byCat.putIfAbsent(d.data['category'] as String, () => []).add(d);
  }
  final picked = <Doc>[];
  final want = n - open.length - (close == null ? 0 : 1);
  while (picked.length < want && byCat.values.any((l) => l.isNotEmpty)) {
    for (final cat in Content.categories) {
      final l = byCat[cat];
      if (l != null && l.isNotEmpty && picked.length < want) picked.add(l.removeAt(0));
    }
  }
  picked.sort((a, b) => (a.data['order'] as int).compareTo(b.data['order'] as int));
  return [...open, ...picked, ?close];
}

class MockView extends ConsumerStatefulWidget {
  const MockView({super.key, required this.session, required this.items, required this.mocks});
  final Doc session;
  final List<Doc> items, mocks;

  @override
  ConsumerState<MockView> createState() => _MockViewState();
}

class _MockViewState extends ConsumerState<MockView> {
  String? _openId;
  bool _thinking = false, _timed = true, _spoken = false;
  final _watch = Stopwatch();
  Timer? _tick;
  VoiceResult? _voice;

  Store get _store => ref.read(storeProvider);
  Sessions get _sessions => ref.read(sessionsProvider);
  int get _depth => followUpDepth(widget.session.data['intensity'] as int);

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<bool> _hasKey() async => (await ref.read(aiClientProvider).settings()).hasKey;

  Json _turn(String role, String text, {String? meta}) => {'role': role, 'text': text, 'at': nowUtc().toIso8601String(), 'meta': ?meta};

  void _startClock() {
    if (_watch.isRunning) return;
    _watch
      ..reset()
      ..start();
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _start() async {
    final plan = mockPlan(widget.items, widget.session.data['intensity'] as int);
    if (plan.isEmpty) return say(context, 'Add questions to the plan first.');
    final live = await _hasKey();
    final id = await _store.put(
      'mock',
      {
        'startedAt': nowUtc().toIso8601String(),
        'live': live,
        'timed': _timed,
        'spoken': _spoken,
        'plan': [for (final d in plan) {'id': d.id, 'prompt': d.data['prompt'], 'followUps': d.data['followUps']}],
        'idx': 0,
        'fu': 0,
        'turns': <Json>[],
      },
      parent: widget.session.id,
    );
    setState(() => _openId = id);
    await _advance(id, null);
  }

  /// Takes the candidate's reply (null to open) and gets the interviewer's next line.
  Future<void> _advance(String id, String? reply) async {
    final m = (await _store.get(id))!.data;
    String? meta;
    if (reply != null) {
      _watch.stop();
      _tick?.cancel();
      final v = _voice;
      _voice = null;
      final took = v?.seconds ?? _watch.elapsed.inSeconds;
      final d = analyse(reply, seconds: took, longestPause: v?.longestPause, pauses: v?.pauses);
      meta = [
        if (v != null) 'spoken',
        if (took > 0) clock(took),
        '${d.words} words',
        if (d.wpm != null) '${d.wpm} a minute',
        if (d.fillerCount > 0) '${d.fillerCount} filler${d.fillerCount == 1 ? '' : 's'}',
        if ((v?.longestPause ?? 0) >= 4) 'longest pause ${v!.longestPause}s',
        if (m['timed'] == true && took > answerLimit) 'over the ${clock(answerLimit)} limit',
      ].join('  ·  ');
      _watch.reset();
    }
    final turns = [...(m['turns'] as List).cast<Json>(), if (reply != null) _turn('user', reply, meta: meta)];
    final plan = (m['plan'] as List).cast<Json>();
    var idx = m['idx'] as int, fu = m['fu'] as int;
    await _store.patch(id, {'turns': turns});
    if (!mounted) return;
    setState(() => _thinking = true);
    String line;
    var ended = false;
    if (m['live'] == true) {
      final hasNext = idx + 1 < plan.length;
      final director = reply == null
          ? 'Begin the interview. Greet the candidate in one sentence, then ask planned question 1: "${plan[0]['prompt']}". Use move "next".'
          : 'Planned question just answered: "${plan[idx]['prompt']}". Follow-ups used on it: $fu of $_depth.${fu >= _depth ? ' You must move on.' : ''} '
              '${hasNext ? 'Next planned question: "${plan[idx + 1]['prompt']}".' : 'No questions remain: use move "end".'}';
      final r = await tryAi(context, () => _sessions.interviewerTurn(widget.session, turns, director: director, maxFollowUps: _depth));
      if (r == null) {
        if (mounted) setState(() => _thinking = false);
        return;
      }
      line = '${r['say']}';
      if (reply != null) {
        if (r['move'] == 'followup' && fu < _depth + 1) {
          fu++;
        } else if (r['move'] == 'end' || !hasNext) {
          ended = true;
        } else {
          idx++;
          fu = 0;
        }
      }
    } else {
      // No key: the questions and their bank follow-ups, in order.
      final follow = (plan[idx]['followUps'] as List? ?? const []).cast<String>();
      if (reply == null) {
        line = 'Thanks for making the time. ${plan[0]['prompt']}';
      } else if (fu < _depth && fu < follow.length) {
        line = follow[fu++];
      } else if (idx + 1 < plan.length) {
        idx++;
        fu = 0;
        line = '${plan[idx]['prompt']}';
      } else {
        line = 'That is everything I wanted to cover. Thank you.';
        ended = true;
      }
    }
    await _store.patch(id, {'turns': [...turns, _turn('assistant', line)], 'idx': idx, 'fu': fu});
    if (!mounted) return;
    setState(() => _thinking = false);
    if (m['spoken'] == true) await speakAloud(ref, context, line);
    if (ended) await _finish(id);
  }

  Future<void> _finish(String id) async {
    _watch.stop();
    _tick?.cancel();
    final m = (await _store.get(id))!.data;
    final turns = (m['turns'] as List).cast<Json>();
    await _store.patch(id, {'endedAt': nowUtc().toIso8601String()});
    if (!turns.any((t) => t['role'] == 'user') || m['live'] != true || !mounted) return;
    setState(() => _thinking = true);
    final r = await tryAi(context, () => _sessions.debrief(widget.session, turns));
    if (r != null) await _store.patch(id, {'debrief': r, 'score': (r['score'] as num).toDouble().clamp(0, 10)});
    if (mounted) setState(() => _thinking = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final byId = {for (final d in widget.mocks) d.id: d};
    final open = byId[_openId];
    if (open == null) return _list();
    final m = open.data;
    final turns = (m['turns'] as List).cast<Json>();
    final ended = m['endedAt'] != null;
    final plan = (m['plan'] as List);
    final them = '${widget.session.data['company']}'.isEmpty ? 'Interviewer' : 'Interviewer, ${widget.session.data['company']}';
    final secs = _watch.elapsed.inSeconds;
    final timed = m['timed'] == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 2, 28, 6),
        child: Row(children: [
          JBtn('All mocks', icon: 'back', quiet: true, onTap: () => setState(() => _openId = null)),
          const Spacer(),
          if (!ended) ...[
            Text('Question ${(m['idx'] as int) + 1} of ${plan.length}', style: t.bodyMedium?.copyWith(color: p.textMuted)),
            const SizedBox(width: 12),
            JBtn('End the interview', onTap: _thinking ? null : () => _finish(open.id)),
          ],
        ]),
      ),
      Expanded(
        child: ended
            ? _Debrief(mock: open, them: them, thinking: _thinking, onSelfScore: (v) => _store.patch(open.id, {'score': v}))
            : ChatList(messages: [for (final t in turns) ChatMessage.of(t, them: them)], typing: _thinking ? 'The interviewer' : null),
      ),
      if (!ended)
        Composer(
          enabled: !_thinking,
          onFirstKey: _startClock,
          onVoice: (r) => _voice = r,
          leading: Text(
            timed ? clock((answerLimit - secs).clamp(0, answerLimit)) : clock(secs),
            style: context.mono.copyWith(fontSize: 15, color: timed && secs > answerLimit ? p.danger : (timed && secs > answerLimit - 20 ? p.ratingLow : p.textMuted)),
          ),
          onSend: (text) => _advance(open.id, text),
        ),
    ]);
  }

  Widget _list() {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    final mocks = [...widget.mocks]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final n = mockLength(widget.session.data['intensity'] as int);
    return Sheet(width: 760, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Heading('Mock interview'),
          const SizedBox(height: 6),
          Text(
            'About $n questions from your plan, weakest and least practised first, with up to $_depth follow-up${_depth == 1 ? '' : 's'} each. No notes are shown. '
            'With a key, the interviewer plays this role\'s interviewer, probes what you say, and debriefs you at the end. Without one, it asks the planned questions and their standard follow-ups and you rate yourself.',
            style: readStyle(context).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 14),
          Row(children: [
            JChk(_timed, label: 'Timed answers', onChanged: (v) => setState(() => _timed = v)),
            Text('Timed: ${clock(answerLimit)} per answer, counted down', style: t.bodyMedium),
            const SizedBox(width: 18),
            JChk(_spoken, label: 'Interviewer speaks', onChanged: (v) => setState(() => _spoken = v)),
            Text('Interviewer speaks each question aloud', style: t.bodyMedium),
          ]),
          const SizedBox(height: 6),
          Text('Answer aloud with "Speak my answer": it is transcribed on this PC, and your time, pace, pauses and filler words appear under each answer.', style: t.bodySmall),
          const SizedBox(height: 14),
          JBtn('Start a mock interview', icon: 'play', primary: true, onTap: _start),
        ]),
      ),
      if (mocks.isNotEmpty) ...[
        const SizedBox(height: 22),
        const Label('Past mocks'),
        for (final d in mocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              onTap: () => setState(() => _openId = d.id),
              child: Row(children: [
                Expanded(child: Text(_when(d.createdAt), style: t.bodyLarge)),
                if (d.data['endedAt'] == null) const Pill('In progress', color: P.accent) else ScoreBadge((d.data['score'] as num?)?.toDouble()),
                const SizedBox(width: 8),
                JBtn('Delete', quiet: true, danger: true, onTap: () async {
                  if (await confirm(context, 'Delete this mock?', 'Its transcript and debrief are removed.')) await _store.delete(d.id);
                }),
              ]),
            ),
          ),
      ],
    ]);
  }
}

String _when(DateTime t) {
  final l = t.toLocal();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[l.month - 1]} ${l.day}, ${l.hour % 12 == 0 ? 12 : l.hour % 12}:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'AM' : 'PM'}';
}

class _Debrief extends StatelessWidget {
  const _Debrief({required this.mock, required this.them, required this.thinking, required this.onSelfScore});
  final Doc mock;
  final String them;
  final bool thinking;
  final ValueChanged<double> onSelfScore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final m = mock.data;
    final d = m['debrief'] as Json?;
    final turns = (m['turns'] as List).cast<Json>();
    List<String> list(String k) => [for (final e in d?[k] as List? ?? const []) '$e'];
    return Sheet(width: 820, children: [
      if (thinking)
        Panel(child: Row(children: [const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.6)), const SizedBox(width: 12), Text('Writing your debrief…', style: readStyle(context))]))
      else if (d != null)
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ScoreBadge((d['score'] as num).toDouble(), large: true),
              const SizedBox(width: 18),
              Expanded(child: Padding(padding: const EdgeInsets.only(top: 4), child: Text('${d['readiness']}', style: readStyle(context).weight(600)))),
            ]),
            const SizedBox(height: 12),
            Text('${d['summary']}', style: readStyle(context)),
            const SizedBox(height: 14),
            const Label('Practise before the real one'),
            Bullets(list('drillNext'), color: P.accent),
            const SizedBox(height: 10),
            const Label('Improve'),
            Bullets(list('improvements'), color: P.warn),
            const SizedBox(height: 10),
            const Label('Strengths'),
            Bullets(list('strengths'), color: P.good),
            const SizedBox(height: 10),
            const Label('Question by question'),
            for (final q in (d['perQuestion'] as List? ?? const []).cast<Json>())
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text('${q['question']}', style: readStyle(context).weight(600))),
                    const SizedBox(width: 10),
                    Text(scoreText((q['score'] as num).toDouble()), style: context.mono.copyWith(color: scoreColor((q['score'] as num).toDouble()))),
                  ]),
                  Text('${q['note']}', style: readStyle(context).copyWith(color: p.textMuted)),
                  Text('Change: ${q['better']}', style: readStyle(context)),
                ]),
              ),
          ]),
        )
      else
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('How did that go?', style: t.titleLarge),
            const SizedBox(height: 4),
            Text('Rate the interview as a whole. Read your answers below against your prepared ones first.', style: t.bodyMedium?.copyWith(color: p.textMuted)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              for (final (label, score) in const [('Poor', 3.0), ('Shaky', 5.0), ('Passable', 7.0), ('Strong', 8.5), ('Excellent', 9.5)])
                JBtn(label, primary: (m['score'] as num?)?.toDouble() == score, onTap: () => onSelfScore(score)),
            ]),
          ]),
        ),
      const SizedBox(height: 22),
      const Label('Transcript'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final turn in turns)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(turn['role'] == 'user' ? 'You' : them, style: t.bodyMedium?.copyWith(color: turn['role'] == 'user' ? p.text : p.ink).weight(600)),
                Text('${turn['text']}', style: readStyle(context)),
                if (turn['meta'] != null) Text('${turn['meta']}', style: t.bodySmall?.copyWith(color: p.textFaint)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}
