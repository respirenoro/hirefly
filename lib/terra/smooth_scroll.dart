import 'package:flutter/widgets.dart';

/// A [ScrollController] whose mouse-wheel steps glide a little instead of
/// jumping. Wheel ticks that arrive mid-glide add to where it is heading.
/// Set [smooth] false (Reduce motion) to jump as usual.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({this.duration = const Duration(milliseconds: 120)});

  final Duration duration;
  bool smooth = true;

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics, ScrollContext context, ScrollPosition? oldPosition) =>
      _SmoothPosition(this, physics: physics, context: context, oldPosition: oldPosition, initialPixels: initialScrollOffset, keepScrollOffset: keepScrollOffset, debugLabel: debugLabel);
}

class _SmoothPosition extends ScrollPositionWithSingleContext {
  _SmoothPosition(this._owner, {required super.physics, required super.context, super.oldPosition, super.initialPixels, super.keepScrollOffset, super.debugLabel});

  final SmoothScrollController _owner;
  double? _target;

  @override
  void pointerScroll(double delta) {
    if (!_owner.smooth || delta == 0) {
      _target = null;
      super.pointerScroll(delta);
      return;
    }
    final to = ((_target ?? pixels) + delta).clamp(minScrollExtent, maxScrollExtent);
    if (to == pixels) return;
    _target = to;
    animateTo(to, duration: _owner.duration, curve: Curves.easeOutCubic).whenComplete(() {
      if (_target == to) _target = null;
    });
  }
}
