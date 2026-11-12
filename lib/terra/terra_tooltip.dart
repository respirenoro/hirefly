// TT1-TT8: the one tooltip for the app. Timings and behaviour follow
// docs/research/hover-and-tooltip-reference.md.
import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart';

import 'palette.dart';

/// Which side of the control the tooltip prefers; it flips when there is no
/// room, and is clamped inside the window.
enum TipSide { below, above, right, left }

/// How long the pointer rests before the first tooltip shows (TT2).
const tooltipColdDelay = Duration(milliseconds: 300);

/// How long a tooltip lingers after the pointer leaves. Entering the next
/// control inside this time swaps directly, with no delay (TT3, TT4).
const tooltipHideGrace = Duration(milliseconds: 100);

/// After a tooltip has been shown and the pointer leaves, another tooltip
/// (or the same one) entered inside this time shows at once (TT3, TT4; F-48).
const tooltipWarmWindow = Duration(milliseconds: 500);

/// A short label for a control: accent fill, light text, a caret toward the
/// control. Appears and goes in one frame, with no fade (TT5).
class TerraTooltip extends StatefulWidget {
  const TerraTooltip({super.key, required this.message, required this.child, this.side = TipSide.below});

  final String message;
  final Widget child;
  final TipSide side;

  @override
  State<TerraTooltip> createState() => _TerraTooltipState();
}

/// Where the bubble ended up: its side of the control and where its caret
/// points, in the bubble's own coordinates.
class _Place {
  const _Place(this.side, this.caret);
  final TipSide side;
  final double caret;
}

class _TerraTooltipState extends State<TerraTooltip> {
  late final _place = ValueNotifier<_Place>(_Place(widget.side, 0));
  final _tip = GlobalKey<RawTooltipState>();
  Timer? _focusTimer;
  Timer? _dwell;
  bool _shown = false;
  static Duration _warmUntil = Duration.zero;

  static Duration get _now => SchedulerBinding.instance.currentSystemFrameTimeStamp;

  // F-48: a tip that has been up leaves the whole app warm for half a second.
  void _enter() {
    _shown = false;
    _dwell?.cancel();
    _dwell = Timer(tooltipColdDelay, () => _shown = true);
    if (_now < _warmUntil) _tip.currentState?.ensureTooltipVisible();
  }

  void _leave() {
    _dwell?.cancel();
    if (!_shown) return;
    _shown = false;
    _warmUntil = _now + tooltipWarmWindow;
  }

  // F-46: keyboard focus shows the tip after the cold delay; blur or Esc hides it.
  void _focusChanged(bool focused) {
    _focusTimer?.cancel();
    if (focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional) {
      _focusTimer = Timer(tooltipColdDelay, () => _tip.currentState?.ensureTooltipVisible());
    } else {
      RawTooltip.dismissAllToolTips();
    }
  }

  @override
  void dispose() {
    _focusTimer?.cancel();
    _dwell?.cancel();
    _place.dispose();
    super.dispose();
  }

  static const _margin = 5.0; // room for the caret on every side

  Offset _position(TooltipPositionContext c) {
    final t = c.target, ts = c.targetSize, sz = c.tooltipSize, ov = c.overlaySize;
    final vertical = widget.side == TipSide.below || widget.side == TipSide.above;
    double clamp(double v, double size, double room) => v.clamp(4.0, (room - size - 4).clamp(4.0, room));
    if (vertical) {
      final below = widget.side == TipSide.below;
      final fitsBelow = t.dy + ts.height / 2 + sz.height <= ov.height - 4;
      final fitsAbove = t.dy - ts.height / 2 - sz.height >= 4;
      final useBelow = below ? (fitsBelow || !fitsAbove) : !(fitsAbove || !fitsBelow);
      final y = useBelow ? t.dy + ts.height / 2 - _margin + 1 : t.dy - ts.height / 2 - sz.height + _margin - 1;
      final x = clamp(t.dx - sz.width / 2, sz.width, ov.width);
      _place.value = _Place(useBelow ? TipSide.below : TipSide.above, t.dx - x);
      return Offset(x, y);
    }
    final right = widget.side == TipSide.right;
    final fitsRight = t.dx + ts.width / 2 + sz.width <= ov.width - 4;
    final fitsLeft = t.dx - ts.width / 2 - sz.width >= 4;
    final useRight = right ? (fitsRight || !fitsLeft) : !(fitsLeft || !fitsRight);
    final x = useRight ? t.dx + ts.width / 2 - _margin + 1 : t.dx - ts.width / 2 - sz.width + _margin - 1;
    final y = clamp(t.dy - sz.height / 2, sz.height, ov.height);
    _place.value = _Place(useRight ? TipSide.right : TipSide.left, t.dy - y);
    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message.isEmpty) return widget.child;
    final p = context.palette;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: p.onAccent, height: 1.3);
    return RawTooltip(
      key: _tip,
      semanticsTooltip: widget.message,
      hoverDelay: tooltipColdDelay,
      dismissDelay: tooltipHideGrace,
      animationStyle: AnimationStyle.noAnimation,
      positionDelegate: _position,
      tooltipBuilder: (context, _) => CustomPaint(
        painter: _BubblePainter(_place, p.accent),
        child: Padding(
          padding: const EdgeInsets.all(_margin).add(const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(widget.message, style: style, softWrap: true),
          ),
        ),
      ),
      child: MouseRegion(
       onEnter: (_) => _enter(),
       onExit: (_) => _leave(),
       child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: _focusChanged,
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) RawTooltip.dismissAllToolTips();
          return KeyEventResult.ignored;
        },
        child: widget.child,
       ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter(this.place, this.fill) : super(repaint: place);
  final ValueListenable<_Place> place;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const m = _TerraTooltipState._margin;
    final body = Rect.fromLTRB(m, m, size.width - m, size.height - m);
    final pl = place.value;
    final path = Path()..addRRect(RRect.fromRectAndRadius(body, const Radius.circular(4)));
    const half = 5.0;
    switch (pl.side) {
      case TipSide.below:
        final x = pl.caret.clamp(m + 6, size.width - m - 6);
        path.addPolygon([Offset(x - half, m), Offset(x, 0), Offset(x + half, m)], true);
      case TipSide.above:
        final x = pl.caret.clamp(m + 6, size.width - m - 6);
        path.addPolygon([Offset(x - half, size.height - m), Offset(x, size.height), Offset(x + half, size.height - m)], true);
      case TipSide.right:
        final y = pl.caret.clamp(m + 6, size.height - m - 6);
        path.addPolygon([Offset(m, y - half), Offset(0, y), Offset(m, y + half)], true);
      case TipSide.left:
        final y = pl.caret.clamp(m + 6, size.height - m - 6);
        path.addPolygon([Offset(size.width - m, y - half), Offset(size.width, y), Offset(size.width - m, y + half)], true);
    }
    canvas.drawPath(path, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.fill != fill || old.place != place;
}
