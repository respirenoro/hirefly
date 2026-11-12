import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'fonts.dart';
import 'palette.dart';
import 'hover.dart';
import 'line_icon.dart';

/// The parts the interface is built from, measured from the chosen design
/// (`docs/research/ui-port-checklist.md`). Screens use these, so one change
/// reaches every screen.
extension JStyles on BuildContext {
  /// Figures: the numbers font at 12.
  TextStyle get mono => Theme.of(this).textTheme.bodySmall!.copyWith(fontFamily: fonts.numbers, fontSize: 12, letterSpacing: -0.2, color: palette.text).weight(400);

  /// Your own words beside the interface.
  TextStyle get quote => Theme.of(this).textTheme.bodyMedium!.copyWith(fontFamily: fonts.display, fontSize: 15, height: 1.42, color: palette.text).weight(400);
}

class JKbd extends StatelessWidget {
  const JKbd(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: p.s3, borderRadius: BorderRadius.circular(4), border: Border.all(color: p.border)),
      child: Text(label, style: context.mono.copyWith(fontSize: 11, letterSpacing: 0, color: p.textMuted, height: 1.2).weight(500)),
    );
  }
}

/// A button: quiet by default, accent when [primary].
class JBtn extends StatefulWidget {
  const JBtn(this.label, {super.key, this.icon, this.trailingIcon, this.primary = false, this.quiet = false, this.danger = false, this.height = 30, this.onTap});
  final String label;
  final String? icon, trailingIcon;
  final bool primary;

  /// A text-only button (no fill or border), in the accent colour: the in-line and Cancel kind.
  final bool quiet;

  /// Draws the label in the danger colour (Remove, Delete); for a [quiet] button.
  final bool danger;
  final double height;
  final VoidCallback? onTap;

  @override
  State<JBtn> createState() => _JBtnState();
}

class _JBtnState extends State<JBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final fg = widget.primary ? p.onAccent : (widget.danger ? p.danger : (widget.quiet ? p.accent : p.text));
    final enabled = widget.onTap != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tappable(
        label: widget.label,
        radius: p.radius,
        ringOutside: widget.primary,
        onTap: widget.onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            height: widget.height,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: widget.primary ? (_hover && enabled ? Color.alphaBlend(p.text.withValues(alpha: 0.08), p.accent) : p.accent) : (_hover && enabled ? p.s3Hover : (widget.quiet ? null : p.s3)),
              borderRadius: BorderRadius.circular(p.radius),
              border: widget.primary || widget.quiet ? null : Border.all(color: p.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (widget.icon != null) ...[LineIcon(widget.icon!, size: 13, color: fg), const SizedBox(width: 7)],
              Text(widget.label, maxLines: 1, style: t.labelLarge?.copyWith(color: fg, letterSpacing: 0).weight(500)),
              if (widget.trailingIcon != null) ...[const SizedBox(width: 7), LineIcon(widget.trailingIcon!, size: 12, color: fg)],
            ]),
          ),
        ),
      ),
    );
  }
}

/// One choice in a [JSeg].
class JSegItem<T> {
  const JSegItem(this.value, this.label, {this.icon, this.tooltip});
  final T value;
  final String label;
  final String? icon, tooltip;
}

/// A segmented switch.
class JSeg<T> extends StatelessWidget {
  const JSeg({super.key, required this.items, required this.value, required this.onChanged});
  final List<JSegItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: p.s2, borderRadius: BorderRadius.circular(p.radius), border: Border.all(color: p.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final it in items)
          Tappable(
              label: it.label,
              selected: it.value == value,
              radius: p.radius - 2,
              onTap: () => onChanged(it.value),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: it.value == value ? p.s3 : null, borderRadius: BorderRadius.circular(p.radius - 2)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (it.icon != null) ...[LineIcon(it.icon!, size: 14, color: it.value == value ? p.text : p.textMuted), const SizedBox(width: 6)],
                  Text(it.label, maxLines: 1, style: t.labelLarge?.copyWith(color: it.value == value ? p.text : p.textMuted, letterSpacing: 0).weight(500)),
                ]),
              ),
            ),
      ]),
    );
  }
}

/// A section label in a side pane, with optional right-hand words.
class JSec extends StatelessWidget {
  const JSec(this.label, {super.key, this.trailing, this.trailingWidget, this.mono = false, this.accent = false, this.onTrailing});
  final String label;
  final String? trailing;
  final Widget? trailingWidget;

  /// The right-hand words are figures.
  final bool mono;
  final bool accent;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final color = accent || onTrailing != null ? p.ink : p.textFaint;
    final base = t.bodySmall!.copyWith(color: p.textFaint, height: 1.45);
    final right = trailing == null ? null : Text(trailing!, style: mono ? context.mono.copyWith(color: color) : base.copyWith(color: color));
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(child: Semantics(header: true, child: Text(label, style: base))),
        ?trailingWidget,
        if (right != null) onTrailing == null ? right : Tappable(onTap: onTrailing, child: right),
      ]),
    );
  }
}

/// A label and value on one line.
class JKv extends StatelessWidget {
  const JKv(this.label, this.value, {super.key, this.mono = false, this.accent = false, this.strongLabel = false, this.faintValue = false});
  final String label;
  final String? value;
  final bool mono, accent, strongLabel, faintValue;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final color = accent ? p.ink : (faintValue ? p.textFaint : p.text);
    // C-11: at 1920+ the value sits no more than 960 px from its label.
    return Align(
      alignment: Alignment.centerLeft,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kRowMaxWidth),
        child: _kv(context, t, p, color),
      ),
    );
  }

  Widget _kv(BuildContext context, TextTheme t, Palette p, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: strongLabel ? p.text : p.textMuted))),
        if (value != null) ...[
          const SizedBox(width: 12),
          Flexible(child: Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: mono ? context.mono.copyWith(color: color) : t.bodyMedium?.copyWith(color: color))),
        ],
      ]),
    );
  }
}

/// Widest a label-and-control row grows (C-11).
const kRowMaxWidth = 960.0;

/// The line between sections of a side pane, edge to edge past its padding.
class JDivi extends StatelessWidget {
  const JDivi({super.key});

  @override
  Widget build(BuildContext context) => Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 12), color: context.palette.border);
}

/// A tick box. With [onChanged] it is a control (focus ring, Space or click toggles,
/// named by [label] for screen readers); without, only the drawn part.
class JChk extends StatelessWidget {
  const JChk(this.on, {super.key, this.onChanged, this.label});
  final bool on;
  final ValueChanged<bool>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final box = Semantics(checked: on, child: Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        color: on ? p.accent : null,
        borderRadius: BorderRadius.circular(p.radius * 0.55),
        border: on ? null : Border.all(color: p.textFaint, width: 1.3),
      ),
      alignment: Alignment.center,
      child: on ? LineIcon('check', size: 10, stroke: 3, color: p.onAccent) : null,
    ));
    if (onChanged == null) return box;
    return Tappable(label: label, toggled: on, radius: 4, onTap: () => onChanged!(!on), child: Padding(padding: const EdgeInsets.all(8), child: box));
  }
}

/// A column's title line.
class JLh extends StatelessWidget {
  const JLh(this.title, {super.key, this.count, this.monoRight, this.onTap});
  final String title;
  final String? count, monoRight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final title0 = Text(title, style: t.bodyMedium?.copyWith(fontSize: 14).weight(600));
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        if (onTap == null) title0 else Tappable(onTap: onTap, child: title0),
        if (count != null) ...[const SizedBox(width: 8), Text(count!, style: t.bodyMedium?.copyWith(fontSize: 14, color: p.textFaint))],
        if (monoRight != null) ...[const Spacer(), Text(monoRight!, style: context.mono.copyWith(color: p.textFaint))],
      ]),
    );
  }
}

/// A group label in a column, with optional figures at the right.
class JGl extends StatelessWidget {
  const JGl(this.label, {super.key, this.right, this.rightAccent = false});
  final String label;
  final String? right;
  final bool rightAccent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Row(children: [
        Expanded(child: Text(label, style: t.bodySmall?.copyWith(color: p.textFaint))),
        if (right != null) Text(right!, style: context.mono.copyWith(color: rightAccent ? p.ink : p.textFaint)),
      ]),
    );
  }
}

/// A row in a column.
class JLi extends StatefulWidget {
  const JLi({super.key, required this.text, this.leading, this.trailing, this.trailingMono = true, this.on = false, this.done = false, this.onTap, this.label, this.faint = false, this.indent = 0, this.leadingWidth = 15});
  final String text;
  final Widget? leading;

  /// Extra space before the row's content (a nested row) and the width of the leading slot.
  final double indent, leadingWidth;
  final String? trailing;
  final bool trailingMono;

  /// The current row.
  final bool on;

  /// Struck through.
  final bool done;
  final bool faint;
  final VoidCallback? onTap;
  final String? label;

  @override
  State<JLi> createState() => _JLiState();
}

class _JLiState extends State<JLi> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final muted = widget.done || widget.faint;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tappable(
        label: widget.label ?? widget.text,
        radius: 0,
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: EdgeInsets.fromLTRB(12 + widget.indent, 6, 14, 6),
          decoration: BoxDecoration(
            color: widget.on ? p.s3 : (_hover && widget.onTap != null ? p.s2 : null),
            border: Border(left: BorderSide(color: widget.on ? p.accent : Colors.transparent, width: 2)),
          ),
          child: Row(children: [
            if (widget.leading != null) ...[SizedBox(width: widget.leadingWidth, child: Center(child: widget.leading)), const SizedBox(width: 10)],
            Expanded(
              child: Text(
                widget.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodyMedium?.copyWith(
                  color: muted ? p.textFaint : p.text,
                  decoration: widget.done ? TextDecoration.lineThrough : null,
                  decorationColor: p.textFaint,
                ),
              ),
            ),
            if (widget.trailing != null) ...[
              const SizedBox(width: 10),
              Text(widget.trailing!, style: widget.trailingMono ? context.mono.copyWith(color: p.textFaint) : t.bodyMedium?.copyWith(color: p.textFaint)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// A page's title block: optional kicker above the serif title, actions at the
/// right, aligned to the title's foot.
class JH extends StatelessWidget {
  const JH(this.title, {super.key, this.kicker, this.actions = const [], this.bottom = 8, this.actionsBesideTitle = false});
  final String title;
  final String? kicker;
  final List<Widget> actions;
  final double bottom;

  /// Put the actions right after the title instead of at the far right, so they
  /// sit next to what they act on.
  final bool actionsBesideTitle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final heading = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (kicker != null) Text(kicker!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(fontSize: 12.5, color: p.textFaint)),
      Semantics(header: true, child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.headlineMedium)),
    ]);
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 10, 14, bottom),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (actionsBesideTitle) Flexible(child: heading) else Expanded(child: heading),
        const SizedBox(width: 14),
        for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(width: 6), a],
      ]),
    );
  }
}

/// A bare text field's decoration, for fields inside a drawn box: no fill and
/// no focus outline of its own.
InputDecoration jFieldDecoration(String hint, TextStyle? hintStyle) => InputDecoration(
      isCollapsed: true,
      filled: false,
      hintText: hint,
      hintStyle: hintStyle,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: EdgeInsets.zero,
    );

/// A small card in a side pane: art, two lines and an action.
class JSideCard extends StatelessWidget {
  const JSideCard({super.key, required this.leading, required this.title, required this.subtitle, this.action, this.onAction, this.onTap, this.margin = EdgeInsets.zero});
  final Widget leading;
  final String title, subtitle;
  final String? action;
  final VoidCallback? onAction;

  /// Opens what the card is about; the art and both lines take the click, the
  /// action button keeps its own.
  final VoidCallback? onTap;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final about = Row(children: [
      leading,
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.weight(500)),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: p.textMuted)),
        ]),
      ),
    ]);
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: p.s3, borderRadius: BorderRadius.circular(p.radius)),
      child: Row(children: [
        Expanded(child: onTap == null ? about : HoverLift(onTap: onTap, child: about)),
        if (action != null) ...[const SizedBox(width: 8), JBtn(action!, height: 28, onTap: onAction)],
      ]),
    );
  }
}

/// The art size control: small and large grid icons around a short track.
class JSizer extends StatelessWidget {
  const JSizer({super.key, required this.value, required this.min, required this.max, required this.onChanged});
  final double value, min, max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const track = 46.0;
    void set(double x) => onChanged(min + (x / track).clamp(0.0, 1.0) * (max - min));
    final step = (max - min) / 10;
    void nudge(int dir) => onChanged((value + dir * step).clamp(min, max));
    return Semantics(
      label: 'Art size',
      value: '${value.round()} pixels',
      increasedValue: '${(value + step).clamp(min, max).round()} pixels',
      decreasedValue: '${(value - step).clamp(min, max).round()} pixels',
      slider: true,
      onIncrease: () => nudge(1),
      onDecrease: () => nudge(-1),
      child: Focus(
       onKeyEvent: (_, e) {
        if (e is KeyUpEvent) return KeyEventResult.ignored;
        final dir = switch (e.logicalKey) {
          LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.arrowUp => 1,
          LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.arrowDown => -1,
          _ => 0,
        };
        if (dir == 0) return KeyEventResult.ignored;
        nudge(dir);
        return KeyEventResult.handled;
       },
       child: Row(mainAxisSize: MainAxisSize.min, children: [
        LineIcon('grid', size: 12, color: p.textFaint),
        const SizedBox(width: 6),
        GestureDetector(
          key: const ValueKey('library.art'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => set(d.localPosition.dx),
          onTapDown: (d) => set(d.localPosition.dx),
          child: SizedBox(
            width: track,
            height: 24,
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
              Container(height: 3, decoration: BoxDecoration(color: p.s3, borderRadius: BorderRadius.circular(2))),
              Positioned(left: (value - min) / (max - min) * track - 5.5, child: Container(width: 11, height: 11, decoration: BoxDecoration(color: p.text, shape: BoxShape.circle))),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        LineIcon('grid', size: 16, color: p.textFaint),
      ]),
     ),
    );
  }
}
