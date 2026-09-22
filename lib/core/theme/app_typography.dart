import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Styles typographiques EduPro — reproduction exacte de variables.css
/// Font: Inter, tailles de 12px à 36px
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'Inter';

  // ---- Tailles ----
  static const double xs   = 12.0;  // --font-size-xs
  static const double sm   = 13.0;  // --font-size-sm
  static const double base = 14.0;  // --font-size-base
  static const double md   = 16.0;  // --font-size-md
  static const double lg   = 18.0;  // --font-size-lg
  static const double xl   = 20.0;  // --font-size-xl
  static const double xxl  = 24.0;  // --font-size-2xl
  static const double xxxl = 30.0;  // --font-size-3xl
  static const double xxxxl = 36.0; // --font-size-4xl

  // ---- Poids ----
  static const FontWeight wNormal   = FontWeight.w400;
  static const FontWeight wMedium   = FontWeight.w500;
  static const FontWeight wSemibold = FontWeight.w600;
  static const FontWeight wBold     = FontWeight.w700;
  static const FontWeight wExtrabold = FontWeight.w800;

  // ---- Line heights ----
  static const double lhTight   = 1.25;
  static const double lhNormal  = 1.5;
  static const double lhRelaxed = 1.75;

  // ---- Styles pré-définis (Light mode) ----
  static TextStyle heading1({Color? color}) => TextStyle(
    fontSize: xxxxl,
    fontWeight: wBold,
    height: lhTight,
    color: color ?? AppColors.lightTextPrimary,
  );

  static TextStyle heading2({Color? color}) => TextStyle(
    fontSize: xxl,
    fontWeight: wBold,
    height: lhTight,
    color: color ?? AppColors.lightTextPrimary,
  );

  static TextStyle heading3({Color? color}) => TextStyle(
    fontSize: xl,
    fontWeight: wSemibold,
    height: lhTight,
    color: color ?? AppColors.lightTextPrimary,
  );

  static TextStyle heading4({Color? color}) => TextStyle(
    fontSize: lg,
    fontWeight: wSemibold,
    height: lhTight,
    color: color ?? AppColors.lightTextPrimary,
  );

  static TextStyle bodyLarge({Color? color}) => TextStyle(
    fontSize: md,
    fontWeight: wNormal,
    height: lhNormal,
    color: color ?? AppColors.lightTextPrimary,
  );

  static TextStyle body({Color? color}) => TextStyle(
    fontSize: base,
    fontWeight: wNormal,
    height: lhNormal,
    color: color ?? AppColors.lightTextPrimary,
  );

  static TextStyle bodySmall({Color? color}) => TextStyle(
    fontSize: sm,
    fontWeight: wNormal,
    height: lhNormal,
    color: color ?? AppColors.lightTextSecondary,
  );

  static TextStyle caption({Color? color}) => TextStyle(
    fontSize: xs,
    fontWeight: wNormal,
    height: lhNormal,
    color: color ?? AppColors.lightTextTertiary,
  );

  static TextStyle label({Color? color}) => TextStyle(
    fontSize: sm,
    fontWeight: wMedium,
    height: lhNormal,
    color: color ?? AppColors.lightTextPrimary,
  );

  static TextStyle buttonText({Color? color}) => TextStyle(
    fontSize: sm,
    fontWeight: wMedium,
    height: lhNormal,
    color: color ?? Colors.white,
  );

  static TextStyle badgeText({Color? color}) => TextStyle(
    fontSize: xs,
    fontWeight: wMedium,
    height: 1.0,
    color: color,
  );

  static TextStyle statValue({Color? color}) => TextStyle(
    fontSize: xxxl,
    fontWeight: wBold,
    height: lhTight,
    color: color ?? AppColors.lightTextPrimary,
  );
}
