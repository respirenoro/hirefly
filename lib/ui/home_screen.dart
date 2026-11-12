import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_client.dart';
import '../data/content.dart';
import '../data/db.dart';
import '../engine/engine.dart';
import 'shell.dart';
import 'ui.dart';

/// Days until an interview date (`yyyy-MM-dd`), or null when none is set.
int? daysUntil(Object? date) {
  final d = DateTime.tryParse('${date ?? ''}');
  if (d == null) return null;
  final now = DateTime.now();
  return DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
}

String countdown(int days) => days < 0 ? 'interview was ${-days} day${days == -1 ? '' : 's'} ago' : (days == 0 ? 'interview today' : (days == 1 ? 'interview tomorrow' : 'interview in $days days'));

/// One thing worth doing now, and where it is done.
class _Todo {
  _Todo(this.weight, this.text, this.detail, this.go);
  final double weight;
  final String text, detail;
  final VoidCallback go;
}

/// Today: what to do next across every role and skill, then each role's standing.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    final sessions = [...ref.watch(docsProvider(('session', null))).value ?? const <Doc>[]]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final hasKey = ref.watch(aiSettingsProvider).value?.hasKey ?? true;
    final content = ref.watch(contentProvider);
    final progress = ref.watch(lessonProgressProvider);
    final stories = ref.watch(storiesProvider);
    final now = DateTime.now();
    final todos = <_Todo>[];

    for (final s in sessions.where((s) => s.data['status'] != 'paused')) {
      final items = [for (final d in ref.watch(docsProvider(('item', s.id))).value ?? const <Doc>[]) d.data].where(isActive).toList();
      final mocks = ref.watch(docsProvider(('mock', s.id))).value ?? const <Doc>[];
      final name = '${s.data['company']}'.trim().isEmpty ? '${s.data['role']}' : '${s.data['company']}';
      final days = daysUntil(s.data['interviewDate']);
      // Nearer interviews outrank everything else.
      final urgency = days == null ? 1.0 : (days <= 0 ? 4.0 : (days <= 3 ? 3.0 : (days <= 7 ? 2.0 : 1.2)));
      final left = days == null || days < 1 ? 1 : days;
      final unwritten = items.where((i) => i['state'] == 'new').length;
      final due = items.where((i) => (i['attempts'] as int? ?? 0) > 0 && isDue(i, now)).length;
      final untested = items.where((i) => i['state'] != 'new' && (i['attempts'] as int? ?? 0) == 0).length;
      if (s.data['brief'] == null && hasKey && '${s.data['posting']}'.trim().isNotEmpty) {
        todos.add(_Todo(urgency * 5, 'Build the brief for $name', 'What the posting screens for, your edge, and where you will be pressed', () => ref.go('role', s.id)));
      }
      if (unwritten > 0) {
        final n = days == null ? unwritten : (unwritten / left).ceil();
        todos.add(_Todo(urgency * 3, 'Prepare $n answer${n == 1 ? '' : 's'} for $name', days == null ? '$unwritten not started' : '$unwritten not started, ${countdown(days)}', () => ref.go('role', s.id, 'prepare')));
      }
      if (due + untested > 0) {
        todos.add(_Todo(urgency * (due > 0 ? 3.5 : 2.5), 'Practise ${due + untested} answer${due + untested == 1 ? '' : 's'} from memory for $name',
            [if (due > 0) '$due due for review', if (untested > 0) '$untested written but never said without notes'].join(', '), () => ref.go('role', s.id, 'practice')));
      }
      if (mocks.isEmpty && items.where((i) => i['state'] != 'new').length >= 5) {
        todos.add(_Todo(urgency * 2.8, 'Sit a mock interview for $name', 'You have enough answers ready to be tested under pressure', () => ref.go('role', s.id, 'mock')));
      }
    }
    final gaps = stories.where((s) => (s['open'] as List? ?? const []).isNotEmpty && '${s['notes'] ?? ''}'.trim().isEmpty).length;
    if (gaps > 0) {
      todos.add(_Todo(2.2, 'Fill in $gaps stor${gaps == 1 ? 'y' : 'ies'} with details only you know', 'A real number or incident is what turns a fair answer into a strong one', () => ref.go('stories')));
    }
    for (final m in content.modules) {
      final lessons = m.lessons.toList();
      final next = lessons.where((l) => !lessonDone(progress[l.id])).firstOrNull;
      if (lessons.any((l) => progress[l.id] != null) && next != null) {
        todos.add(_Todo(1.5, 'Continue ${m.title}: ${next.title}', '${lessons.where((l) => lessonDone(progress[l.id])).length} of ${lessons.length} lessons done', () => ref.go('lesson', m.id, next.id)));
      }
    }
    todos.sort((a, b) => b.weight.compareTo(a.weight));

    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageTop(title: 'Today', kicker: '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}', actions: [JBtn('New role', icon: 'plus', primary: true, onTap: () => ref.go('new-role'))]),
      Expanded(
        child: Sheet(width: 980, children: [
          if (!hasKey) ...[
            Panel(
              raised: true,
              onTap: () => ref.go('settings'),
              child: Row(children: [
                LineIcon('sparkle', size: 16, color: p.accent),
                const SizedBox(width: 12),
                Expanded(child: Text('Add a Claude API key in Settings to turn on the coach, the live interviewer and tailored questions. Without one you can still prepare answers, practise with self-rating and do every lesson and lab.', style: readStyle(context))),
              ]),
            ),
            const SizedBox(height: 18),
          ],
          const Label('Do next'),
          if (todos.isEmpty)
            Panel(
              child: Text(
                sessions.isEmpty
                    ? 'Start with a role: give HireFly the posting and the resume you sent, and it builds a plan from the question bank for that job. Or open a skill on the left and take its first lesson.'
                    : 'Nothing is waiting. Every answer has been practised recently; they come back when they are due.',
                style: readStyle(context).copyWith(color: p.textMuted),
              ),
            )
          else
            Container(
              decoration: p.panel(),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final (i, todo) in todos.take(7).indexed) ...[
                  if (i > 0) Container(height: 1, color: p.border),
                  _TodoRow(todo, first: i == 0),
                ],
              ]),
            ),
          const SizedBox(height: 26),
          const Label('Roles'),
          if (sessions.isEmpty)
            Text('No roles yet.', style: t.bodyMedium?.copyWith(color: p.textFaint))
          else
            Wrap(spacing: 12, runSpacing: 12, children: [for (final s in sessions) SizedBox(width: 314, child: _SessionCard(s))]),
          const SizedBox(height: 26),
          const Label('Skills'),
          Wrap(spacing: 12, runSpacing: 12, children: [for (final m in content.modules) SizedBox(width: 314, child: _SkillCard(m))]),
        ]),
      ),
    ]);
  }
}

class _TodoRow extends StatefulWidget {
  const _TodoRow(this.todo, {required this.first});
  final _Todo todo;
  final bool first;

  @override
  State<_TodoRow> createState() => _TodoRowState();
}

class _TodoRowState extends State<_TodoRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tappable(
        label: widget.todo.text,
        radius: 0,
        pressScale: 1,
        onTap: widget.todo.go,
        child: Container(
          color: _hover ? p.s2 : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: widget.first ? p.accent : p.textFaint, shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.todo.text, style: t.bodyLarge?.weight(500)),
                Text(widget.todo.detail, style: t.bodySmall?.copyWith(color: p.textMuted)),
              ]),
            ),
            LineIcon('right', size: 14, color: p.textFaint),
          ]),
        ),
      ),
    );
  }
}

class _SessionCard extends ConsumerWidget {
  const _SessionCard(this.session);
  final Doc session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = session.data;
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    final items = [for (final d in ref.watch(docsProvider(('item', session.id))).value ?? const <Doc>[]) d.data];
    final mocks = [for (final d in ref.watch(docsProvider(('mock', session.id))).value ?? const <Doc>[]) d.data];
    final progress = sessionProgress(items, mocks);
    final paused = s['status'] == 'paused';
    final days = daysUntil(s['interviewDate']);
    final store = ref.read(storeProvider);
    return Panel(
      onTap: () => ref.go('role', session.id),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s['role']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleLarge),
              Text('${s['company']}'.isEmpty ? 'General practice' : '${s['company']}', style: t.bodyMedium?.copyWith(color: p.textMuted)),
            ]),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            popUpAnimationStyle: AnimationStyle.noAnimation,
            icon: LineIcon('more', size: 16, color: p.textFaint),
            onSelected: (v) async {
              if (v == 'edit') ref.go('new-role', session.id);
              if (v == 'pause') await store.patch(session.id, {'status': paused ? 'active' : 'paused'});
              if (v == 'delete' && context.mounted && await confirm(context, 'Delete this role?', 'Its plan, answers, practice history and mock interviews are removed. Answers you marked ready stay saved for other roles.')) {
                await store.deleteTree(session.id);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit details')),
              PopupMenuItem(value: 'pause', child: Text(paused ? 'Resume' : 'Pause')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ScoreBadge(sessionRating(items, mocks)),
              const Spacer(),
              if (paused) const Pill('Paused') else if (days != null) Pill(countdown(days), color: days <= 3 ? P.warn : P.muted),
            ]),
            const SizedBox(height: 10),
            Bar(progress),
            const SizedBox(height: 6),
            Text(
              '${(progress * 100).round()}% prepared  ·  ${items.where(isActive).length} questions  ·  ${mocks.length} mock${mocks.length == 1 ? '' : 's'}  ·  ${intensityNames[(s['intensity'] as int).clamp(1, 5)]}',
              style: t.bodySmall,
            ),
          ]),
        ),
      ]),
    );
  }
}

class _SkillCard extends ConsumerWidget {
  const _SkillCard(this.module);
  final SkillModule module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    final done = ref.watch(lessonProgressProvider);
    final labsDone = (ref.watch(docsProvider(('lab', null))).value ?? const <Doc>[]).where((d) => module.labs.any((l) => l['id'] == d.id)).length;
    final lessons = module.lessons.toList();
    final n = lessons.where((l) => lessonDone(done[l.id])).length;
    return Panel(
      onTap: () => ref.go('skill', module.id),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(module.title, style: t.titleLarge)),
          if (n == lessons.length && n > 0) const Pill('Complete', color: P.good) else if (n > 0) const Pill('In progress', color: P.accent),
        ]),
        const SizedBox(height: 2),
        SizedBox(height: 38, child: Text(module.tagline, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: p.textMuted))),
        const SizedBox(height: 10),
        Bar(lessons.isEmpty ? 0 : n / lessons.length, color: p.ratingHigh),
        const SizedBox(height: 6),
        Text('$n of ${lessons.length} lessons${module.labs.isEmpty ? '' : '  ·  $labsDone of ${module.labs.length} labs'}', style: t.bodySmall),
      ]),
    );
  }
}
