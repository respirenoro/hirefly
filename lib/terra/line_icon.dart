import 'package:flutter/material.dart';

import 'line_icon_data.dart';

/// The interface's line icons, drawn from their paths at any size, with round
/// caps and joins and a stroke of 1.6 on a 24 box unless told otherwise.
class LineIcon extends StatelessWidget {
  const LineIcon(this.name, {super.key, this.size, this.color, this.stroke = 1.6, this.fill = false, this.semanticLabel, this.shadows});
  final String name;

  /// Like [Icon], the surrounding [IconTheme]'s size when not given.
  final double? size;
  final Color? color;
  final double stroke;

  /// Filled instead of outlined.
  final bool fill;
  final String? semanticLabel;

  /// Drawn under the icon, as [Icon.shadows] are.
  final List<Shadow>? shadows;

  static final _cache = <String, List<Path>>{};

  /// The paths of an icon on a 24 box; empty for an unknown name.
  static List<Path> pathsOf(String name) => _cache[name] ??= [for (final s in lineIconData[name] ?? const <String>[]) parseIconShape(s)];

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    // No colour and no icon theme: the theme's text colour, never black on a dark palette (E12).
    final c = color ?? theme.color ?? Theme.of(context).colorScheme.onSurface;
    final icon = CustomPaint(size: Size.square(size ?? theme.size ?? 24), painter: _IconPainter(pathsOf(name), c, stroke, fill, shadows));
    return semanticLabel == null ? ExcludeSemantics(child: icon) : Semantics(label: semanticLabel, child: icon);
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.paths, this.color, this.stroke, this.fill, this.shadows);
  final List<Path> paths;
  final Color color;
  final double stroke;
  final bool fill;
  final List<Shadow>? shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true
      ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.scale(size.width / 24);
    for (final s in shadows ?? const <Shadow>[]) {
      final shade = Paint()
        ..color = s.color
        ..style = paint.style
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.blurSigma * 24 / size.width);
      for (final p in paths) {
        canvas.drawPath(p.shift(s.offset * 24 / size.width), shade);
      }
    }
    for (final p in paths) {
      canvas.drawPath(p, paint);
    }
  }

  @override
  bool shouldRepaint(_IconPainter o) => !identical(o.paths, paths) || o.color != color || o.stroke != stroke || o.fill != fill || o.shadows != shadows;
}

final _token = RegExp(r'[a-zA-Z]|-?\d*\.?\d+');

/// One shape: SVG path text, or `circle cx cy r`, or `rect x y w h rx`.
Path parseIconShape(String shape) {
  final parts = shape.split(' ');
  double n(int i) => double.parse(parts[i]);
  if (parts.first == 'circle') return Path()..addOval(Rect.fromCircle(center: Offset(n(1), n(2)), radius: n(3)));
  if (parts.first == 'rect') {
    return Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(n(1), n(2), n(3), n(4)), Radius.circular(n(5))));
  }
  return parseSvgPath(shape);
}

/// Enough of SVG path syntax for the icons: M L H V C S A Z, absolute and relative.
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = _token.allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0, x = 0.0, y = 0.0, startX = 0.0, startY = 0.0;
  // The last curve's second control point, which S reflects.
  var cx = 0.0, cy = 0.0;
  var cmd = '', prev = '';
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (RegExp(r'^[a-zA-Z]$').hasMatch(tokens[i])) {
      cmd = tokens[i++];
      if (cmd == 'Z' || cmd == 'z') {
        path.close();
        x = startX;
        y = startY;
        continue;
      }
    }
    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        final a = next(), b = next();
        x = rel ? x + a : a;
        y = rel ? y + b : b;
        path.moveTo(x, y);
        startX = x;
        startY = y;
        // Further pairs after a move are lines.
        cmd = rel ? 'l' : 'L';
      case 'L':
        final a = next(), b = next();
        x = rel ? x + a : a;
        y = rel ? y + b : b;
        path.lineTo(x, y);
      case 'H':
        final a = next();
        x = rel ? x + a : a;
        path.lineTo(x, y);
      case 'V':
        final a = next();
        y = rel ? y + a : a;
        path.lineTo(x, y);
      case 'C':
        final v = [for (var k = 0; k < 6; k++) next()];
        final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
        path.cubicTo(ox + v[0], oy + v[1], ox + v[2], oy + v[3], ox + v[4], oy + v[5]);
        cx = ox + v[2];
        cy = oy + v[3];
        x = ox + v[4];
        y = oy + v[5];
      case 'S':
        final v = [for (var k = 0; k < 4; k++) next()];
        final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
        final curve = prev == 'C' || prev == 'S';
        path.cubicTo(curve ? 2 * x - cx : x, curve ? 2 * y - cy : y, ox + v[0], oy + v[1], ox + v[2], oy + v[3]);
        cx = ox + v[0];
        cy = oy + v[1];
        x = ox + v[2];
        y = oy + v[3];
      case 'A':
        final rx = next(), ry = next(), rot = next(), large = next(), sweep = next(), a = next(), b = next();
        x = rel ? x + a : a;
        y = rel ? y + b : b;
        path.arcToPoint(Offset(x, y), radius: Radius.elliptical(rx, ry), rotation: rot, largeArc: large != 0, clockwise: sweep != 0);
      default:
        throw FormatException('Unknown path command $cmd in $d');
    }
    prev = cmd.toUpperCase();
  }
  return path;
}
