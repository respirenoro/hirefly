// Middle-click scrolling and the firefly mark.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../terra/palette.dart';

/// Scrolling with the wheel button, as browsers do it: click the wheel and
/// move the pointer away from that spot to glide, faster the further you go;
/// click again (or press Escape) to stop. Holding the wheel down and dragging
/// works too, and stops on release.
class MiddleScroll extends StatefulWidget {
  const MiddleScroll({super.key, required this.controller, required this.child});
  final ScrollController controller;
  final Widget child;

  @override
  State<MiddleScroll> createState() => _MiddleScrollState();
}

/// Pixels a second for a pointer [distance] pixels from where the wheel was
/// clicked: nothing inside a small dead zone, then gathering speed.
double middleScrollSpeed(double distance) {
  const dead = 14.0;
  final d = distance.abs() - dead;
  if (d <= 0) return 0;
  return distance.sign * math.min(9000.0, 6 * math.pow(d, 1.35).toDouble());
}

class _MiddleScrollState extends State<MiddleScroll> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Offset? _anchor;
  Offset _pointer = Offset.zero;
  Duration _last = Duration.zero;
  DateTime _downAt = DateTime(0);
  bool _held = false;

  bool get _active => _anchor != null;

  void _start(Offset at) {
    setState(() {
      _anchor = at;
      _pointer = at;
      _held = true;
      _downAt = DateTime.now();
    });
    _last = Duration.zero;
    _ticker.start();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void _stop() {
    if (!_active) return;
    _ticker.stop();
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (mounted) setState(() => _anchor = null);
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
      _stop();
      return true;
    }
    return false;
  }

  void _tick(Duration now) {
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    final c = widget.controller;
    if (!c.hasClients || dt <= 0 || dt > .2) return;
    final v = middleScrollSpeed(_pointer.dy - _anchor!.dy);
    if (v == 0) return;
    final pos = c.position;
    final to = (pos.pixels + v * dt).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (to != pos.pixels) pos.jumpTo(to);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Listener(
      onPointerDown: (e) {
        if (e.buttons == kMiddleMouseButton) {
          _active ? _stop() : _start(e.localPosition);
        } else if (_active) {
          _stop();
        }
      },
      onPointerMove: (e) {
        if (_active) _pointer = e.localPosition;
      },
      onPointerHover: (e) {
        if (_active) _pointer = e.localPosition;
      },
      onPointerUp: (e) {
        if (!_active || !_held) return;
        _held = false;
        // A drag with the wheel held ends on release; a plain click stays on.
        final dragged = (_pointer - _anchor!).distance > 14 || DateTime.now().difference(_downAt) > const Duration(milliseconds: 350);
        if (dragged) _stop();
      },
      child: Stack(children: [
        widget.child,
        if (_active)
          Positioned(
            left: _anchor!.dx - 13,
            top: _anchor!.dy - 13,
            child: IgnorePointer(
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(color: p.surfaceRaised, shape: BoxShape.circle, border: Border.all(color: p.lineStrong)),
                child: Icon(Icons.unfold_more, size: 16, color: p.textMuted),
              ),
            ),
          ),
        if (_active) const Positioned.fill(child: MouseRegion(cursor: SystemMouseCursors.allScroll, opaque: false)),
      ]),
    );
  }
}

/// HireFly's mark: a firefly seen from above, wings half open, its tail lit.
class FireflyMark extends StatelessWidget {
  const FireflyMark({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: CustomPaint(size: Size.square(size), painter: FireflyPainter(context.palette)));
}

class FireflyPainter extends CustomPainter {
  const FireflyPainter(this.p);
  final Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 48 box, head up and a little to the right.
    canvas.save();
    canvas.scale(size.width / 48);
    canvas.translate(24, 24);
    canvas.rotate(.42);
    canvas.translate(-24, -24);

    const glow = Color(0xFFF5C451), ember = Color(0xFFFFE9A6);
    // The light: a soft halo behind the tail.
    canvas.drawCircle(
      const Offset(24, 35),
      15,
      Paint()..shader = RadialGradient(colors: [glow.withValues(alpha: .55), glow.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: const Offset(24, 35), radius: 15)),
    );
    // Wings, swept back and translucent.
    final wing = Paint()..color = p.text.withValues(alpha: .30);
    final edge = Paint()
      ..color = p.text.withValues(alpha: .55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final side in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(24, 19);
      canvas.rotate(side * .78);
      final r = Rect.fromLTWH(-4.5, -1, 9, 21);
      canvas.drawOval(r, wing);
      canvas.drawOval(r, edge);
      canvas.restore();
    }
    // Antennae.
    final feeler = Paint()
      ..color = p.textMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(Path()..moveTo(22.5, 9)..quadraticBezierTo(19, 5, 16.5, 5.5), feeler);
    canvas.drawPath(Path()..moveTo(25.5, 9)..quadraticBezierTo(29, 5, 31.5, 5.5), feeler);
    // Head and thorax.
    final body = Paint()..color = const Color(0xFF3B3631);
    canvas.drawCircle(const Offset(24, 11), 3.6, body);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(19.5, 13.5, 9, 9.5), const Radius.circular(4)), Paint()..color = const Color(0xFF5A4B3C));
    // The lit abdomen, in segments.
    final tail = RRect.fromRectAndRadius(const Rect.fromLTWH(19.2, 22, 9.6, 17), const Radius.circular(4.8));
    canvas.drawRRect(tail, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFD99A2B), glow, ember]).createShader(tail.outerRect));
    final seam = Paint()
      ..color = const Color(0x553B2A10)
      ..strokeWidth = 1;
    for (final y in [27.0, 31.5]) {
      canvas.drawLine(Offset(19.8, y), Offset(28.2, y), seam);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FireflyPainter old) => old.p != p;
}
