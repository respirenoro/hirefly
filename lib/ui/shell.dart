// The window: Soloza's layout of a sidebar and one content pane over the soft
// canvas. Pages swap in place and at once; nothing slides or fades.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_client.dart';
import '../data/content.dart';
import '../data/db.dart';
import '../engine/engine.dart';
import '../engine/inbox.dart';
import 'home_screen.dart';
import 'new_session_screen.dart';
import 'new_skill_screen.dart';
import 'sandbox_screen.dart';
import 'session_screen.dart';
import 'settings_screen.dart';
import 'skills_screen.dart';
import 'story_screen.dart';
import 'ui.dart';

/// Where the learner is: a page, the thing it shows, and a part of it.
@immutable
class Nav {
  const Nav(this.page, [this.id, this.sub]);
  final String page;
  final String? id, sub;

  @override
  bool operator ==(Object other) => other is Nav && other.page == page && other.id == id && other.sub == sub;

  @override
  int get hashCode => Object.hash(page, id, sub);
}

class NavNotifier extends Notifier<Nav> {
  @override
  Nav build() => const Nav('home');

  /// The role the learner was preparing when they opened a skill, so skill
  /// pages can offer the way back. Leaving for anything else forgets it.
  String? fromRole;

  void go(String page, [String? id, String? sub]) {
    if (state.page == 'role' && const {'skill', 'lesson', 'sandbox'}.contains(page)) {
      fromRole = state.id;
    } else if (!const {'skill', 'lesson', 'sandbox'}.contains(page)) {
      fromRole = null;
    }
    state = Nav(page, id, sub);
  }
}

final navProvider = NotifierProvider<NavNotifier, Nav>(NavNotifier.new);

extension NavRef on WidgetRef {
  void go(String page, [String? id, String? sub]) => read(navProvider.notifier).go(page, id, sub);

  /// A "Back to the role" button for skill pages opened from a role, else nothing.
  List<Widget> backToRole() {
    final id = read(navProvider.notifier).fromRole;
    final role = id == null ? null : watch(docProvider(id)).value;
    if (role == null) return const [];
    final company = '${role.data['company']}'.trim();
    return [JBtn('Back to ${company.isEmpty ? role.data['role'] : company}', icon: 'back', onTap: () => go('role', id))];
  }
}

/// Lesson progress documents, by lesson id.
final lessonProgressProvider = Provider.autoDispose<Map<String, Json>>(
    (ref) => {for (final d in ref.watch(docsProvider(('lesson', null))).value ?? const <Doc>[]) d.id: d.data});

bool lessonDone(Json? p) => p != null && p['state'] != 'started';

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  StreamSubscription<InboxEvent>? _inbox;

  @override
  void initState() {
    super.initState();
    // Roles other tools ask for arrive through the inbox folder.
    final inbox = ref.read(inboxProvider);
    _inbox = inbox.events.listen((e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(e.message),
          width: 560,
          duration: const Duration(seconds: 12),
          action: e.sessionId == null ? null : SnackBarAction(label: 'Open', onPressed: () => ref.go('role', e.sessionId)),
        ));
    });
    inbox.poll();
  }

  @override
  void dispose() {
    _inbox?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nav = ref.watch(navProvider);
    final p = context.palette;
    final page = switch (nav.page) {
      'role' => SessionScreen(nav.id!, key: ValueKey('role-${nav.id}'), tab: nav.sub),
      'new-role' => NewSessionScreen(key: ValueKey('new-${nav.id}'), editId: nav.id),
      'skill' => SkillScreen(nav.id!, key: ValueKey('skill-${nav.id}'), tab: nav.sub),
      'lesson' => LessonScreen(nav.id!, nav.sub!, key: ValueKey('lesson-${nav.sub}')),
      'sandbox' => const SandboxScreen(),
      'new-skill' => const NewSkillScreen(),
      'dossier' => const DossierScreen(),
      'stories' => const StoriesScreen(),
      'settings' => const SettingsScreen(),
      _ => const HomeScreen(),
    };
    return Scaffold(
      backgroundColor: p.canvasBase ?? p.background,
      body: Stack(children: [
        const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _CanvasPainter(Palette.dark)))),
        Row(children: [
          const _Sidebar(),
          Expanded(child: Material(type: MaterialType.transparency, child: page)),
        ]),
      ]),
    );
  }
}

/// The skin's pools of colour over its ground (Soloza's soft canvas).
class _CanvasPainter extends CustomPainter {
  const _CanvasPainter(this.p);
  final Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = p.canvasBase ?? p.background);
    for (final g in p.canvasGlows) {
      final c = Offset(size.width * g.x, size.height * g.y);
      final rect = Rect.fromCenter(center: c, width: g.rx * 2, height: g.ry * 2);
      canvas.drawOval(
        rect,
        Paint()..shader = RadialGradient(colors: [g.color.withValues(alpha: .42), g.color.withValues(alpha: 0)], stops: [0, g.stop]).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter old) => false;
}

class _Sidebar extends ConsumerStatefulWidget {
  const _Sidebar();

  @override
  ConsumerState<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<_Sidebar> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final nav = ref.watch(navProvider);
    final sessions = [...ref.watch(docsProvider(('session', null))).value ?? const <Doc>[]]
      ..sort((a, b) {
        final pa = a.data['status'] == 'paused' ? 1 : 0, pb = b.data['status'] == 'paused' ? 1 : 0;
        return pa != pb ? pa.compareTo(pb) : b.updatedAt.compareTo(a.updatedAt);
      });
    final modules = ref.watch(contentProvider).modules;
    final progress = ref.watch(lessonProgressProvider);
    final spent = (ref.watch(aiMonthSpendProvider).value ?? 0) / 1000000;
    final hasKey = ref.watch(aiSettingsProvider).value?.hasKey ?? true;
    return Container(
      width: 244,
      decoration: BoxDecoration(color: p.sidebar.withValues(alpha: .86), border: Border(right: BorderSide(color: p.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 14, 6),
          child: Row(children: [
            const FireflyMark(size: 38),
            const SizedBox(width: 4),
            Text('HireFly', style: t.headlineSmall),
          ]),
        ),
        Expanded(
          child: MiddleScroll(
            controller: _scroll,
            child: ListView(controller: _scroll, padding: const EdgeInsets.only(bottom: 12), children: [
            JLi(text: 'Today', leading: const LineIcon('sun', size: 15), on: nav.page == 'home', onTap: () => ref.go('home')),
            const JGl('Roles'),
            for (final s in sessions) _RoleRow(s, on: (nav.page == 'role' || nav.page == 'new-role') && nav.id == s.id),
            JLi(text: 'New role', leading: const LineIcon('plus', size: 15), on: nav.page == 'new-role' && nav.id == null, onTap: () => ref.go('new-role'), faint: nav.page != 'new-role'),
            const JGl('Skills'),
            for (final m in modules)
              JLi(
                text: m.title,
                leading: LineIcon(_skillIcon(m.id), size: 15),
                trailing: '${m.lessons.where((l) => lessonDone(progress[l.id])).length}/${m.lessons.length}',
                on: (nav.page == 'skill' || nav.page == 'lesson') && nav.id == m.id || (nav.page == 'sandbox' && m.id == 'sql'),
                onTap: () => ref.go('skill', m.id),
              ),
            JLi(text: 'New skill', leading: const LineIcon('plus', size: 15), on: nav.page == 'new-skill', onTap: () => ref.go('new-skill'), faint: nav.page != 'new-skill'),
            const JGl('You'),
            JLi(text: 'Know your role', leading: const LineIcon('person', size: 15), on: nav.page == 'dossier', onTap: () => ref.go('dossier')),
            JLi(text: 'Your stories', leading: const LineIcon('book-open', size: 15), on: nav.page == 'stories', onTap: () => ref.go('stories')),
          ]),
          ),
        ),
        Container(height: 1, color: p.border),
        JLi(
          text: 'Settings',
          leading: const LineIcon('gear', size: 15),
          trailing: hasKey ? '\$${spent.toStringAsFixed(2)}' : 'no key',
          on: nav.page == 'settings',
          onTap: () => ref.go('settings'),
        ),
        const SizedBox(height: 6),
      ]),
    );
  }
}

String _skillIcon(String id) => switch (id) {
      'sql' => 'layers',
      'excel' => 'grid',
      'power-bi' => 'chart',
      'jira' => 'flag',
      'azure-devops' => 'sync',
      'ado-test-plans' => 'check-circle',
      'playwright' => 'play-circle',
      'ticket-process' => 'tag',
      _ => 'article',
    };

class _RoleRow extends ConsumerWidget {
  const _RoleRow(this.session, {required this.on});
  final Doc session;
  final bool on;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = [for (final d in ref.watch(docsProvider(('item', session.id))).value ?? const <Doc>[]) d.data];
    final mocks = [for (final d in ref.watch(docsProvider(('mock', session.id))).value ?? const <Doc>[]) d.data];
    final s = session.data;
    final company = '${s['company']}'.trim();
    return JLi(
      text: company.isEmpty ? '${s['role']}' : '$company · ${s['role']}',
      leading: LineIcon(s['status'] == 'paused' ? 'pause' : 'speech', size: 15),
      trailing: '${(sessionProgress(items, mocks) * 100).round()}%',
      faint: s['status'] == 'paused',
      on: on,
      onTap: () => ref.go('role', session.id),
    );
  }
}
