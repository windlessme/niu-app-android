import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'niu_colors.dart';

/// Type scale (Android sp):
/// display 34 · headline 30/26/22 · title 19/16/14 · body 16/15/13 · label 15/12/11.
abstract final class NiuTheme {
  static ThemeData get light => _theme(Brightness.light);
  static ThemeData get dark => _theme(Brightness.dark);

  static TextTheme _text(NiuColors c) {
    TextStyle s(
      double size,
      FontWeight weight,
      Color color, {
      double height = 1.3,
      double spacing = 0,
    }) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: spacing,
    );
    return TextTheme(
      displayLarge: s(44, FontWeight.w700, c.ink, height: 1.1, spacing: -.5),
      displayMedium: s(38, FontWeight.w700, c.ink, height: 1.1, spacing: -.4),
      displaySmall: s(34, FontWeight.w700, c.ink, height: 1.15, spacing: -.3),
      headlineLarge: s(30, FontWeight.w700, c.ink, height: 1.2, spacing: -.2),
      headlineMedium: s(26, FontWeight.w700, c.ink, height: 1.2),
      headlineSmall: s(22, FontWeight.w700, c.ink, height: 1.25),
      titleLarge: s(19, FontWeight.w700, c.ink, height: 1.3),
      titleMedium: s(16, FontWeight.w600, c.ink, height: 1.35),
      titleSmall: s(14, FontWeight.w600, c.ink, height: 1.35),
      bodyLarge: s(16, FontWeight.w400, c.ink, height: 1.5),
      bodyMedium: s(15, FontWeight.w400, c.ink, height: 1.5),
      bodySmall: s(13, FontWeight.w400, c.inkSecondary, height: 1.45),
      labelLarge: s(15, FontWeight.w600, c.ink, height: 1.2),
      labelMedium: s(12, FontWeight.w500, c.inkSecondary, height: 1.3),
      labelSmall: s(11, FontWeight.w600, c.inkTertiary, spacing: .3),
    );
  }

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final c = dark ? NiuColors.dark : NiuColors.light;
    final text = _text(c);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: c.accent,
          brightness: brightness,
        ).copyWith(
          primary: c.accent,
          onPrimary: c.onAccent,
          primaryContainer: c.accentSoft,
          onPrimaryContainer: c.accent,
          secondaryContainer: c.accentSoft,
          onSecondaryContainer: c.accent,
          surface: c.surface,
          onSurface: c.ink,
          onSurfaceVariant: c.inkSecondary,
          surfaceContainerLowest: c.surface,
          surfaceContainerLow: c.surface,
          surfaceContainer: c.canvas,
          surfaceContainerHigh: c.raised,
          surfaceContainerHighest: c.raised,
          surfaceTint: Colors.transparent,
          outline: c.inkTertiary,
          outlineVariant: c.hairline,
          error: c.error,
          onError: dark ? Colors.black : Colors.white,
        );
    const pill = StadiumBorder();
    const buttonPadding = EdgeInsets.symmetric(
      horizontal: NiuSpacing.xl,
      vertical: NiuSpacing.md,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [c],
      textTheme: text,
      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.canvas,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      iconTheme: IconThemeData(color: c.ink, size: 22),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: c.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.ink,
        titleSpacing: NiuSpacing.xs,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: overlay(brightness, c.canvas),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: NiuSize.navigationBar,
        elevation: 0,
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.accentSoft,
        indicatorShape: pill,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? c.ink
                : c.inkSecondary,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? c.accent
                : c.inkSecondary,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NiuRadius.card),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, NiuSize.buttonHeight),
          padding: buttonPadding,
          shape: pill,
          textStyle: text.labelLarge,
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          disabledBackgroundColor: c.fillStrong,
          disabledForegroundColor: c.inkTertiary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, NiuSize.buttonHeight),
          padding: buttonPadding,
          shape: pill,
          textStyle: text.labelLarge,
          foregroundColor: c.ink,
          side: BorderSide(color: c.hairline, width: 1),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(NiuSize.touchTarget, NiuSize.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: NiuSpacing.md),
          shape: pill,
          textStyle: text.labelLarge,
          foregroundColor: c.accent,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(NiuSize.touchTarget, NiuSize.touchTarget),
          foregroundColor: c.ink,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.fill,
        selectedColor: c.accentSoft,
        disabledColor: c.fill,
        side: BorderSide.none,
        shape: pill,
        showCheckmark: false,
        labelStyle: text.titleSmall?.copyWith(color: c.inkSecondary),
        secondaryLabelStyle: text.titleSmall?.copyWith(color: c.accent),
        padding: const EdgeInsets.symmetric(horizontal: NiuSpacing.xs),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.fill,
        hintStyle: text.bodyLarge?.copyWith(color: c.inkTertiary),
        labelStyle: text.bodyLarge?.copyWith(color: c.inkSecondary),
        prefixIconColor: c.inkTertiary,
        suffixIconColor: c.inkTertiary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: NiuSpacing.lg,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NiuRadius.control),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NiuRadius.control),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NiuRadius.control),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NiuRadius.control),
          borderSide: BorderSide(color: c.error, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: c.hairline,
        thickness: .8,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.inkSecondary,
        textColor: c.ink,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodySmall,
        contentPadding: const EdgeInsets.symmetric(horizontal: NiuSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NiuRadius.card),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.fill,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 6,
        borderRadius: BorderRadius.circular(NiuRadius.pill),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.raised,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.fillStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(NiuRadius.sheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.raised,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.inkSecondary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NiuRadius.sheet),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.raised,
        surfaceTintColor: Colors.transparent,
        textStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NiuRadius.lg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? c.raised : c.ink,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: dark ? c.ink : c.surface,
        ),
        actionTextColor: dark ? c.accent : const Color(0xff9cc4ff),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NiuRadius.lg),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? c.raised : c.ink,
          borderRadius: BorderRadius.circular(NiuRadius.sm),
        ),
        textStyle: text.labelMedium?.copyWith(color: dark ? c.ink : c.surface),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.ink,
        unselectedLabelColor: c.inkSecondary,
        indicatorColor: c.accent,
        dividerColor: Colors.transparent,
        labelStyle: text.titleSmall,
        unselectedLabelStyle: text.titleSmall?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: c.accent,
        scaffoldBackgroundColor: c.canvas,
        barBackgroundColor: c.canvas,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static SystemUiOverlayStyle overlay(Brightness brightness, Color navigation) {
    final dark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: navigation,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
    );
  }
}
