// From Soloza's `app/theme/fonts.dart`: the three type roles. HireFly ships
// the default set only, so the font picker and registry scan are left out.
import 'package:flutter/material.dart';

@immutable
class AppFonts extends ThemeExtension<AppFonts> {
  const AppFonts({this.ui = 'Commissioner', this.display = 'Lora', this.numbers = 'DM Mono'});

  /// Controls, tables, labels.
  final String ui;

  /// Headings and the owner's own writing.
  final String display;

  /// Figures that line up, and code.
  final String numbers;

  @override
  AppFonts copyWith({String? ui, String? display, String? numbers}) =>
      AppFonts(ui: ui ?? this.ui, display: display ?? this.display, numbers: numbers ?? this.numbers);

  @override
  AppFonts lerp(AppFonts? other, double t) => other == null || t < 0.5 ? this : other;
}

extension FontsContext on BuildContext {
  AppFonts get fonts => Theme.of(this).extension<AppFonts>() ?? const AppFonts();
}
