import 'package:flutter/material.dart';
import '../../core/constants/app_breakpoints.dart';
import '../../core/theme/app_spacing.dart';

/// Grille adaptative (1 col sur Mobile, 2 cols sur Tablette, 3-4 cols sur Desktop)
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.spacing = AppSpacing.s4,
    this.runSpacing = AppSpacing.s4,
    this.mobileColumns = 1,
    this.tabletColumns = 2,
    this.desktopColumns = 4,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int columns;
        if (constraints.maxWidth < AppBreakpoints.tabletMin) {
          columns = mobileColumns;
        } else if (constraints.maxWidth < AppBreakpoints.desktopMin) {
          columns = tabletColumns;
        } else {
          columns = desktopColumns;
        }

        if (columns == 1) {
          return Column(
            children: children
                .map((c) => Padding(
                      padding: EdgeInsets.only(bottom: runSpacing),
                      child: c,
                    ))
                .toList(),
          );
        }

        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children.map((c) {
            return SizedBox(
              width: itemWidth,
              child: c,
            );
          }).toList(),
        );
      },
    );
  }
}

/// Grille de formulaire fondée sur une largeur minimale de champ plutôt que
/// sur le type d'appareil. Elle passe automatiquement de plusieurs colonnes à
/// une seule sans overflow et conserve une largeur confortable par champ.
class ResponsiveFormGrid extends StatelessWidget {
  const ResponsiveFormGrid({
    super.key,
    required this.children,
    this.minFieldWidth = 260,
    this.maxColumns = 2,
    this.spacing = AppSpacing.s4,
    this.runSpacing = AppSpacing.s5,
  });

  final List<Widget> children;
  final double minFieldWidth;
  final int maxColumns;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth;
          final possible = ((available + spacing) / (minFieldWidth + spacing))
              .floor()
              .clamp(1, maxColumns);
          final fieldWidth = (available - spacing * (possible - 1)) / possible;
          return Wrap(
            spacing: spacing,
            runSpacing: runSpacing,
            children: children
                .map((child) => SizedBox(width: fieldWidth, child: child))
                .toList(),
          );
        },
      );
}

/// Rend un tableau aussi large que sa zone de travail lorsque ses colonnes sont
/// courtes, tout en conservant le défilement horizontal si elles la dépassent.
class ResponsiveDataTable extends StatelessWidget {
  const ResponsiveDataTable({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: child,
          ),
        ),
      );
}
