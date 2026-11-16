import 'package:flutter/material.dart';

abstract final class CafeColors {
  static const charcoal = Color(0xFF20242A);
  static const graphite = Color(0xFF292E36);
  static const coral = Color(0xFFFF4B2F);
  static const mint = Color(0xFFEEFFEC);
  static const ivory = Color(0xFFF5F4E9);
}

abstract final class CafeSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const radius = 20.0;
  static const desktop = 1000.0;
}

abstract final class CafeTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: CafeColors.coral,
          brightness: brightness,
        ).copyWith(
          primary: CafeColors.coral,
          onPrimary: CafeColors.charcoal,
          primaryContainer: dark
              ? const Color(0xFF593127)
              : const Color(0xFFFFE4DB),
          onPrimaryContainer: dark ? CafeColors.ivory : CafeColors.charcoal,
          secondary: dark ? CafeColors.mint : const Color(0xFF395C42),
          onSecondary: dark ? CafeColors.charcoal : Colors.white,
          surface: dark ? CafeColors.graphite : const Color(0xFFFFFEF9),
          onSurface: dark ? CafeColors.ivory : CafeColors.charcoal,
          onSurfaceVariant: dark
              ? const Color(0xFFBFC3C5)
              : const Color(0xFF5A6064),
          outline: dark ? const Color(0xFF81868C) : const Color(0xFF777C80),
          outlineVariant: dark
              ? const Color(0xFF414751)
              : const Color(0xFFE1E2D9),
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Inter',
      brightness: brightness,
    );
    final text = base.textTheme;
    return base.copyWith(
      scaffoldBackgroundColor: dark ? CafeColors.charcoal : CafeColors.ivory,
      textTheme: text.copyWith(
        displayLarge: text.displayLarge?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w600,
          letterSpacing: -2,
        ),
        displayMedium: text.displayMedium?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w600,
          letterSpacing: -1.5,
        ),
        headlineLarge: text.headlineLarge?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w600,
          letterSpacing: -1,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w600,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: text.bodyMedium?.copyWith(height: 1.55),
        bodyLarge: text.bodyLarge?.copyWith(height: 1.55),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CafeSpace.radius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: scheme.surface,
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 400),
      ),
    );
  }
}
