import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Servexa brand v2 (PRODUCT.md §6): indigo primary + amber accent,
/// Poppins headings over Inter body, pill buttons, 16–20px corners.
abstract final class AppTheme {
  static const seed = Color(0xFF4F46E5);
  static const accent = Color(0xFFF59E0B);

  static ThemeData get light => _base(Brightness.light);
  static ThemeData get dark => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = GoogleFonts.interTextTheme(base.textTheme);
    final headingFamily = GoogleFonts.poppins().fontFamily;
    return base.copyWith(
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(
            fontFamily: headingFamily, fontWeight: FontWeight.w600),
        titleLarge: text.titleLarge?.copyWith(
            fontFamily: headingFamily, fontWeight: FontWeight.w600),
        titleMedium: text.titleMedium?.copyWith(fontFamily: headingFamily),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: text.titleLarge?.copyWith(
          fontFamily: headingFamily,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
      ),
    );
  }
}
