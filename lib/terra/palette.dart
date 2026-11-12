// From Soloza's `app/theme/palette.dart`: the semantic colour tokens and the
// Night skin. HireFly has the one skin, so the other skins, the drawn frames
// and the backdrop art are left out; the tokens and their values are Soloza's.
import 'package:flutter/material.dart';

/// A pool of colour on the soft canvas: where it sits (fractions of the
/// window), how far it reaches in pixels, and where it has faded out.
@immutable
class CanvasGlow {
  const CanvasGlow(this.x, this.y, this.rx, this.ry, this.color, this.stop);
  final double x, y, rx, ry, stop;
  final Color color;
}

/// Semantic color tokens. Widgets never use raw hex values, only these.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.brightness,
    required this.background,
    required this.sidebar,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.onAccent,
    required this.ratingTop,
    required this.ratingHigh,
    required this.ratingMid,
    required this.ratingLow,
    required this.danger,
    this.accentInk,
    this.borderStrong,
    this.canvasBase,
    this.canvasGlows = const [],
    this.radius = 8,
  });

  final Brightness brightness;
  final Color background, sidebar, surface, surfaceRaised, border;
  final Color text, textMuted, textFaint;
  final Color accent, onAccent;
  final Color ratingTop, ratingHigh, ratingMid, ratingLow;
  final Color danger;
  final Color? accentInk, borderStrong;

  Color get ink => accentInk ?? accent;
  Color get lineStrong => borderStrong ?? border;

  /// The selected thing's quiet background.
  Color get accentSoft => accent.withValues(alpha: 0.12);

  /// Quiet fills over a window.
  Color get s2 => text.withValues(alpha: 0.05);
  Color get s3 => text.withValues(alpha: 0.09);
  Color get s3Hover => text.withValues(alpha: 0.14);

  /// The soft canvas: a ground and pools of colour over it.
  final Color? canvasBase;
  final List<CanvasGlow> canvasGlows;

  /// Corner radius of controls.
  final double radius;

  /// The frame around panels, dialogs and menus at a given corner radius.
  OutlinedBorder shape(double r) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(r), side: BorderSide(color: border));

  /// A panel: the one way to draw a card. Its fill is a faint step over the
  /// window, so the canvas still shows through. [edge] colours the border for a state.
  Decoration panel([double r = 12, Color? edge]) =>
      BoxDecoration(color: text.withValues(alpha: 0.025), borderRadius: BorderRadius.circular(r), border: Border.all(color: edge ?? border));

  /// A panel that hides what's under it.
  Decoration solidPanel([double r = 12, Color? edge]) =>
      BoxDecoration(color: surface, borderRadius: BorderRadius.circular(r), border: Border.all(color: edge ?? lineStrong));

  /// A 0-10 score's colour (Soloza's rating colours).
  Color score(double? v) => v == null ? textFaint : (v >= 8.5 ? ratingTop : (v >= 7 ? ratingHigh : (v >= 5 ? ratingMid : ratingLow)));

  /// Night: warm graphite, lamp-lit. Lines are translucent so they read the
  /// same over any canvas.
  static const dark = Palette(
    brightness: Brightness.dark,
    background: Color(0xFF141311),
    sidebar: Color(0xFF171614),
    surface: Color(0xFF191816),
    surfaceRaised: Color(0xFF2A2926),
    border: Color(0x14FFFFFF),
    borderStrong: Color(0x24FFFFFF),
    canvasBase: Color(0xFF121110),
    canvasGlows: [
      CanvasGlow(0.9, 0.04, 1000, 700, Color(0xFF7A5A22), 0.66),
      CanvasGlow(0.02, 0.96, 860, 640, Color(0xFF1F5558), 0.68),
      CanvasGlow(0.46, 0.5, 600, 460, Color(0xFF3A2A24), 0.7),
    ],
    text: Color(0xFFEFE9DE),
    textMuted: Color(0xFFBAB3A6),
    textFaint: Color(0xFF9D978B),
    accent: Color(0xFF5DB4E8),
    onAccent: Color(0xFF0B1116),
    ratingTop: Color(0xFFF5C451),
    ratingHigh: Color(0xFF5BD08A),
    ratingMid: Color(0xFFB7C46A),
    ratingLow: Color(0xFFE08A6A),
    danger: Color(0xFFEF6B5B),
  );

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) => other == null || t < 0.5 ? this : other;
}

extension PaletteContext on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>() ?? Palette.dark;
}
