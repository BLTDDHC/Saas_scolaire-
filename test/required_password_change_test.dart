import 'dart:convert';

import 'package:edupro_flutter_web/app.dart';
import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/auth/required_password_change_page.dart';
import 'package:edupro_flutter_web/features/school/school_shell.dart';
import 'package:edupro_flutter_web/features/superadmin/superadmin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const testEmail = 'forced.admin@edupro.local';
const newPassword = 'NouveauMotDePasseSolide2026!';
const validTestJwt = 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.test-signature';

Map<String, dynamic> user(bool required, {String role = 'admin'}) => {
      'id': '10000000-0000-0000-0000-000000000001',
      'name': 'Admin Obligatoire',
      'email': testEmail,
      'role': role,
      'roleName': role,
      'schoolId': role == 'superadmin' ? null : 'school_forced',
      'status': 'active',
      'passwordSet': true,
      'mustChangePassword': required,
    };

Map<String, dynamic> get emptyBootstrap => {
      for (final kind in [
        'establishments',
        'subscriptions',
        'academic-years',
        'students',
        'teachers',
        'classes',
        'subjects',
        'evaluations',
        'grades',
        'behavior-assessments',
        'affectations',
        'absences',
        'assignments',
        'documents',
        'finance-fees',
        'finance-registrations',
        'finance-fee-assignments',
        'finance-payments',
        'finance-receipts',
        'student-registrations',
        'announcements',
        'annual-bulletins',
        'annual-decisions',
        're-enrollment-requests'
      ])
        kind: [],
    };

class BackendState {
  bool mustChange = true;
  int changeCalls = 0;
  int meCalls = 0;
  int bootstrapCalls = 0;
  int? changeError;

  MockClient client() => MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response(
              jsonEncode(
                  {'accessToken': validTestJwt, 'user': user(mustChange)}),
              200);
        }
        if (request.url.path == '/api/v1/auth/change-password') {
          changeCalls++;
          if (changeError != null)
            return http.Response(
                jsonEncode({'detail': 'Erreur test $changeError'}),
                changeError!);
          final body = Map<String, dynamic>.from(jsonDecode(request.body));
          expect(body['new_password'], newPassword);
          expect(body['new_password_confirmation'], newPassword);
          expect(body.containsKey('current_password'), isFalse);
          mustChange = false;
          return http.Response(
              jsonEncode({
                'accessToken': validTestJwt,
                'user': user(false),
              }),
              200);
        }
        if (request.url.path == '/api/v1/auth/me') {
          meCalls++;
          return http.Response(jsonEncode(user(mustChange)), 200);
        }
        if (request.url.path == '/api/v1/bootstrap') {
          bootstrapCalls++;
          return http.Response(jsonEncode(emptyBootstrap), 200);
        }
        if (request.url.path == '/api/v1/school/academic-years' ||
            request.url.path == '/api/v1/school/classes') {
          return http.Response(jsonEncode(<Map<String, dynamic>>[]), 200);
        }
        return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
      });
}

class TeacherWithoutCurrentSlotBackend {
  bool mustChange = true;
  int workspaceCalls = 0;
  int attendanceCalls = 0;

  MockClient client() => MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response(
              jsonEncode({
                'accessToken': validTestJwt,
                'user': user(mustChange, role: 'teacher'),
              }),
              200);
        }
        if (request.url.path == '/api/v1/auth/change-password') {
          mustChange = false;
          return http.Response(
              jsonEncode({
                'accessToken': validTestJwt,
                'user': user(false, role: 'teacher'),
              }),
              200);
        }
        if (request.url.path == '/api/v1/auth/me') {
          return http.Response(
              jsonEncode(user(mustChange, role: 'teacher')), 200);
        }
        if (request.url.path == '/api/v1/bootstrap') {
          return http.Response(jsonEncode(emptyBootstrap), 200);
        }
        if (request.url.path == '/api/v1/school/teacher/workspace') {
          workspaceCalls++;
          return http.Response(
              jsonEncode({
                'establishment': {
                  'id': 'school_forced',
                  'name': 'Le cogito',
                  'type': 'Établissement scolaire',
                  'status': 'active',
                  'enabledModules': ['attendance'],
                },
                'academicYears': [
                  {
                    'id': 'year-1',
                    'name': '2026-2027',
                    'start': '2026-09-01',
                    'end': '2027-06-30',
                    'schoolId': 'school_forced',
                    'status': 'active',
                    'isActive': true,
                  }
                ],
                'classes': [
                  {
                    'id': 'class-1',
                    'name': 'Terminale C',
                    'schoolId': 'school_forced',
                    'academicYearId': 'year-1',
                  }
                ],
                'cycles': [],
                'schoolLevels': [],
                'subjects': [],
                'students': [],
                'affectations': [],
              }),
              200);
        }
        if (request.url.path == '/api/v1/school/attendance') {
          attendanceCalls++;
          return http.Response(
              jsonEncode({'detail': 'Le creneau de cours est obligatoire'}),
              422);
        }
        return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
      });
}

Future<StoreService> storeFor(BackendState backend, {bool clear = true}) async {
  if (clear) SharedPreferences.setMockInitialValues({});
  final store = StoreService(api: ApiClient(client: backend.client()));
  await store.init();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('forced admin sees only required password screen after login',
      (tester) async {
    final backend = BackendState();
    final store = await storeFor(backend);
    expect(await store.login(testEmail, 'initial-used-only-by-login'), isTrue);
    expect(backend.bootstrapCalls, 0);
    await tester.pumpWidget(
        ChangeNotifierProvider.value(value: store, child: const EduProApp()));
    await tester.pumpAndSettle();
    expect(find.byType(RequiredPasswordChangePage), findsOneWidget);
    expect(find.byType(SchoolShell), findsNothing);
  });

  testWidgets('different confirmation does not call backend', (tester) async {
    final backend = BackendState();
    final store = await storeFor(backend);
    await store.login(testEmail, 'initial-used-only-by-login');
    await tester.pumpWidget(
        ChangeNotifierProvider.value(value: store, child: const EduProApp()));
    await tester.enterText(find.byType(TextFormField).at(0), newPassword);
    await tester.enterText(find.byType(TextFormField).at(1), '${newPassword}x');
    await tester.tap(find.text('Changer le mot de passe'));
    await tester.pump();
    expect(
        find.text('Les mots de passe ne correspondent pas.'), findsOneWidget);
    expect(backend.changeCalls, 0);
    expect(find.byType(SchoolShell), findsNothing);
  });

  testWidgets('invalid short password stays on usable form', (tester) async {
    final backend = BackendState();
    final store = await storeFor(backend);
    await store.login(testEmail, 'initial-used-only-by-login');
    await tester.pumpWidget(
        ChangeNotifierProvider.value(value: store, child: const EduProApp()));
    await tester.enterText(find.byType(TextFormField).at(0), 'court');
    await tester.enterText(find.byType(TextFormField).at(1), 'court');
    await tester.tap(find.text('Changer le mot de passe'));
    await tester.pump();
    expect(
        find.text('Le mot de passe doit contenir entre 8 et 128 caractères.'),
        findsOneWidget);
    expect(backend.changeCalls, 0);
    expect(find.text('Changer le mot de passe'), findsOneWidget);
    expect(find.byType(SchoolShell), findsNothing);
  });

  testWidgets('successful change confirms with me then opens admin dashboard',
      (tester) async {
    final backend = BackendState();
    final store = await storeFor(backend);
    await store.login(testEmail, 'initial-used-only-by-login');
    await tester.pumpWidget(
        ChangeNotifierProvider.value(value: store, child: const EduProApp()));
    await tester.enterText(find.byType(TextFormField).at(0), newPassword);
    await tester.enterText(find.byType(TextFormField).at(1), newPassword);
    await tester.tap(find.text('Changer le mot de passe'));
    await tester.pumpAndSettle();
    expect(backend.changeCalls, 1);
    expect(backend.meCalls, 0);
    expect(store.currentUser!.mustChangePassword, isFalse);
    expect(find.byType(RequiredPasswordChangePage), findsNothing);
    expect(find.byType(SchoolShell), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    final saved = jsonDecode(preferences.getString('edupro_currentUser')!)
        as Map<String, dynamic>;
    expect(saved['mustChangePassword'], isFalse);
    expect(saved.containsKey('password'), isFalse);
    expect(saved.containsKey('passwordHash'), isFalse);
  });

  test(
      'teacher changes the forced password without loading attendance before a course is selected',
      () async {
    SharedPreferences.setMockInitialValues({});
    final backend = TeacherWithoutCurrentSlotBackend();
    final store = StoreService(api: ApiClient(client: backend.client()));
    await store.init();

    expect(await store.login(testEmail, 'temporary-password'), isTrue);
    expect(store.currentUser!.mustChangePassword, isTrue);
    expect(backend.workspaceCalls, 0);
    expect(backend.attendanceCalls, 0);

    expect(await store.changeRequiredPassword(newPassword), isTrue);
    expect(store.currentUser!.mustChangePassword, isFalse);
    expect(backend.workspaceCalls, 1);
    expect(backend.attendanceCalls, 0);
  });

  for (final status in [400, 401, 403, 409, 422, 500]) {
    test('HTTP $status keeps forced session outside dashboard', () async {
      final backend = BackendState()..changeError = status;
      final store = await storeFor(backend);
      await store.login(testEmail, 'initial-used-only-by-login');
      expect(await store.changeRequiredPassword(newPassword), isFalse);
      expect(store.currentUser!.mustChangePassword, isTrue);
      expect(store.passwordChangeError, contains('$status'));
      expect(backend.bootstrapCalls, 0);
    });
  }

  testWidgets('restored session uses fresh me value', (tester) async {
    final backend = BackendState();
    final first = await storeFor(backend);
    await first.login(testEmail, 'initial-used-only-by-login');
    final restoredForced = await storeFor(backend, clear: false);
    expect(restoredForced.currentUser!.mustChangePassword, isTrue);
    expect(backend.bootstrapCalls, 0);
    expect(await restoredForced.changeRequiredPassword(newPassword), isTrue);
    final restoredConfigured = await storeFor(backend, clear: false);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: restoredConfigured, child: const EduProApp()));
    await tester.pumpAndSettle();
    expect(restoredConfigured.currentUser!.mustChangePassword, isFalse);
    expect(find.byType(SchoolShell), findsOneWidget);
  });

  testWidgets('configured admin and superadmin routing remain unchanged',
      (tester) async {
    final adminBackend = BackendState()..mustChange = false;
    final admin = await storeFor(adminBackend);
    await admin.login(testEmail, 'configured');
    await tester.pumpWidget(
        ChangeNotifierProvider.value(value: admin, child: const EduProApp()));
    await tester.pumpAndSettle();
    expect(find.byType(SchoolShell), findsOneWidget);

    final superBackend = BackendState()..mustChange = false;
    final superStore = await storeFor(superBackend);
    superStore.logout();
    final superClient = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login')
        return http.Response(
            jsonEncode({
              'accessToken': validTestJwt,
              'user': user(false, role: 'superadmin')
            }),
            200);
      if (request.url.path == '/api/v1/bootstrap')
        return http.Response(jsonEncode(emptyBootstrap), 200);
      if (request.url.path == '/api/v1/superadmin/dashboard')
        return http.Response(
            jsonEncode({
              'establishments': {
                'total': 0,
                'active': 0,
                'suspended': 0,
                'recent': []
              },
              'subscriptions': {
                'total': 0,
                'active': 0,
                'upcoming': 0,
                'overdue': 0,
                'expired': 0,
                'activeAmountTotal': 0
              },
              'users': {'total': 0, 'admins': 0}
            }),
            200);
      return http.Response('{}', 404);
    });
    final configuredSuper = StoreService(api: ApiClient(client: superClient));
    SharedPreferences.setMockInitialValues({});
    await configuredSuper.init();
    await configuredSuper.login('admin@edupro.com', 'configured');
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: configuredSuper, child: const EduProApp()));
    await tester.pumpAndSettle();
    expect(find.byType(SuperAdminDashboard), findsOneWidget);
  });
}
