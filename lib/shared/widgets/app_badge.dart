import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

enum AppBadgeVariant { success, warning, danger, info, primary, secondary }

/// Badge sémantique EduPro — reproduction exacte de components.css
class AppBadge extends StatelessWidget {
  final String label;
  final AppBadgeVariant variant;
  final IconData? icon;

  const AppBadge({
    super.key,
    required this.label,
    this.variant = AppBadgeVariant.primary,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bgColor;
    Color textColor;

    switch (variant) {
      case AppBadgeVariant.success:
        bgColor = isDark ? const Color(0x2610B981) : AppColors.success50;
        textColor = isDark ? const Color(0xFF34D399) : AppColors.success700;
        break;
      case AppBadgeVariant.warning:
        bgColor = isDark ? const Color(0x26F59E0B) : AppColors.warning50;
        textColor = isDark ? const Color(0xFFFBBF24) : AppColors.warning700;
        break;
      case AppBadgeVariant.danger:
        bgColor = isDark ? const Color(0x26EF4444) : AppColors.danger50;
        textColor = isDark ? const Color(0xFFF87171) : AppColors.danger700;
        break;
      case AppBadgeVariant.info:
        bgColor = isDark ? const Color(0x263B82F6) : AppColors.info50;
        textColor = isDark ? const Color(0xFF60A5FA) : AppColors.info700;
        break;
      case AppBadgeVariant.primary:
        bgColor = isDark ? const Color(0x266366F1) : AppColors.primary50;
        textColor = isDark ? const Color(0xFFA5B4FC) : AppColors.primary700;
        break;
      case AppBadgeVariant.secondary:
        bgColor = isDark ? const Color(0x3364748B) : AppColors.gray100;
        textColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2 + 2,
        vertical: AppSpacing.s1 - 1,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTypography.badgeText(color: textColor),
          ),
        ],
      ),
    );
  }
}
