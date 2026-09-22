import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

enum AppButtonVariant { primary, secondary, ghost, danger, success }

enum AppButtonSize { small, medium, large }

/// Bouton réutilisable EduPro — reproduction exacte des styles components.css
class AppButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool isLoading;
  final bool fullWidth;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bgColor;
    Color textColor;
    BorderSide borderSide = BorderSide.none;

    switch (widget.variant) {
      case AppButtonVariant.primary:
        bgColor = _isHovered ? AppColors.primary700 : AppColors.primary600;
        textColor = Colors.white;
        break;
      case AppButtonVariant.secondary:
        bgColor = _isHovered
            ? (isDark ? AppColors.darkBgHover : AppColors.lightBgHover)
            : (isDark ? AppColors.darkBgCard : AppColors.lightBgCard);
        textColor =
            isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
        borderSide = BorderSide(
          color:
              isDark ? AppColors.darkBorderColor : AppColors.lightBorderColor,
        );
        break;
      case AppButtonVariant.ghost:
        bgColor = _isHovered
            ? (isDark ? AppColors.darkBgHover : AppColors.lightBgHover)
            : Colors.transparent;
        textColor =
            isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
        break;
      case AppButtonVariant.danger:
        bgColor = _isHovered ? AppColors.danger600 : AppColors.danger500;
        textColor = Colors.white;
        break;
      case AppButtonVariant.success:
        bgColor = _isHovered ? AppColors.success600 : AppColors.success500;
        textColor = Colors.white;
        break;
    }

    EdgeInsets padding;
    double fontSize;
    double iconSize;

    switch (widget.size) {
      case AppButtonSize.small:
        padding = const EdgeInsets.symmetric(
            horizontal: AppSpacing.s3, vertical: AppSpacing.s1);
        fontSize = AppTypography.xs;
        iconSize = 14;
        break;
      case AppButtonSize.medium:
        padding = const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4, vertical: AppSpacing.s2);
        fontSize = AppTypography.sm;
        iconSize = 16;
        break;
      case AppButtonSize.large:
        padding = const EdgeInsets.symmetric(
            horizontal: AppSpacing.s6, vertical: AppSpacing.s3);
        fontSize = AppTypography.base;
        iconSize = 18;
        break;
    }

    final child = AnimatedContainer(
      duration: AppDurations.fast,
      decoration: BoxDecoration(
        color:
            widget.onPressed == null ? bgColor.withValues(alpha: 0.5) : bgColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.fromBorderSide(borderSide),
      ),
      padding: padding,
      child: widget.isLoading
          ? SizedBox(
              width: iconSize,
              height: iconSize,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(textColor),
              ),
            )
          : Row(
              mainAxisSize:
                  widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: iconSize, color: textColor),
                  const SizedBox(width: AppSpacing.s2),
                ],
                if (widget.fullWidth)
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTypography.buttonText(color: textColor)
                          .copyWith(fontSize: fontSize),
                    ),
                  )
                else
                  Text(
                    widget.label,
                    style: AppTypography.buttonText(color: textColor)
                        .copyWith(fontSize: fontSize),
                  ),
              ],
            ),
    );

    final enabled = widget.onPressed != null && !widget.isLoading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            onHover: (value) => setState(() => _isHovered = value),
            onTap: enabled ? widget.onPressed : null,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: widget.fullWidth
                ? SizedBox(width: double.infinity, child: child)
                : child,
          ),
        ),
      ),
    );
  }
}
