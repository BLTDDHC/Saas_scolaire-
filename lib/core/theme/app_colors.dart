import 'package:flutter/material.dart';

/// Palette de couleurs EduPro — reproduction exacte de variables.css
class AppColors {
  AppColors._();

  // ---- Couleurs Primaires (Indigo) ----
  static const primary50  = Color(0xFFEEF2FF);
  static const primary100 = Color(0xFFE0E7FF);
  static const primary200 = Color(0xFFC7D2FE);
  static const primary300 = Color(0xFFA5B4FC);
  static const primary400 = Color(0xFF818CF8);
  static const primary500 = Color(0xFF6366F1);
  static const primary600 = Color(0xFF4F46E5);
  static const primary700 = Color(0xFF4338CA);
  static const primary800 = Color(0xFF3730A3);
  static const primary900 = Color(0xFF312E81);

  // ---- Couleurs Secondaires (Violet) ----
  static const secondary50  = Color(0xFFF5F3FF);
  static const secondary100 = Color(0xFFEDE9FE);
  static const secondary200 = Color(0xFFDDD6FE);
  static const secondary300 = Color(0xFFC4B5FD);
  static const secondary400 = Color(0xFFA78BFA);
  static const secondary500 = Color(0xFF8B5CF6);
  static const secondary600 = Color(0xFF7C3AED);
  static const secondary700 = Color(0xFF6D28D9);
  static const secondary800 = Color(0xFF5B21B6);
  static const secondary900 = Color(0xFF4C1D95);

  // ---- Couleurs Sémantiques ----
  static const success50  = Color(0xFFECFDF5);
  static const success100 = Color(0xFFD1FAE5);
  static const success500 = Color(0xFF10B981);
  static const success600 = Color(0xFF059669);
  static const success700 = Color(0xFF047857);

  static const warning50  = Color(0xFFFFFBEB);
  static const warning100 = Color(0xFFFEF3C7);
  static const warning500 = Color(0xFFF59E0B);
  static const warning600 = Color(0xFFD97706);
  static const warning700 = Color(0xFFB45309);

  static const danger50  = Color(0xFFFEF2F2);
  static const danger100 = Color(0xFFFEE2E2);
  static const danger500 = Color(0xFFEF4444);
  static const danger600 = Color(0xFFDC2626);
  static const danger700 = Color(0xFFB91C1C);

  static const info50  = Color(0xFFEFF6FF);
  static const info100 = Color(0xFFDBEAFE);
  static const info500 = Color(0xFF3B82F6);
  static const info600 = Color(0xFF2563EB);
  static const info700 = Color(0xFF1D4ED8);

  // ---- Gris / Neutres ----
  static const gray50  = Color(0xFFF8FAFC);
  static const gray100 = Color(0xFFF1F5F9);
  static const gray200 = Color(0xFFE2E8F0);
  static const gray300 = Color(0xFFCBD5E1);
  static const gray400 = Color(0xFF94A3B8);
  static const gray500 = Color(0xFF64748B);
  static const gray600 = Color(0xFF475569);
  static const gray700 = Color(0xFF334155);
  static const gray800 = Color(0xFF1E293B);
  static const gray900 = Color(0xFF0F172A);
  static const gray950 = Color(0xFF020617);

  // ---- Light Mode Tokens ----
  static const lightBgBody       = Color(0xFFF1F5F9);
  static const lightBgSidebar    = Color(0xFFFFFFFF);
  static const lightBgHeader     = Color(0xFFFFFFFF);
  static const lightBgCard       = Color(0xFFFFFFFF);
  static const lightBgInput      = Color(0xFFFFFFFF);
  static const lightBgHover      = Color(0xFFF8FAFC);
  static const lightBgActive     = Color(0xFFEEF2FF); // primary-50
  static const lightBgTableStripe = Color(0xFFF8FAFC);
  static const lightTextPrimary   = Color(0xFF0F172A);
  static const lightTextSecondary = Color(0xFF475569);
  static const lightTextTertiary  = Color(0xFF94A3B8);
  static const lightTextInverse   = Color(0xFFFFFFFF);
  static const lightBorderColor   = Color(0xFFE2E8F0);
  static const lightBorderLight   = Color(0xFFF1F5F9);
  static const lightDivider       = Color(0xFFE2E8F0);
  static const lightModalOverlay  = Color(0x990F172A);

  // ---- Dark Mode Tokens ----
  static const darkBgBody        = Color(0xFF0F172A);
  static const darkBgSidebar     = Color(0xFF1E293B);
  static const darkBgHeader      = Color(0xFF1E293B);
  static const darkBgCard        = Color(0xFF1E293B);
  static const darkBgInput       = Color(0xFF0F172A);
  static const darkBgHover       = Color(0xFF334155);
  static const darkBgActive      = Color(0x264F46E5); // rgba(79,70,229,0.15)
  static const darkBgTableStripe = Color(0xFF162032);
  static const darkTextPrimary   = Color(0xFFF1F5F9);
  static const darkTextSecondary = Color(0xFF94A3B8);
  static const darkTextTertiary  = Color(0xFF64748B);
  static const darkTextInverse   = Color(0xFF0F172A);
  static const darkBorderColor   = Color(0xFF334155);
  static const darkBorderLight   = Color(0xFF1E293B);
  static const darkDivider       = Color(0xFF334155);
  static const darkModalOverlay  = Color(0xB3000000);

  // ---- Couleurs d'avatar ----
  static const List<Color> avatarColors = [
    Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFF3B82F6),
    Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFFEF4444),
    Color(0xFFEC4899), Color(0xFF8B5CF6), Color(0xFF06B6D4),
    Color(0xFFF97316),
  ];

  /// Retourne une couleur d'avatar déterministe basée sur le nom
  static Color avatarColorFor(String name) {
    int hash = 0;
    for (int i = 0; i < name.length; i++) {
      hash = name.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return avatarColors[hash.abs() % avatarColors.length];
  }
}
