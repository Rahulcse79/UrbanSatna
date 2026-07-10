// CupertinoPageTransitionsBuilder moved from the material library to the
// cupertino library across Flutter versions: current stable resolves it via
// this import, while 3.27 (the newest toolchain the macOS-12 dev Mac can
// run) still exports it from material and flags this import instead.
// ignore: unused_import, undefined_shown_name
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A named look the admin can apply to every user's app at runtime
/// (PRODUCT.md §6.5 — the UI itself is remote-controlled data).
class ThemePreset {
  const ThemePreset(this.key, this.label, this.seed, this.accent);

  final String key;
  final String label;
  final Color seed;
  final Color accent;
}

const themePresets = <ThemePreset>[
  ThemePreset('indigo', 'Indigo', Color(0xFF4F46E5), Color(0xFFF59E0B)),
  ThemePreset('emerald', 'Emerald', Color(0xFF059669), Color(0xFFF59E0B)),
  ThemePreset('crimson', 'Crimson', Color(0xFFDC2626), Color(0xFF0EA5E9)),
  ThemePreset('royal', 'Royal purple', Color(0xFF7C3AED), Color(0xFFF43F5E)),
  ThemePreset('ocean', 'Ocean', Color(0xFF0284C7), Color(0xFFF97316)),
  ThemePreset('sunset', 'Sunset', Color(0xFFEA580C), Color(0xFF6366F1)),
  ThemePreset('teal', 'Teal', Color(0xFF0D9488), Color(0xFFF59E0B)),
  ThemePreset('gold', 'Heritage gold', Color(0xFFB45309), Color(0xFF1F2937)),
  ThemePreset('rose', 'Rose', Color(0xFFE11D48), Color(0xFF14B8A6)),
];

ThemePreset presetByKey(String key) => themePresets.firstWhere(
      (p) => p.key == key,
      orElse: () => themePresets.first,
    );

/// Servexa brand v2 (PRODUCT.md §6): preset-seeded Material 3,
/// Poppins headings over Inter body, pill buttons, 16–20px corners.
abstract final class AppTheme {
  static ThemeData light(String preset) =>
      _base(Brightness.light, presetByKey(preset));
  static ThemeData dark(String preset) =>
      _base(Brightness.dark, presetByKey(preset));

  static ThemeData _base(Brightness brightness, ThemePreset preset) {
    final scheme =
        ColorScheme.fromSeed(seedColor: preset.seed, brightness: brightness);
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = GoogleFonts.interTextTheme(base.textTheme);
    final headingFamily = GoogleFonts.poppins().fontFamily;
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      // iOS-style slide transitions everywhere: premium navigation feel.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(
            fontFamily: headingFamily, fontWeight: FontWeight.w700),
        titleLarge: text.titleLarge?.copyWith(
            fontFamily: headingFamily, fontWeight: FontWeight.w600),
        titleMedium: text.titleMedium?.copyWith(fontFamily: headingFamily),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: text.titleLarge?.copyWith(
          fontFamily: headingFamily,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: scheme.onSurface,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(
          text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
