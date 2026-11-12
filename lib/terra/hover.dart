import 'package:flutter/material.dart';

import 'press.dart';

/// Desktop hover affordance: a quick surface brightening + pointer cursor
/// (no zoom — unslop: hover is a colour/surface change, press scales down a
/// touch). Cheap: one opacity animation over the child.
/// Something clickable that isn't a button widget: Tab reaches it, Enter or
/// Space opens it, a ring shows where the focus is, and screen readers hear a
/// button with [label] (or the text inside it).
class Tappable extends StatefulWidget {
  const Tappable({
    super.key,
    required this.child,
    required this.onTap,
    this.label,
    this.selected,
    this.toggled,
    this.radius = 8,
    this.handleClicks = true,
    this.pressScale = 0.97,
    this.ringOutside = false,
  });
  final Widget child;
  final VoidCallback? onTap;
  final String? label;

  /// One of a set (a segment, a tab) is chosen; null when the idea doesn't apply.
  final bool? selected;

  /// An on/off control is on; null when the idea doesn't apply.
  final bool? toggled;
  final double radius;

  /// False when [child] already handles its own clicks.
  final bool handleClicks;

  /// How far the child shrinks while held (QA-5); 1 turns it off.
  final double pressScale;

  /// Draw the focus ring 2 px outside the child (for filled controls, where
  /// an inside ring would vanish into the fill).
  final bool ringOutside;

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable> {
  bool _ring = false;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        selected: widget.selected,
        toggled: widget.toggled,
        label: widget.label,
        child: FocusableActionDetector(
          enabled: onTap != null,
          mouseCursor: onTap == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          onShowFocusHighlight: (v) => setState(() => _ring = v),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                onTap?.call();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: widget.handleClicks ? onTap : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: _ring && !widget.ringOutside ? _ringBox(context, widget.radius) : const BoxDecoration(),
                  child: PressScale(
                    scale: widget.pressScale,
                    enabled: onTap != null && widget.pressScale != 1,
                    child: ExcludeSemantics(excluding: widget.label != null, child: widget.child),
                  ),
                ),
                if (_ring && widget.ringOutside)
                  Positioned(
                    left: -4,
                    top: -4,
                    right: -4,
                    bottom: -4,
                    child: IgnorePointer(child: DecoratedBox(decoration: _ringBox(context, widget.radius + 4))),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static BoxDecoration _ringBox(BuildContext context, double radius) => BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
      );
}

class HoverLift extends StatefulWidget {
  const HoverLift({
    super.key,
    required this.child,
    this.onTap,
    this.onSecondaryTapUp,
    this.scale = 1.0,
  });

  final Widget child;
  final VoidCallback? onTap;
  final GestureTapUpCallback? onSecondaryTapUp;
  final double scale;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final lift = MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapUp: widget.onSecondaryTapUp,
        child: Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: _hover ? Duration.zero : const Duration(milliseconds: 140),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return widget.onTap == null
        ? lift
        : Tappable(onTap: widget.onTap, handleClicks: false, child: lift);
  }
}
