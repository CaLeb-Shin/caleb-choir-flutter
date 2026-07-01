import 'package:flutter/material.dart';

// ─── Color System (HTML 디자인 레퍼런스 기반) ───
class AppColors {
  // Primary — Deep Navy
  static const primary = Color(0xFF000E24);
  static const primaryContainer = Color(0xFF00234B);
  static const primarySoft = Color(0xFFE8EDF5);

  // Secondary — Warm Gold
  static const secondary = Color(0xFF775A19);
  static const secondaryContainer = Color(0xFFFED488);
  static const secondarySoft = Color(0xFFFFF8E8);

  // Text
  static const ink = Color(0xFF191C1D);
  static const onSurfaceVariant = Color(0xFF43474E);
  static const muted = Color(0xFF74777F);
  static const subtle = Color(0xFFC4C6D0);

  // Surfaces
  static const bg = Color(0xFFF8F9FA);
  static const card = Color(0xFFFFFFFF);
  static const paper = Color(0xFFFFFCF5);
  static const paperLine = Color(0xFFE8DEC8);
  static const paperFold = Color(0xFFF4EBD9);
  static const surfaceLow = Color(0xFFF3F4F5);
  static const surfaceMid = Color(0xFFEDEEEF);
  static const surfaceHigh = Color(0xFFE7E8E9);

  // Utility
  static const border = Color(0xFFC4C6D0);
  static const error = Color(0xFFBA1A1A);
  static const success = Color(0xFF2E7D32);

  // Legacy aliases
  static const accent = primary;
  static const accentSoft = primarySoft;
  static const warm = secondary;
  static const warmSoft = secondarySoft;
  static const onSurface = ink;
  static const onPrimary = Color(0xFFFFFFFF);
  static const background = bg;
  static const surface = card;
}

// ─── Typography Helpers ───
class AppText {
  static const _fallbackFonts = [
    'Apple Color Emoji',
    'Segoe UI Emoji',
    'Noto Color Emoji',
    // Pretendard is bundled (see pubspec `fonts:`), so Korean glyphs render on
    // web (CanvasKit) from the app itself — no runtime Noto download that a
    // proxy / security software could block, which was leaving some syllables
    // as tofu (□). The system fonts below still cover native platforms.
    'Pretendard',
    'Apple SD Gothic Neo',
    'Noto Sans CJK KR',
    'Noto Sans KR',
    'Malgun Gothic',
    'Arial',
    'sans-serif',
  ];

  // Inter is bundled as an app asset (see pubspec `fonts:`) instead of being
  // fetched at runtime, so text paints on the first frame with no network
  // round-trip or font swap. Korean falls through to the system fonts below.
  static const fontFamily = 'Inter';

  static TextStyle _inter(
    double size, {
    required FontWeight weight,
    Color? color,
    double? height,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: _fallbackFonts,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }

  /// Inter — 헤드라인, 제목
  static TextStyle headline(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) {
    return _inter(size, weight: weight, color: color ?? AppColors.ink);
  }

  /// Inter — body text
  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
  }) {
    return _inter(
      size,
      weight: weight,
      color: color ?? AppColors.ink,
      height: height,
    );
  }

  /// 라벨 — 대문자 트래킹
  static TextStyle label({Color? color}) {
    return _inter(
      11,
      weight: FontWeight.w700,
      color: color ?? AppColors.secondary,
    );
  }
}

// ─── Theme ───
class AppTheme {
  static ThemeData get light {
    final textTheme = Typography.material2021().black.apply(
      fontFamily: AppText.fontFamily,
      fontFamilyFallback: AppText._fallbackFonts,
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: AppText.fontFamily,
      fontFamilyFallback: AppText._fallbackFonts,
      textTheme: textTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.bg,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.body(
          20,
          weight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(color: AppColors.border.withValues(alpha: 0.26)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryContainer,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: AppText.body(15, weight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: AppText.body(15, weight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        hintStyle: AppText.body(
          14,
          color: AppColors.muted,
          weight: FontWeight.w400,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.border.withValues(alpha: 0.8),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.primaryContainer,
            width: 1.4,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
      ),
    );
  }
}
