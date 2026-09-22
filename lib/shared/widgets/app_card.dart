import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Card EduPro — reproduction de components.css (.card)
class AppCard extends StatelessWidget {
  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? headerAction;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.headerAction,
    this.padding,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isHorizontalWorkspace = child is SingleChildScrollView &&
        (child as SingleChildScrollView).scrollDirection == Axis.horizontal;

    Widget effectiveChild = child;
    if (isHorizontalWorkspace) {
      final scrollView = child as SingleChildScrollView;
      effectiveChild = LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: scrollView.controller,
          physics: scrollView.physics,
          primary: scrollView.primary,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: scrollView.child ?? const SizedBox.shrink(),
          ),
        ),
      );
    }

    final cardContent = Container(
      width: isHorizontalWorkspace ? double.infinity : null,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBgCard : AppColors.lightBgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color:
              isDark ? AppColors.darkBorderColor : AppColors.lightBorderColor,
          width: 0.5,
        ),
        // Les cartes structurent l'information sans donner à chaque bloc une
        // profondeur décorative. L'état interactif reste porté par InkWell.
        boxShadow: const [],
      ),
      padding: padding ?? const EdgeInsets.all(AppSpacing.s4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              color: isDark
                                  ? AppColors.darkTextTertiary
                                  : AppColors.lightTextTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (headerAction != null) ...[
                    const SizedBox(width: AppSpacing.s2),
                    headerAction!,
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.s4),
              Divider(
                color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
                height: 1,
              ),
              const SizedBox(height: AppSpacing.s4),
            ],
            effectiveChild,
          ],
        ),
      ),
    );

    if (onTap != null) {
      return Semantics(
        button: true,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: cardContent,
          ),
        ),
      );
    }

    return cardContent;
  }
}
