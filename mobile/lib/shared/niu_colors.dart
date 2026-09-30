import 'package:flutter/material.dart';

/// Semantic palette. Surfaces follow a three-layer model shared with iOS:
/// canvas (page) → surface (card) → fill (controls and wells inside a card).
@immutable
class NiuColors extends ThemeExtension<NiuColors> {
  const NiuColors({
    required this.canvas,
    required this.surface,
    required this.raised,
    required this.ink,
    required this.inkSecondary,
    required this.inkTertiary,
    required this.hairline,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.error,
    required this.fill,
    required this.fillStrong,
    required this.shadow,
  });

  /// Page background behind cards.
  final Color canvas;

  /// Cards, grouped lists, navigation bar.
  final Color surface;

  /// Sheets, menus and selected thumbs that sit above a surface.
  final Color raised;
  final Color ink, inkSecondary, inkTertiary;
  final Color hairline;
  final Color accent, onAccent, accentSoft;
  final Color success, warning, error;

  /// Translucent wells; readable on both canvas and surface.
  final Color fill, fillStrong;
  final Color shadow;

  static const light = NiuColors(
    canvas: Color(0xfff2f3f7),
    surface: Colors.white,
    raised: Colors.white,
    ink: Color(0xff15171c),
    inkSecondary: Color(0xff5a5f6b),
    inkTertiary: Color(0xff737885),
    hairline: Color(0xffe2e4ea),
    accent: Color(0xff0a62d0),
    onAccent: Colors.white,
    accentSoft: Color(0xffe5eefc),
    success: Color(0xff1b7f45),
    warning: Color(0xff9a5400),
    error: Color(0xffc9302a),
    fill: Color(0x0d15171c),
    fillStrong: Color(0x1a15171c),
    shadow: Color(0x0f0c1830),
  );

  static const dark = NiuColors(
    canvas: Colors.black,
    surface: Color(0xff17181c),
    raised: Color(0xff232429),
    ink: Color(0xfff3f4f7),
    inkSecondary: Color(0xffabafba),
    inkTertiary: Color(0xff8c909b),
    hairline: Color(0xff2d2f35),
    accent: Color(0xff62a3ff),
    onAccent: Color(0xff04142c),
    accentSoft: Color(0xff15284a),
    success: Color(0xff5fd38c),
    warning: Color(0xfff4b04e),
    error: Color(0xffff7b72),
    fill: Color(0x14f3f4f7),
    fillStrong: Color(0x24f3f4f7),
    shadow: Color(0x00000000),
  );

  static NiuColors of(BuildContext context) =>
      Theme.of(context).extension<NiuColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  NiuColors copyWith({
    Color? canvas,
    Color? surface,
    Color? raised,
    Color? ink,
    Color? inkSecondary,
    Color? inkTertiary,
    Color? hairline,
    Color? accent,
    Color? onAccent,
    Color? accentSoft,
    Color? success,
    Color? warning,
    Color? error,
    Color? fill,
    Color? fillStrong,
    Color? shadow,
  }) => NiuColors(
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    raised: raised ?? this.raised,
    ink: ink ?? this.ink,
    inkSecondary: inkSecondary ?? this.inkSecondary,
    inkTertiary: inkTertiary ?? this.inkTertiary,
    hairline: hairline ?? this.hairline,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    accentSoft: accentSoft ?? this.accentSoft,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    error: error ?? this.error,
    fill: fill ?? this.fill,
    fillStrong: fillStrong ?? this.fillStrong,
    shadow: shadow ?? this.shadow,
  );

  @override
  NiuColors lerp(covariant NiuColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return NiuColors(
      canvas: mix(canvas, other.canvas),
      surface: mix(surface, other.surface),
      raised: mix(raised, other.raised),
      ink: mix(ink, other.ink),
      inkSecondary: mix(inkSecondary, other.inkSecondary),
      inkTertiary: mix(inkTertiary, other.inkTertiary),
      hairline: mix(hairline, other.hairline),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      accentSoft: mix(accentSoft, other.accentSoft),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      error: mix(error, other.error),
      fill: mix(fill, other.fill),
      fillStrong: mix(fillStrong, other.fillStrong),
      shadow: mix(shadow, other.shadow),
    );
  }
}

/// Feature identity hues, mirroring the per-feature colours used on iOS.
/// Each hue resolves to a readable foreground and a quiet tinted background.
enum NiuHue {
  blue(Color(0xff0a62d0), Color(0xff62a3ff)),
  indigo(Color(0xff4f46c8), Color(0xff9d97ff)),
  purple(Color(0xff8a3fc4), Color(0xffcf96ff)),
  pink(Color(0xffc2336f), Color(0xffff8fbb)),
  orange(Color(0xffb85300), Color(0xffffa45c)),
  amber(Color(0xff8f6500), Color(0xffffc94d)),
  green(Color(0xff1b7f45), Color(0xff5fd38c)),
  teal(Color(0xff00786f), Color(0xff4fd6c8)),
  cyan(Color(0xff00729a), Color(0xff5ccff5)),
  red(Color(0xffc9302a), Color(0xffff7b72)),
  gray(Color(0xff5a5f6b), Color(0xffabafba));

  const NiuHue(this.light, this.dark);
  final Color light, dark;

  Color foreground(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  Color background(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return foreground(context).withValues(alpha: dark ? .18 : .11);
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
      huge = 48;

  /// Horizontal page gutter.
  static const double gutter = xl;

  /// Vertical rhythm between page sections.
  static const double section = 28;
}

abstract final class NiuRadius {
  static const double xs = 6,
      sm = 8,
      md = 12,
      lg = 16,
      xl = 20,
      xxl = 28,
      pill = 999;

  static const double card = xl, tile = md, control = 14, sheet = xxl;
}

abstract final class NiuSize {
  static const double touchTarget = 48;
  static const double iconTile = 40, iconTileLarge = 52;
  static const double buttonHeight = 52, buttonHeightCompact = 44;
  static const double navigationBar = 72;
}

abstract final class NiuShadow {
  static List<BoxShadow> card(BuildContext context) {
    final color = NiuColors.of(context).shadow;
    if (color.a == 0) return const [];
    return [
      BoxShadow(color: color, blurRadius: 12, offset: const Offset(0, 2)),
    ];
  }
}
