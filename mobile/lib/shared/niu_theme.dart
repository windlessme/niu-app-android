import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'niu_colors.dart';

abstract final class NiuTheme {
  static ThemeData get light => _theme(Brightness.light);
  static ThemeData get dark => _theme(Brightness.dark);
  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors = dark ? NiuColors.dark : NiuColors.light;
    final background = colors.pageBackground;
    final surface = colors.cardSurface;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xff3478f6),
          brightness: brightness,
          surface: surface,
        ).copyWith(
          primary: colors.accent,
          onPrimary: dark ? const Color(0xff0c2444) : Colors.white,
          primaryContainer: dark
              ? const Color(0xff263c58)
              : const Color(0xffe2edff),
          onPrimaryContainer: dark
              ? const Color(0xffdbe9ff)
              : const Color(0xff193455),
          onSurface: colors.text,
          onSurfaceVariant: colors.secondary,
          outlineVariant: colors.separator,
          surfaceContainerHighest: colors.elevated,
          surfaceContainerLowest: colors.cardSurface,
          surfaceContainerLow: colors.surfaceSecondary,
          surfaceContainer: colors.surfaceSecondary,
          surfaceContainerHigh: colors.surfaceTertiary,
          error: colors.error,
        );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [colors],
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: colors.text,
        ),
        displayMedium: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w700,
          color: colors.text,
        ),
        displaySmall: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w700,
          color: colors.text,
        ),
        headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: colors.text,
        ),
        headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: colors.text,
        ),
        headlineSmall: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: colors.text,
        ),
        titleLarge: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: colors.text,
        ),
        titleMedium: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: colors.text,
        ),
        titleSmall: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: colors.text,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: colors.text, height: 1.4),
        bodyMedium: TextStyle(fontSize: 16, color: colors.text, height: 1.4),
        bodySmall: TextStyle(
          fontSize: 14,
          color: colors.secondary,
          height: 1.4,
        ),
        labelSmall: TextStyle(fontSize: 12, color: colors.tertiary),
        labelMedium: TextStyle(fontSize: 12, color: colors.secondary),
        labelLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: colors.text,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(50, 50)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(50, 50)),
      ),
      scaffoldBackgroundColor: background,
      splashFactory: NoSplash.splashFactory,
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: scheme.primary,
        scaffoldBackgroundColor: background,
        barBackgroundColor: background,
        textTheme: CupertinoTextThemeData(
          primaryColor: scheme.primary,
          textStyle: TextStyle(color: scheme.onSurface, fontSize: 17),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: dark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: background,
          systemNavigationBarIconBrightness: dark
              ? Brightness.light
              : Brightness.dark,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NiuRadius.card),
          side: BorderSide(
            color: dark
                ? scheme.outlineVariant.withValues(alpha: .25)
                : Colors.transparent,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: .5),
        thickness: .5,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(NiuRadius.card),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        dividerColor: scheme.outlineVariant,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NiuRadius.control),
          borderSide: BorderSide.none,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
