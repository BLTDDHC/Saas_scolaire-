import 'package:flutter/material.dart';
import '../../core/constants/app_breakpoints.dart';

/// Builder adaptatif selon la largeur disponible (Mobile / Tablette / Desktop)
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context) mobile;
  final Widget Function(BuildContext context)? tablet;
  final Widget Function(BuildContext context) desktop;

  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppBreakpoints.tabletMin) {
          return mobile(context);
        }
        if (constraints.maxWidth < AppBreakpoints.desktopMin && tablet != null) {
          return tablet!(context);
        }
        return desktop(context);
      },
    );
  }
}
