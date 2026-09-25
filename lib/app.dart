import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'data/services/store_service.dart';
import 'features/auth/login_page.dart';
import 'features/auth/required_password_change_page.dart';
import 'features/superadmin/superadmin_dashboard.dart';
import 'features/school/school_shell.dart';

/// Application principale MAYELE + — avec réactivité au Store et au Thème
class EduProApp extends StatelessWidget {
  const EduProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<StoreService>(
      builder: (context, store, child) {
        if (!store.isLoaded) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text(
                      'Chargement de MAYELE +...',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        Widget homePage;
        if (!store.isAuthenticated) {
          homePage = const LoginPage();
        } else if (store.currentUser!.mustChangePassword) {
          homePage = const RequiredPasswordChangePage();
        } else if (store.isSuperAdmin()) {
          homePage = const SuperAdminDashboard();
        } else {
          homePage = const SchoolShell();
        }

        return MaterialApp(
          title: 'MAYELE + — Gestion scolaire',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: store.themeMode,
          home: homePage,
        );
      },
    );
  }
}
