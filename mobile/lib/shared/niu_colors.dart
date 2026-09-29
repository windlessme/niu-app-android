import 'package:flutter/material.dart';

@immutable
class NiuColors extends ThemeExtension<NiuColors> {
  const NiuColors({
    required this.background,
    required this.surface,
    required this.elevated,
    required this.text,
    required this.secondary,
    required this.tertiary,
    required this.separator,
    required this.accent,
    required this.warning,
    required this.success,
    required this.error,
    this.controlSurface,
    this.navSurface,
    this.softAccent,
    this.selectedControl,
  });
  final Color background,
      surface,
      elevated,
      text,
      secondary,
      tertiary,
      separator,
      accent,
      warning,
      success,
      error;
  final Color? controlSurface, navSurface, softAccent, selectedControl;
  Color get selectedControlSurface => selectedControl ?? elevated;
  Color get pageBackground => background;
  Color get cardSurface => surface;
  Color get navigationSurface => navSurface ?? surface;
  // Compatibility aliases preserve existing feature code and palette roles.
  Color get groupedBackground => background;
  Color get surfaceSecondary => controlSurface ?? surface;
  Color get surfaceTertiary => elevated;
  Color get label => text;
  Color get secondaryLabel => secondary;
  Color get tertiaryLabel => tertiary;
  Color get fill => text.withValues(alpha: .12);
  Color get secondaryFill => text.withValues(alpha: .08);
  Color get tertiaryFill => text.withValues(alpha: .05);
  Color get accentSoft => softAccent ?? accent.withValues(alpha: .12);
  Color get infoSoft => accentSoft;
  Color get accentMedium => accent.withValues(alpha: .25);
  Color get info => accent;
  static const light = NiuColors(
    background: Color(0xffe8edf3),
    surface: Colors.white,
    elevated: Color(0xffcdd7e3),
    controlSurface: Color(0xffd9e2ed),
    navSurface: Colors.white,
    softAccent: Color(0xffdbeaff),
    selectedControl: Colors.white,
    text: Color(0xff1c1c1e),
    secondary: Color(0xff606069),
    tertiary: Color(0xff73737d),
    separator: Color(0xffd9d9df),
    accent: Color(0xff0066cc),
    warning: Color(0xff9c5700),
    success: Color(0xff208044),
    error: Color(0xffc83332),
  );
  static const dark = NiuColors(
    background: Colors.black,
    surface: Color(0xff1c1c1e),
    elevated: Color(0xff242426),
    text: Color(0xfff5f5f7),
    secondary: Color(0xffb8b8c0),
    tertiary: Color(0xff9898a2),
    separator: Color(0xff38383a),
    accent: Color(0xff69adff),
    warning: Color(0xffffbd62),
    success: Color(0xff72d694),
    error: Color(0xffff8580),
  );
  static NiuColors of(BuildContext context) =>
      Theme.of(context).extension<NiuColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);
  @override
  NiuColors copyWith({
    Color? controlSurface,
    Color? navSurface,
    Color? softAccent,
    Color? selectedControl,
    Color? background,
    Color? surface,
    Color? elevated,
    Color? text,
    Color? secondary,
    Color? tertiary,
    Color? separator,
    Color? accent,
    Color? warning,
    Color? success,
    Color? error,
  }) => NiuColors(
    controlSurface: controlSurface ?? this.controlSurface,
    navSurface: navSurface ?? this.navSurface,
    softAccent: softAccent ?? this.softAccent,
    selectedControl: selectedControl ?? this.selectedControl,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    elevated: elevated ?? this.elevated,
    text: text ?? this.text,
    secondary: secondary ?? this.secondary,
    tertiary: tertiary ?? this.tertiary,
    separator: separator ?? this.separator,
    accent: accent ?? this.accent,
    warning: warning ?? this.warning,
    success: success ?? this.success,
    error: error ?? this.error,
  );
  @override
  NiuColors lerp(covariant NiuColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return NiuColors(
      controlSurface: mix(surfaceSecondary, other.surfaceSecondary),
      navSurface: mix(navigationSurface, other.navigationSurface),
      softAccent: mix(accentSoft, other.accentSoft),
      selectedControl: mix(
        selectedControlSurface,
        other.selectedControlSurface,
      ),
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      elevated: mix(elevated, other.elevated),
      text: mix(text, other.text),
      secondary: mix(secondary, other.secondary),
      tertiary: mix(tertiary, other.tertiary),
      separator: mix(separator, other.separator),
      accent: mix(accent, other.accent),
      warning: mix(warning, other.warning),
      success: mix(success, other.success),
      error: mix(error, other.error),
    );
  }
}

abstract final class NiuSpacing {
  static const double xs = 4,
      sm = 8,
      md = 12,
      lg = 16,
      xl = 20,
      xxl = 24,
      xxxl = 32,
      x4l = 48;
  // Semantic cross-platform roles. page=20 is the established Android gutter.
  static const double inline = sm,
      compact = md,
      content = lg,
      section = xxl,
      large = xxxl,
      spacious = x4l,
      page = xl;
}

abstract final class NiuRadius {
  static const double xsmall = 6,
      small = 10,
      medium = 14,
      large = 18,
      xlarge = 24,
      xxlarge = 32,
      pill = 999;
  static const double card = xlarge, hero = xxlarge, control = medium;
}
