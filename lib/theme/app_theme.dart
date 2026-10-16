import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/app_spacing.dart';

/// Material's [ColorScheme] has no "success" role, and this app needs
/// exactly one — used consistently for every "something good happened"
/// moment (PR indicator, streak heatmap, rest-timer completion). A
/// deliberately muted moss/forest green, not emerald, not neon.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
  });

  static const light = AppSemanticColors(
    success: Color(0xFF3C7A57),
    onSuccess: Colors.white,
    successContainer: Color(0xFFD8ECDD),
    onSuccessContainer: Color(0xFF163828),
  );
  static const dark = AppSemanticColors(
    success: Color(0xFF8FCBA3),
    onSuccess: Color(0xFF0B2A1A),
    successContainer: Color(0xFF1F4A34),
    onSuccessContainer: Color(0xFFC9E9D4),
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
  }) =>
      AppSemanticColors(
        success: success ?? this.success,
        onSuccess: onSuccess ?? this.onSuccess,
        successContainer: successContainer ?? this.successContainer,
        onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      );

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) =>
      other is AppSemanticColors
          ? AppSemanticColors(
              success: Color.lerp(success, other.success, t)!,
              onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
              successContainer: Color.lerp(successContainer, other.successContainer, t)!,
              onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
            )
          : this;
}

/// Builds this app's light/dark themes: a deep petrol/teal seed (capable and
/// technical, not a stock Material demo blue and not fitness-cliché neon), a
/// warm copper secondary a single seed can't derive on its own, and the
/// [AppSemanticColors] "success" token used everywhere something good
/// happens. Energetic and sharp, never gamified — no gold "achievement"
/// colors, no confetti-adjacent palette choices.
class AppTheme {
  const AppTheme._();

  /// The built-in palette. Also what the Settings "Reset" button restores, so
  /// these are the single source of truth for "default" — the profile stores
  /// null rather than a copy of these values.
  static const defaultAccent = Color(0xFF0B6E77);
  static const defaultHighlightLight = Color(0xFF8A5A22);
  static const defaultHighlightDark = Color(0xFFE3B579);

  /// Builds the light theme. [accent] seeds the whole Material 3 scheme and
  /// [highlight] replaces the copper secondary; null means the built-in
  /// palette, reproduced exactly.
  ///
  /// Seeding rather than assigning raw colours is deliberate: Material derives
  /// every surface and on-colour from the seed with guaranteed contrast, so no
  /// colour the user can pick makes the app unreadable.
  static ThemeData light({Color? accent, Color? highlight}) =>
      _build(Brightness.light, accent: accent, highlight: highlight);

  static ThemeData dark({Color? accent, Color? highlight}) =>
      _build(Brightness.dark, accent: accent, highlight: highlight);

  static ThemeData _build(
    Brightness brightness, {
    Color? accent,
    Color? highlight,
  }) {
    final isDark = brightness == Brightness.dark;
    final seed = accent ?? defaultAccent;

    var colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    // The container/on-colour pairs for a custom highlight are derived from a
    // second seeded scheme rather than hand-picked, so a user colour gets the
    // same contrast guarantees the built-in copper was tuned for by hand.
    ColorScheme? highlightScheme;
    if (highlight != null) {
      highlightScheme =
          ColorScheme.fromSeed(seedColor: highlight, brightness: brightness);
    }

    colorScheme = isDark
        ? colorScheme.copyWith(
            secondary: highlight ?? const Color(0xFFE3B579),
            onSecondary: highlightScheme?.onPrimary ?? const Color(0xFF4A2E00),
            secondaryContainer:
                highlightScheme?.primaryContainer ?? const Color(0xFF5C3D12),
            onSecondaryContainer:
                highlightScheme?.onPrimaryContainer ?? const Color(0xFFF2DDBD),
            // Material's auto-derived tonal primaryContainer for the default
            // seed lands on a pale, saturated cyan that reads as "bright light
            // blue" rather than a deliberate extension of the petrol
            // identity — override with a deliberately muted, desaturated
            // teal instead. Only for the default seed: a custom accent has no
            // petrol identity to protect, and its own derived container is
            // the better answer.
            primaryContainer:
                accent == null ? const Color(0xFF1E3E3C) : null,
            onPrimaryContainer:
                accent == null ? const Color(0xFFD6E4E2) : null,
          )
        : colorScheme.copyWith(
            secondary: highlight ?? const Color(0xFF8A5A22),
            onSecondary: highlightScheme?.onPrimary ?? Colors.white,
            secondaryContainer:
                highlightScheme?.primaryContainer ?? const Color(0xFFF2DDBD),
            onSecondaryContainer:
                highlightScheme?.onPrimaryContainer ?? const Color(0xFF4A3110),
            primaryContainer:
                accent == null ? const Color(0xFFD6E4E2) : null,
            onPrimaryContainer:
                accent == null ? const Color(0xFF13322F) : null,
          );

    final textTheme = _buildTextTheme(colorScheme.onSurface);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,
      extensions: [isDark ? AppSemanticColors.dark : AppSemanticColors.light],
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.secondaryContainer,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 1,
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        showCheckmark: false,
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.secondaryContainer,
        labelStyle: textTheme.labelLarge,
        side: BorderSide.none,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
    );
  }

  static TextTheme _buildTextTheme(Color baseColor) {
    return TextTheme(
      headlineSmall: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: baseColor),
      titleLarge: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: baseColor),
      titleMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: baseColor),
      titleSmall: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: baseColor),
      bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, height: 1.35, color: baseColor),
      bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, height: 1.35, color: baseColor),
      bodySmall: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: baseColor),
      labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: baseColor),
      labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: baseColor),
      labelSmall: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: baseColor),
    );
  }
}

/// Convenience accessor for the app's "success" semantic color, used for
/// every "something good happened" moment (PR indicator, streak heatmap,
/// rest-timer completion) instead of ad hoc [Colors.green].
extension AppSemanticColorsX on BuildContext {
  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>()!;
}
