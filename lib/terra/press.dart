import 'package:flutter/material.dart';

/// QA-5: press feedback that starts on pointer down. [PressScale] shrinks its
/// child a touch while a pointer is held on it and eases back on release, exit
/// or cancel. It never takes part in the gesture arena (a [Listener]), so the
/// child's own tap still fires. Off with reduced motion and when [enabled] is false.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.scale = 0.97,
    this.enabled = true,
  });
  final Widget child;
  final double scale;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

/// The scale for a box of [size]: each edge moves in by about 2 px at most and
/// the ratio never goes below [floor], so big surfaces barely move.
double pressScaleFor(Size size, double floor) {
  final longest = size.longestSide;
  if (longest <= 0) return floor;
  final s = 1 - 4 / longest;
  return s > floor ? s : floor;
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  double _scale = 1;

  void _press() {
    if (!mounted) return;
    final size = context.size;
    setState(() {
      _down = true;
      _scale = size == null ? widget.scale : pressScaleFor(size, widget.scale);
    });
  }

  void _release() {
    if (_down && mounted) setState(() => _down = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || MediaQuery.maybeDisableAnimationsOf(context) == true) {
      return widget.child;
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _press(),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      // Sliding off cancels the press; sliding back on presses again.
      onPointerMove: (e) {
        final inside = (Offset.zero & (context.size ?? Size.zero)).contains(e.localPosition);
        if (!inside && _down) {
          _release();
        } else if (inside && !_down) {
          _press();
        }
      },
      child: AnimatedScale(
        scale: _down ? _scale : 1,
        duration: Duration(milliseconds: _down ? 70 : 160),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A splash factory with no ripple: a flat tint appears within a few frames of
/// the pointer going down (60 ms) and leaves in 120 ms. Flutter's own highlight
/// takes 200 ms to fade in, which is gone before a quick click shows it.
class PressTint extends InteractiveInkFeatureFactory {
  const PressTint();

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) => _PressTintFeature(
    controller: controller,
    referenceBox: referenceBox,
    color: color,
    rectCallback: containedInkWell ? rectCallback : null,
    borderRadius: borderRadius,
    customBorder: customBorder,
    onRemoved: onRemoved,
  );
}

class _PressTintFeature extends InteractiveInkFeature {
  _PressTintFeature({
    required super.controller,
    required super.referenceBox,
    required super.color,
    this.rectCallback,
    this.borderRadius,
    this.customBorder,
    super.onRemoved,
  }) {
    _in =
        AnimationController(
            vsync: controller.vsync,
            duration: const Duration(milliseconds: 60),
          )
          ..addListener(controller.markNeedsPaint)
          ..forward();
    controller.addInkFeature(this);
  }

  final RectCallback? rectCallback;
  final BorderRadius? borderRadius;
  @override
  final ShapeBorder? customBorder;
  late final AnimationController _in;
  AnimationController? _out;

  void _release() {
    if (_out != null) return;
    // A quick click still reaches the tint's peak before it fades out.
    if (_in.isAnimating) {
      _in.addStatusListener((st) {
        if (st == AnimationStatus.completed) _release();
      });
      return;
    }
    _out =
        AnimationController(
            vsync: controller.vsync,
            duration: const Duration(milliseconds: 120),
          )
          ..addListener(controller.markNeedsPaint)
          ..addStatusListener((s) {
            if (s == AnimationStatus.completed) dispose();
          })
          ..forward();
  }

  @override
  void confirm() => _release();

  @override
  void cancel() => _release();

  @override
  void dispose() {
    _in.dispose();
    _out?.dispose();
    super.dispose();
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final fade = _in.value * (1 - (_out?.value ?? 0));
    if (fade <= 0) return;
    final paint = Paint()..color = color.withValues(alpha: color.a * fade);
    final rect = rectCallback?.call() ?? Offset.zero & referenceBox.size;
    canvas.save();
    canvas.transform(transform.storage);
    if (customBorder != null) {
      canvas.drawPath(customBorder!.getOuterPath(rect), paint);
    } else if (borderRadius != null && borderRadius != BorderRadius.zero) {
      canvas.drawRRect(borderRadius!.toRRect(rect), paint);
    } else {
      canvas.drawRect(rect, paint);
    }
    canvas.restore();
  }
}
