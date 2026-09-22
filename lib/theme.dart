import 'package:flutter/material.dart';

class AppColors {
  // Primary
  static const primary50 = Color(0xFFEEF2FF);
  static const primary100 = Color(0xFFE0E7FF);
  static const primary200 = Color(0xFFC7D2FE);
  static const primary300 = Color(0xFFA5B4FC);
  static const primary400 = Color(0xFF818CF8);
  static const primary500 = Color(0xFF6366F1);
  static const primary600 = Color(0xFF4F46E5);
  static const primary700 = Color(0xFF4338CA);
  static const primary800 = Color(0xFF3730A3);
  static const primary900 = Color(0xFF312E81);

  // Secondary
    static const secondary50 = Color(0xFFF5F3FF);
    static const secondary500 = Color(0xFF8B5CF6);
    static const secondary600 = Color(0xFF7C3AED);

    // Neutrals
    static const gray400 = Color(0xFF94A3B8);

  // Semantic
  static const success50 = Color(0xFFECFDF5);
  static const success500 = Color(0xFF10B981);
  static const warning50 = Color(0xFFFFFBEB);
  static const warning500 = Color(0xFFF59E0B);
  static const danger500 = Color(0xFFEF4444);
  static const info500 = Color(0xFF3B82F6);

  // Neutrals
  static const gray50 = Color(0xFFF8FAFC);
  static const gray100 = Color(0xFFF1F5F9);
  static const gray200 = Color(0xFFE2E8F0);
  static const gray300 = Color(0xFFCBD5E1);
  static const gray500 = Color(0xFF64748B);
  static const gray900 = Color(0xFF0F172A);

  // UI tokens
  static const bgBody = Color(0xFFF1F5F9);
  static const bgSidebar = Color(0xFFFFFFFF);
  static const bgHeader = Color(0xFFFFFFFF);
  static const bgCard = Color(0xFFFFFFFF);
  static const bgModalOverlay = Color(0x990F172A); // approx rgba(15,23,42,0.6)
  static const bgInput = Color(0xFFFFFFFF);
  static const bgHover = Color(0xFFF8FAFC);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF475569);
  static const borderColor = Color(0xFFE2E8F0);
}

class AppRadius {
  static const rSm = 6.0;
  static const rMd = 8.0;
  static const rLg = 12.0;
  static const rXl = 16.0;
}

class AppSpacing {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
}

class AppLayout {
  static const sidebarWidth = 240.0;
  static const sidebarCollapsedWidth = 72.0;
  static const headerHeight = 64.0;
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData.light();
    final theme = base.copyWith(
      primaryColor: AppColors.primary600,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.primary600,
        secondary: AppColors.secondary600,
        background: AppColors.bgBody,
        surface: AppColors.bgCard,
        onPrimary: AppColors.textPrimary,
      ),
      scaffoldBackgroundColor: AppColors.bgBody,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: AppColors.bgHeader,
        foregroundColor: AppColors.textPrimary,
        elevation: 1,
        toolbarHeight: AppLayout.headerHeight,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: AppColors.bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.rMd)),
      ),
      textTheme: base.textTheme.copyWith(
        bodyLarge: const TextStyle(color: AppColors.textPrimary, fontSize: 14.0),
        bodyMedium: const TextStyle(color: AppColors.textSecondary, fontSize: 13.0),
        titleLarge: const TextStyle(color: AppColors.textPrimary, fontSize: 24.0, fontWeight: FontWeight.w700),
        titleMedium: const TextStyle(color: AppColors.textPrimary, fontSize: 18.0, fontWeight: FontWeight.w500),
      ),
      dividerColor: AppColors.borderColor,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary600, foregroundColor: AppColors.textPrimary)),
    );

    // Apply font family using textTheme.apply to avoid using an unsupported copyWith param
    return theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'Inter'),
      primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Inter'),
    );
  }
}
