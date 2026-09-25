import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_typography.dart';

/// Fenêtre Modale EduPro — Reproduction exacte de components.css (.modal) avec adaptation mobile
class AppModal extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? footer;
  final double maxWidth;

  const AppModal({
    super.key,
    required this.title,
    required this.body,
    this.footer,
    this.maxWidth = 720,
  });

  /// Méthode statique pour afficher la modale avec sécurité clavier et responsive
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget body,
    Widget? footer,
    double maxWidth = 720,
  }) {
    return showDialog<T>(
      context: context,
      barrierColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkModalOverlay
          : AppColors.lightModalOverlay,
      builder: (context) => AppModal(
        title: title,
        body: body,
        footer: footer,
        maxWidth: maxWidth,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;
    final modalFooter = footer is Row &&
            !(footer! as Row)
                .children
                .any((child) => child is Expanded || child is Flexible)
        ? Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.s2,
            runSpacing: AppSpacing.s2,
            children: (footer! as Row).children,
          )
        : footer;

    final horizontalSafety = screenWidth < 600 ? AppSpacing.s4 : AppSpacing.s8;
    final effectiveMaxWidth =
        maxWidth.clamp(0, screenWidth - horizontalSafety * 2).toDouble();

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: viewInsetsBottom),
      duration: const Duration(milliseconds: 100),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: screenWidth < 600 ? AppSpacing.s2 : AppSpacing.s4,
          vertical: AppSpacing.s4,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: effectiveMaxWidth,
            maxHeight: screenHeight * (screenWidth < 600 ? 0.92 : 0.88),
          ),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBgCard : AppColors.lightBgCard,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(
              color: isDark
                  ? AppColors.darkBorderColor
                  : AppColors.lightBorderColor,
              width: .8,
            ),
            boxShadow: isDark ? AppShadows.darkLg : AppShadows.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Modale
              Padding(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: AppTypography.heading3(
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                      hoverColor: isDark
                          ? AppColors.darkBgHover
                          : AppColors.lightBgHover,
                    ),
                  ],
                ),
              ),
              Divider(
                color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
                height: 1,
              ),
              // Body défilable (wrapped in Material so form fields and dropdowns have a Material ancestor)
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(
                      screenWidth < 600 ? AppSpacing.s4 : AppSpacing.s6),
                  child: Material(
                    type: MaterialType.transparency,
                    child: body,
                  ),
                ),
              ),
              // Footer Modale (si fourni)
              if (modalFooter != null) ...[
                Divider(
                  color:
                      isDark ? AppColors.darkDivider : AppColors.lightDivider,
                  height: 1,
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        screenWidth < 600 ? AppSpacing.s4 : AppSpacing.s6,
                    vertical: AppSpacing.s4,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: modalFooter,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
