/// Espacements EduPro — reproduction exacte de variables.css
class AppSpacing {
  AppSpacing._();

  static const double s1  = 4.0;   // --space-1
  static const double s2  = 8.0;   // --space-2
  static const double s3  = 12.0;  // --space-3
  static const double s4  = 16.0;  // --space-4
  static const double s5  = 20.0;  // --space-5
  static const double s6  = 24.0;  // --space-6
  static const double s8  = 32.0;  // --space-8
  static const double s10 = 40.0;  // --space-10
  static const double s12 = 48.0;  // --space-12
  static const double s16 = 64.0;  // --space-16
}

/// Border radius EduPro — reproduction exacte de variables.css
class AppRadius {
  AppRadius._();

  static const double sm   = 6.0;    // --radius-sm
  static const double md   = 8.0;    // --radius-md
  static const double lg   = 12.0;   // --radius-lg
  static const double xl   = 16.0;   // --radius-xl
  static const double xxl  = 24.0;   // --radius-2xl
  static const double full = 9999.0; // --radius-full (pill)
}

/// Constantes de layout
class AppLayout {
  AppLayout._();

  static const double sidebarWidth          = 240.0;  // --sidebar-width
  static const double sidebarCollapsedWidth = 72.0;   // --sidebar-collapsed-width
  static const double headerHeight          = 64.0;   // --header-height

  /// Breakpoints responsive
  static const double mobileBreakpoint  = 768.0;
  static const double tabletBreakpoint  = 1024.0;
  static const double desktopBreakpoint = 1280.0;
}

/// Durées de transition
class AppDurations {
  AppDurations._();

  static const Duration fast   = Duration(milliseconds: 150);  // --transition-fast
  static const Duration base   = Duration(milliseconds: 200);  // --transition-base
  static const Duration slow   = Duration(milliseconds: 300);  // --transition-slow
  static const Duration slower = Duration(milliseconds: 500);  // --transition-slower
}

/// Z-index pour la gestion des couches
class AppZIndex {
  AppZIndex._();

  static const int dropdown     = 100;
  static const int sticky       = 200;
  static const int sidebar      = 300;
  static const int header       = 400;
  static const int modalOverlay = 500;
  static const int modal        = 600;
  static const int toast        = 700;
  static const int tooltip      = 800;
}
