import 'package:flutter/material.dart';
import '../constants/app_breakpoints.dart';

enum DeviceType { mobile, tablet, desktop, largeDesktop }

/// Utilitaires d'analyse du device et de l'écran pour EduPro
class ContextUtils {
  ContextUtils._();

  static DeviceType getDeviceType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < AppBreakpoints.tabletMin) return DeviceType.mobile;
    if (width < AppBreakpoints.desktopMin) return DeviceType.tablet;
    if (width < AppBreakpoints.largeDesktopMin) return DeviceType.desktop;
    return DeviceType.largeDesktop;
  }

  static bool isMobile(BuildContext context) => getDeviceType(context) == DeviceType.mobile;
  static bool isTablet(BuildContext context) => getDeviceType(context) == DeviceType.tablet;
  static bool isDesktop(BuildContext context) =>
      getDeviceType(context) == DeviceType.desktop || getDeviceType(context) == DeviceType.largeDesktop;

  /// Largeur de l'écran
  static double width(BuildContext context) => MediaQuery.of(context).size.width;

  /// Hauteur de l'écran
  static double height(BuildContext context) => MediaQuery.of(context).size.height;
}
