import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
  /// Noto Serif KR — 헤드라인, 제목
  static TextStyle headline(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) {
    return GoogleFonts.notoSerifKr(
      fontSize: size,
      fontWeight: weight,
      color: color ?? AppColors.ink,
    );
  }

  /// Noto Sans KR — Korean-first body text
  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
  }) {
    return GoogleFonts.notoSansKr(
      fontSize: size,
      fontWeight: weight,
      color: color ?? AppColors.ink,
      height: height,
    );
  }

  /// 라벨 — 대문자 트래킹
  static TextStyle label({Color? color}) {
    return GoogleFonts.notoSansKr(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: color ?? AppColors.secondary,
    );
  }
}

// ─── Theme ───
class AppTheme {
  static ThemeData get light {
    final textTheme = GoogleFonts.notoSansKrTextTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
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
        titleTextStyle: GoogleFonts.notoSansKr(
          color: AppColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.border.withValues(alpha: 0.3)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryContainer,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.notoSansKr(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.notoSansKr(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        hintStyle: GoogleFonts.notoSansKr(
          color: AppColors.muted,
          fontWeight: FontWeight.w400,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: AppColors.border.withValues(alpha: 0.8),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
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
