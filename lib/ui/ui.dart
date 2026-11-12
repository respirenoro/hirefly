// HireFly's shared pieces, built on the kit ported from Soloza (`lib/terra/`):
// its palette, type, panels, buttons and press feedback.
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../ai/ai_client.dart';
import '../terra/app_theme.dart';
import '../terra/fonts.dart';
import '../terra/hover.dart';
import '../terra/j.dart';
import '../terra/line_icon.dart';
import '../terra/palette.dart';
import '../terra/smooth_scroll.dart';
import '../terra/web_link.dart';
import 'extras.dart';

export 'extras.dart';
export '../terra/app_theme.dart' show WeightX;
export '../terra/fonts.dart';
export '../terra/hover.dart';
export '../terra/j.dart';
export '../terra/line_icon.dart';
export '../terra/palette.dart';
export '../terra/web_link.dart';

/// The Night skin's colours by short name, for const contexts.
abstract final class P {
  static const bg = Color(0xFF141311);
  static const surface = Color(0xFF191816);
  static const raised = Color(0xFF2A2926);
  static const border = Color(0x14FFFFFF);
  static const text = Color(0xFFEFE9DE);
  static const muted = Color(0xFFBAB3A6);
  static const faint = Color(0xFF9D978B);
  static const accent = Color(0xFF5DB4E8);
  static const good = Color(0xFF5BD08A);
  static const warn = Color(0xFFF5C451);
  static const bad = Color(0xFFEF6B5B);
}

ThemeData appTheme() => buildTheme(Palette.dark, const AppFonts());

Color scoreColor(double? s) => Palette.dark.score(s);
String scoreText(double? s) => s == null ? 'Not rated' : s.toStringAsFixed(1);

/// Soloza's panel: a faint step over the window with a hairline edge.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.raised = false, this.edge, this.onTap});
  final Widget child;
  final EdgeInsets padding;

  /// A stronger fill and edge, for a callout.
  final bool raised;
  final Color? edge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final box = Container(
      padding: padding,
      decoration: raised ? BoxDecoration(color: p.s2, borderRadius: BorderRadius.circular(12), border: Border.all(color: edge ?? p.lineStrong)) : p.panel(12, edge),
      child: child,
    );
    return onTap == null ? box : HoverLift(onTap: onTap, child: box);
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color = P.muted});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
      );
}

class ScoreBadge extends StatelessWidget {
  const ScoreBadge(this.score, {super.key, this.large = false});
  final double? score;
  final bool large;

  @override
  Widget build(BuildContext context) => Semantics(
        label: score == null ? 'Not rated yet' : 'Rated ${scoreText(score)} out of 10',
        child: ExcludeSemantics(
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(score == null ? '–' : scoreText(score), style: context.mono.copyWith(color: scoreColor(score), fontSize: large ? 30 : 16).weight(500)),
            Text(' / 10', style: context.mono.copyWith(color: P.faint, fontSize: large ? 13 : 11)),
          ]),
        ),
      );
}

class Bar extends StatelessWidget {
  const Bar(this.value, {super.key, this.color});
  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(value: value.clamp(0, 1), minHeight: 3, backgroundColor: p.s3, color: color ?? p.accent, semanticsLabel: 'Progress', semanticsValue: '${(value.clamp(0, 1) * 100).round()}'),
    );
  }
}

/// A quiet section label, sentence case (Soloza's `JSec` look).
class Label extends StatelessWidget {
  const Label(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Semantics(header: true, child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textFaint, height: 1.45))),
      );
}

/// A heading inside a page.
class Heading extends StatelessWidget {
  const Heading(this.text, {super.key, this.sub});
  final String text;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(header: true, child: Text(text, style: t.headlineSmall)),
      if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: t.bodyMedium?.copyWith(color: context.palette.textMuted))),
    ]);
  }
}

/// Body text at reading size.
TextStyle readStyle(BuildContext context) => Theme.of(context).textTheme.bodyLarge!.copyWith(height: 1.55);

class Bullets extends StatelessWidget {
  const Bullets(this.items, {super.key, this.color});
  final List<String> items;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final i in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 9, right: 9), child: Container(width: 4, height: 4, decoration: BoxDecoration(color: color ?? context.palette.textFaint, shape: BoxShape.circle))),
              Expanded(child: Text(i, style: readStyle(context))),
            ]),
          ),
      ]);
}

/// Markdown at reading size. Selection comes from the page's [SelectionArea],
/// so one drag runs across paragraphs, lists, tables and code.
class Md extends StatelessWidget {
  const Md(this.data, {super.key});
  final String data;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    final body = readStyle(context);
    final mono = TextStyle(fontFamily: context.fonts.numbers, fontSize: 13, height: 1.5, color: p.text);
    return MarkdownBody(
      data: data,
      onTapLink: (_, href, _) {
        if (href != null) openWebLink(href);
      },
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: body,
        h1: t.headlineMedium,
        h2: t.headlineSmall,
        h3: t.titleLarge,
        h4: t.titleMedium,
        h1Padding: const EdgeInsets.only(top: 6, bottom: 2),
        h2Padding: const EdgeInsets.only(top: 18, bottom: 2),
        h3Padding: const EdgeInsets.only(top: 12),
        strong: body.weight(600),
        code: mono.copyWith(backgroundColor: p.s3),
        codeblockDecoration: BoxDecoration(color: p.s2, borderRadius: BorderRadius.circular(p.radius), border: Border.all(color: p.border)),
        codeblockPadding: const EdgeInsets.all(12),
        blockquote: body.copyWith(color: p.textMuted),
        blockquoteDecoration: BoxDecoration(border: Border(left: BorderSide(color: p.accent, width: 2))),
        blockquotePadding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
        tableBorder: TableBorder.all(color: p.lineStrong),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        tableHead: body.weight(600),
        tableBody: body,
        listBullet: body.copyWith(color: p.textFaint),
        a: body.copyWith(color: p.accent),
        horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
        blockSpacing: 11,
      ),
    );
  }
}

/// A scrolling page body held to a readable width. Its text selects as one
/// document, and the wheel glides (Soloza's `SmoothScrollController`).
class Sheet extends StatefulWidget {
  const Sheet({super.key, required this.children, this.width = 880, this.padding = const EdgeInsets.fromLTRB(28, 8, 28, 56)});
  final List<Widget> children;
  final double width;
  final EdgeInsets padding;

  @override
  State<Sheet> createState() => _SheetState();
}

class _SheetState extends State<Sheet> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MiddleScroll(
        controller: _scroll,
        child: SelectionArea(
        child: Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: widget.padding,
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(constraints: BoxConstraints(maxWidth: widget.width), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.children)),
            ),
          ),
        ),
        ),
      );
}

/// The top of a page: an optional way back, the serif title and actions at
/// the right (after Soloza's `JH` and `PageHeader`).
class PageTop extends StatelessWidget {
  const PageTop({super.key, required this.title, this.kicker, this.onBack, this.backLabel, this.actions = const [], this.below});
  final String title;
  final String? kicker, backLabel;
  final VoidCallback? onBack;
  final List<Widget> actions;

  /// A row under the title, such as the page's own tabs.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (onBack != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Tappable(
              label: backLabel ?? 'Back',
              onTap: onBack,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                LineIcon('back', size: 13, color: p.textFaint),
                const SizedBox(width: 5),
                Text(backLabel ?? 'Back', style: t.bodySmall?.copyWith(color: p.textFaint)),
              ]),
            ),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (kicker != null) Text(kicker!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(fontSize: 12.5, color: p.textFaint)),
              Semantics(header: true, child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.headlineMedium)),
            ]),
          ),
          const SizedBox(width: 14),
          for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(width: 8), a],
        ]),
        if (below != null) Padding(padding: const EdgeInsets.only(top: 12), child: below),
      ]),
    );
  }
}

void say(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), width: 520));
}

/// Runs an assistant call; a failure becomes a message and null.
Future<T?> tryAi<T>(BuildContext context, Future<T> Function() call) async {
  try {
    return await call();
  } on AiFailure catch (e) {
    if (context.mounted) say(context, e.message);
    return null;
  }
}

Future<bool> confirm(BuildContext context, String title, String body, {String yes = 'Delete'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title, style: Theme.of(c).textTheme.titleLarge),
        content: SizedBox(width: 420, child: Text(body, style: Theme.of(c).textTheme.bodyLarge)),
        actions: [
          JBtn('Cancel', quiet: true, onTap: () => Navigator.pop(c, false)),
          JBtn(yes, primary: true, onTap: () => Navigator.pop(c, true)),
        ],
      ),
    ) ??
    false;

/// A button that shows it is working while an assistant call runs.
class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.busy, required this.onPressed, required this.label, this.icon = 'sparkle', this.filled = false});
  final bool busy, filled;
  final VoidCallback? onPressed;
  final String label;
  final String? icon;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        JBtn(label, icon: busy ? null : icon, primary: filled, onTap: busy ? null : onPressed),
        if (busy) const Padding(padding: EdgeInsets.only(left: 8), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6))),
      ]);
}

/// A field for the learner's own writing, at reading size.
InputDecoration writeField(String hint) => InputDecoration(hintText: hint, hintMaxLines: 3, contentPadding: const EdgeInsets.all(12));
