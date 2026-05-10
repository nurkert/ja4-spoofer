import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Centralized theme setup.
///
/// We keep all colors in one place so visual refinements do not touch feature
/// code. The app uses shadcn_ui as the primary design system.
final class Ja4Theme {
  static ShadThemeData light() {
    return ShadThemeData(
      brightness: Brightness.light,
      colorScheme: ShadStoneColorScheme.light(),
      radius: BorderRadius.circular(14),
      textTheme: ShadTextTheme(family: 'Geist'),
    );
  }

  static ShadThemeData dark() {
    return ShadThemeData(
      brightness: Brightness.dark,
      colorScheme: ShadStoneColorScheme.dark(),
      radius: BorderRadius.circular(14),
      textTheme: ShadTextTheme(family: 'Geist'),
    );
  }
}
