import 'package:flutter/material.dart';

/// Design tokens shared by every screen.
abstract final class AppColors {
  static const primary = Color(0xFF1F6E4D);
  static const primaryDark = Color(0xFF0B3A27);
  static const primarySoft = Color(0xFFDCEFE4);
  static const background = Color(0xFFF4F6F4);
  static const surface = Colors.white;
  static const surfaceMuted = Color(0xFFEEF2EF);
  static const border = Color(0xFFD9E0DB);
  static const borderSoft = Color(0xFFE6EBE7);
  static const text = Color(0xFF17211C);
  static const textMuted = Color(0xFF5A6660);
  static const textFaint = Color(0xFF8A958F);
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class AppRadius {
  static const card = 14.0;
  static const control = 10.0;
  static const pill = 999.0;
}

/// Meaning of a color, so the same state always looks the same everywhere.
enum Tone { brand, success, warning, danger, info, neutral }

class ToneColors {
  const ToneColors(this.foreground, this.background);

  final Color foreground;
  final Color background;
}

ToneColors toneColors(Tone tone) => switch (tone) {
      Tone.brand => const ToneColors(AppColors.primary, AppColors.primarySoft),
      Tone.success => const ToneColors(Color(0xFF1F7A4D), Color(0xFFE3F4EA)),
      Tone.warning => const ToneColors(Color(0xFF9A5B00), Color(0xFFFCEFD7)),
      Tone.danger => const ToneColors(Color(0xFFB42318), Color(0xFFFDE8E6)),
      Tone.info => const ToneColors(Color(0xFF1D5FA8), Color(0xFFE5EFFA)),
      Tone.neutral => const ToneColors(Color(0xFF4F5B55), Color(0xFFEBEFEC)),
    };

/// Tone of a score out of 100 (same bars as the inspection grade).
Tone toneForScore(num? score) {
  if (score == null) return Tone.neutral;
  if (score >= 90) return Tone.success;
  if (score >= 80) return Tone.success;
  if (score >= 70) return Tone.warning;
  return Tone.danger;
}

Tone toneForGrade(String? grade) => switch (grade) {
      'Excellent' || 'Good' => Tone.success,
      'Needs Improvement' => Tone.warning,
      'Critical' => Tone.danger,
      _ => Tone.neutral,
    };

Tone toneForSeverity(String? severity) => switch (severity) {
      'Critical' => Tone.danger,
      'High' => Tone.warning,
      'Medium' => Tone.info,
      _ => Tone.neutral,
    };

Tone toneForActionStatus(String? status) => switch (status) {
      'Open' => Tone.danger,
      'In Progress' => Tone.info,
      'Resolved' => Tone.success,
      'Verified' => Tone.success,
      _ => Tone.neutral,
    };

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primarySoft,
    onPrimaryContainer: AppColors.primaryDark,
    secondary: const Color(0xFF1D5FA8),
    tertiary: const Color(0xFF9A5B00),
    error: const Color(0xFFB42318),
    errorContainer: const Color(0xFFFDE8E6),
    onErrorContainer: const Color(0xFF7A1811),
    surface: AppColors.surface,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.textMuted,
    outline: AppColors.border,
    outlineVariant: AppColors.borderSoft,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: AppColors.background,
    surfaceContainerHighest: AppColors.surfaceMuted,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = _textTheme(base.textTheme);

  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: color, width: width),
      );

  final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.control));

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: text,
    primaryTextTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      shape: const Border(bottom: BorderSide(color: AppColors.borderSoft)),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.borderSoft),
      ),
    ),
    dividerTheme: const DividerThemeData(
        color: AppColors.borderSoft, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: text.bodyMedium?.copyWith(color: AppColors.textMuted),
      floatingLabelStyle: text.labelMedium?.copyWith(color: AppColors.primary),
      hintStyle: text.bodyMedium?.copyWith(color: AppColors.textFaint),
      border: border(AppColors.border),
      enabledBorder: border(AppColors.border),
      focusedBorder: border(AppColors.primary, 2),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: buttonShape,
        side: const BorderSide(color: AppColors.border),
        foregroundColor: AppColors.text,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: AppColors.primarySoft,
      labelTextStyle: WidgetStateProperty.resolveWith((states) =>
          text.labelMedium?.copyWith(
              color: states.contains(WidgetState.selected)
                  ? AppColors.primary
                  : AppColors.textMuted)),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textMuted)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.text,
      contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titleTextStyle: text.titleLarge,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: const BorderSide(color: AppColors.textFaint, width: 1.5),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: const BorderSide(color: AppColors.borderSoft)),
    ),
  );
}

TextTheme _textTheme(TextTheme base) {
  TextStyle style(TextStyle? s, double size, FontWeight weight,
          {double? height, double? letterSpacing, Color? color}) =>
      (s ?? const TextStyle()).copyWith(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color ?? AppColors.text,
      );

  return base.copyWith(
    headlineMedium:
        style(base.headlineMedium, 28, FontWeight.w700, height: 1.2),
    headlineSmall: style(base.headlineSmall, 24, FontWeight.w700, height: 1.25),
    titleLarge: style(base.titleLarge, 20, FontWeight.w700, height: 1.3),
    titleMedium: style(base.titleMedium, 16, FontWeight.w600, height: 1.35),
    titleSmall: style(base.titleSmall, 14, FontWeight.w600, height: 1.35),
    bodyLarge: style(base.bodyLarge, 16, FontWeight.w400, height: 1.45),
    bodyMedium: style(base.bodyMedium, 14, FontWeight.w400, height: 1.45),
    bodySmall: style(base.bodySmall, 12.5, FontWeight.w400,
        height: 1.4, color: AppColors.textMuted),
    labelLarge: style(base.labelLarge, 14, FontWeight.w600, letterSpacing: 0.1),
    labelMedium:
        style(base.labelMedium, 12, FontWeight.w600, letterSpacing: 0.2),
    labelSmall: style(base.labelSmall, 11, FontWeight.w600, letterSpacing: 0.3),
  );
}
