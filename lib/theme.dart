import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppColors {
  static const Color bg = Color(0xFF0F1217);
  static const Color panel = Color(0xFF171B22);
  static const Color panel2 = Color(0xFF1B2029);
  static const Color panel3 = Color(0xFF232A35);
  static const Color line = Color(0xFF272E39);
  static const Color lineSoft = Color(0x12FFFFFF);
  static const Color text = Color(0xFFE7EAF0);
  static const Color muted = Color(0xFF8F99AB);
  static const Color faint = Color(0xFF6B7484);
  static const Color accent = Color(0xFF7AA2FF);
  static const Color now = Color(0xFFFF7A6B);
  static const Color danger = Color(0xFFFF8A7D);
  static const Color canvas = Color(0xFF11151B);

  static Color alpha(Color color, double opacity) =>
      color.withValues(alpha: opacity);
}

ThemeData buildTimelineTheme() {
  const ColorScheme scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Color(0xFF071021),
    secondary: Color(0xFF91B2FF),
    onSecondary: Color(0xFF071021),
    surface: AppColors.panel,
    onSurface: AppColors.text,
    error: AppColors.danger,
    onError: Color(0xFF260603),
    outline: AppColors.line,
  );

  final TextTheme textTheme = Typography.material2021(
    platform: defaultTargetPlatform,
    colorScheme: scheme,
  ).white.apply(bodyColor: AppColors.text, displayColor: AppColors.text);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.panel,
    fontFamily: 'Segoe UI',
    textTheme: textTheme.copyWith(
      titleLarge: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: .1,
        color: AppColors.text,
      ),
      titleMedium: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
      bodyMedium: const TextStyle(fontSize: 12, color: AppColors.text),
      bodySmall: const TextStyle(fontSize: 10.5, color: AppColors.muted),
      labelSmall: const TextStyle(
        fontSize: 8.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: AppColors.muted,
      ),
    ),
    dividerColor: AppColors.line,
    splashFactory: InkSparkle.splashFactory,
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: AppColors.line),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.panel2,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(fontSize: 12, color: AppColors.text),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: AppColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: const Color(0xFF11151B),
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
      hintStyle: const TextStyle(fontSize: 12, color: AppColors.faint),
      labelStyle: const TextStyle(fontSize: 11, color: AppColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF20262F),
      contentTextStyle: TextStyle(fontSize: 12, color: Color(0xFFD7DEE9)),
      actionTextColor: Color(0xFFA9C3FF),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: Color(0xFF36404E)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: const Color(0xFF262D38),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF36404E)),
      ),
      textStyle: const TextStyle(fontSize: 11, color: AppColors.text),
    ),
    datePickerTheme: const DatePickerThemeData(
      backgroundColor: AppColors.panel,
      surfaceTintColor: Colors.transparent,
    ),
    timePickerTheme: const TimePickerThemeData(
      backgroundColor: AppColors.panel,
      dialBackgroundColor: Color(0xFF11151B),
    ),
  );
}

class AppText {
  static const TextStyle kicker = TextStyle(
    fontSize: 8.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
    color: AppColors.muted,
  );
  static const TextStyle label = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    color: AppColors.muted,
  );
  static const TextStyle small = TextStyle(
    fontSize: 10.5,
    color: AppColors.muted,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
  static const TextStyle body = TextStyle(fontSize: 12, color: AppColors.text);
  static const TextStyle title = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
  );
}
