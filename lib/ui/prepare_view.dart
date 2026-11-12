import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/content.dart';
import '../data/db.dart';
import '../engine/delivery.dart';
import '../engine/engine.dart';
import '../engine/sessions.dart';
import '../terra/smooth_scroll.dart';
import 'session_screen.dart';
import 'ui.dart';

/// Build every answer before being tested on it: what the question is really
/// asking, which of your stories fits, your draft, and the coach's read of it.
class PrepareView extends ConsumerStatefulWidget {
  const PrepareView({super.key, required this.session, required this.items});
  final Doc session;
  final List<Doc> items;

  @override
  ConsumerState<PrepareView> createState() => _PrepareViewState();
}

class _PrepareViewState extends ConsumerState<PrepareView> {
  String? _selected;
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final active = widget.items.where((d) => isActive(d.data)).toList();
    if (active.isEmpty) return const EmptyBody('No questions in the plan.', 'Raise the pace on Overview, or build the brief for questions specific to this posting.');
    // Opens on the first question not started, then stays where the learner
    // is: a draft autosaving must not move them to another question.
    if (!active.any((d) => d.id == _selected)) {
      _selected = active.firstWhere((d) => d.data['state'] == 'new', orElse: () => active.first).id;
    }
    final current = active.firstWhere((d) => d.id == _selected);
    final ordered = [for (final cat in Content.categories) ...active.where((d) => d.data['category'] == cat)];
    final index = ordered.indexOf(current);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 320,
        decoration: BoxDecoration(border: Border(right: BorderSide(color: p.border))),
        child: MiddleScroll(
          controller: _scroll,
          child: ListView(controller: _scroll, padding: const EdgeInsets.only(bottom: 24), children: [
          for (final cat in Content.categories)
            if (active.any((d) => d.data['category'] == cat)) ...[
              JGl(categoryNames[cat] ?? cat, right: '${active.where((d) => d.data['category'] == cat && d.data['state'] == 'ready').length}/${active.where((d) => d.data['category'] == cat).length}'),
              for (final d in active.where((d) => d.data['category'] == cat)) _QuestionRow(item: d, selected: d.id == current.id, onTap: () => setState(() => _selected = d.id)),
            ],
        ]),
        ),
      ),
      Expanded(
        child: _Detail(
          key: ValueKey(current.id),
          session: widget.session,
          item: current,
          onNext: index + 1 < ordered.length ? () => setState(() => _selected = ordered[index + 1].id) : null,
        ),
      ),
    ]);
  }
}

class _QuestionRow extends StatefulWidget {
  const _QuestionRow({required this.item, required this.selected, required this.onTap});
  final Doc item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_QuestionRow> createState() => _QuestionRowState();
}

class _QuestionRowState extends State<_QuestionRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final d = widget.item.data;
    final (icon, color, label) = switch (d['state']) {
      'ready' => ('check-circle', p.ratingHigh, 'Ready'),
      'drafted' => ('pen', p.accent, 'Drafted'),
      _ => ('dot', p.textFaint, 'Not started'),
    };
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tappable(
        label: '${d['prompt']}',
        selected: widget.selected,
        radius: 0,
        pressScale: 1,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
          decoration: BoxDecoration(
            color: widget.selected ? p.s3 : (_hover ? p.s2 : null),
            border: Border(left: BorderSide(color: widget.selected ? p.accent : Colors.transparent, width: 2)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: LineIcon(icon, size: 13, color: color, semanticLabel: label)),
            const SizedBox(width: 9),
            Expanded(child: Text('${d['prompt']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: widget.selected ? p.text : p.textMuted))),
            if (d['source'] == 'tailored') Padding(padding: const EdgeInsets.only(left: 6, top: 2), child: LineIcon('sparkle', size: 12, color: p.accent, semanticLabel: 'Written for this posting')),
          ]),
        ),
      ),
    );
  }
}

class _Detail extends ConsumerStatefulWidget {
  const _Detail({super.key, required this.session, required this.item, this.onNext});
  final Doc session, item;
  final VoidCallback? onNext;

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  late final _draft = TextEditingController(text: '${widget.item.data['draft'] ?? ''}');
  late final Sessions _sessions = ref.read(sessionsProvider);
  Timer? _debounce;
  bool _drafting = false, _coaching = false, _dirty = false;
  List<String> _needs = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    if (_dirty) _sessions.saveDraft(widget.item, _draft.text);
    _draft.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _save);
    setState(() {});
  }

  Future<void> _save({bool? ready}) async {
    _debounce?.cancel();
    _dirty = false;
    await _sessions.saveDraft(widget.item, _draft.text, ready: ready);
  }

  Future<void> _writeDraft() async {
    setState(() => _drafting = true);
    await _save();
    if (!mounted) return;
    final r = await tryAi(context, () => _sessions.draft(widget.session, widget.item));
    if (!mounted) return;
    setState(() {
      _drafting = false;
      if (r != null) {
        _draft.text = '${r['answer']}';
        _needs = [for (final n in r['needsFromYou'] as List? ?? const []) '$n'];
      }
    });
    if (r != null) await _save();
  }

  Future<void> _coach() async {
    if (_draft.text.trim().isEmpty) return say(context, 'Write a draft first, or have one drafted for you.');
    setState(() => _coaching = true);
    await _save();
    if (!mounted) return;
    final r = await tryAi(context, () => _sessions.coach(widget.session, widget.item, _draft.text.trim(), mode: 'draft'));
    if (r != null) await ref.read(storeProvider).patch(widget.item.id, {'coach': r});
    if (mounted) setState(() => _coaching = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final d = widget.item.data;
    final q = ref.watch(contentProvider).question(d['qid'] as String?);
    final stories = storiesFor(ref.watch(storiesProvider), '${d['competency']}');
    final coach = d['coach'] as Json?;
    final del = analyse(_draft.text);
    final ready = d['state'] == 'ready';
    final length = del.words == 0 ? '' : '${del.words} words  ·  about ${clock(del.spokenSeconds)} spoken${del.words < 130 ? '  ·  short' : del.words > 300 ? '  ·  long' : ''}';
    return Sheet(width: 820, padding: const EdgeInsets.fromLTRB(28, 14, 28, 56), children: [
      Text('${d['prompt']}', style: t.headlineMedium),
      if (q != null && q.variants.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Also asked as: ${q.variants.join('  ·  ')}', style: t.bodySmall?.copyWith(color: p.textFaint))),
      const SizedBox(height: 18),
      const Label('What they are really asking'),
      Text('${d['intent']}', style: readStyle(context)),
      const SizedBox(height: 16),
      Label('A strong answer (${d['framework'] ?? 'STAR'})'),
      Bullets([for (final g in d['guide'] as List? ?? const []) '$g'], color: P.good),
      if ((d['pitfalls'] as List? ?? const []).isNotEmpty) ...[
        const SizedBox(height: 10),
        const Label('Avoid'),
        Bullets([for (final g in d['pitfalls'] as List) '$g'], color: P.bad),
      ],
      if ('${d['model'] ?? ''}'.trim().isNotEmpty) ...[
        const SizedBox(height: 16),
        const Label('A model answer, to adapt and never to recite'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: p.s2, borderRadius: BorderRadius.circular(p.radius)),
          child: Text('${d['model']}', style: context.quote),
        ),
      ],
      if (stories.isNotEmpty && d['source'] != 'skill') ...[
        const SizedBox(height: 16),
        const Label('Your stories that fit'),
        for (final s in stories.take(4)) _StoryTile(s),
      ],
      const SizedBox(height: 18),
      Row(children: [const Expanded(child: Label('Your answer')), Text(length, style: t.bodySmall?.copyWith(color: p.textFaint))]),
      TextField(
        key: const Key('draft'),
        controller: _draft,
        minLines: 8,
        maxLines: 24,
        onChanged: _changed,
        style: readStyle(context),
        decoration: writeField('Write it the way you would say it. Notes are fine to start; the coach will help you shape them.'),
      ),
      if (_needs.isNotEmpty) ...[
        const SizedBox(height: 10),
        const Label('To make this yours, answer these'),
        Bullets(_needs, color: P.accent),
      ],
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        BusyButton(busy: _coaching, filled: true, onPressed: _drafting ? null : _coach, label: 'Coach this answer'),
        BusyButton(busy: _drafting, icon: 'pen', onPressed: _coaching ? null : _writeDraft, label: _draft.text.trim().isEmpty ? 'Draft it from my history' : 'Redraft from my history'),
        JBtn(
          ready ? 'Not ready yet' : 'Ready, next question',
          icon: ready ? 'undo' : 'check',
          onTap: () async {
            if (!ready && _draft.text.trim().isEmpty) return say(context, 'Write the answer before marking it ready.');
            await _save(ready: !ready);
            if (!ready) widget.onNext?.call();
          },
        ),
        JBtn('Leave this one out', quiet: true, onTap: () => _sessions.setSkipped(widget.item, true)),
      ]),
      if (del.notes.isNotEmpty && del.words >= 60) ...[const SizedBox(height: 10), Bullets(del.notes, color: p.ratingLow)],
      if (coach != null) ...[
        const SizedBox(height: 18),
        CoachResult(coach, onUse: (text) {
          setState(() => _draft.text = text);
          _save();
        }),
      ],
    ]);
  }
}

class _StoryTile extends StatefulWidget {
  const _StoryTile(this.story);
  final Json story;

  @override
  State<_StoryTile> createState() => _StoryTileState();
}

class _StoryTileState extends State<_StoryTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final story = widget.story;
    final parts = [
      for (final k in ['situation', 'task', 'action', 'result'])
        if ('${story[k] ?? ''}'.trim().isNotEmpty) (k, '${story[k]}'),
    ];
    final notes = '${story['notes'] ?? ''}'.trim();
    final open = [for (final o in story['open'] as List? ?? const []) '$o'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Tappable(
        label: '${story['title']}',
        toggled: _open,
        pressScale: 1,
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            LineIcon(_open ? 'down' : 'right', size: 12, color: p.textFaint),
            const SizedBox(width: 8),
            Text('${story['title']}', style: t.bodyLarge),
            if (parts.length < 3) Padding(padding: const EdgeInsets.only(left: 10), child: Text('not written yet', style: t.bodySmall?.copyWith(color: p.ratingLow))),
          ]),
        ),
      ),
      if (_open)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 0, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (k, v) in parts)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${k[0].toUpperCase()}${k.substring(1)}  ', style: readStyle(context).copyWith(color: p.ink).weight(600)),
                  TextSpan(text: v, style: readStyle(context)),
                ])),
              ),
            if (notes.isNotEmpty) Text('Your notes: $notes', style: readStyle(context).copyWith(color: p.textMuted)),
            if (parts.isEmpty) Text('Fill this story in under Your stories.', style: readStyle(context).copyWith(color: p.textMuted)),
            if (open.isNotEmpty && notes.isEmpty) ...[
              const SizedBox(height: 4),
              Text('Still missing', style: t.bodySmall?.copyWith(color: p.ratingLow)),
              Bullets(open, color: p.ratingLow),
            ],
          ]),
        ),
    ]);
  }
}
