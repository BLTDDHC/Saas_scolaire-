import 'dart:async';
import 'dart:convert';

import 'package:edupro_flutter_web/app.dart';
import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/repositories/school_repository.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/auth/login_page.dart';
import 'package:edupro_flutter_web/features/school/school_shell.dart';
import 'package:edupro_flutter_web/features/superadmin/superadmin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const email = 'login.test.20260822123429@edupro.local';
const validPassword = 'test-password-supplied-at-runtime';
const validTestJwt = 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.test-signature';

Map<String, dynamic> get user => {
      'id': '00000000-0000-0000-0000-000000000001',
      'name': 'Login Test Account',
      'email': email,
      'role': 'admin',
      'roleName': 'admin',
      'schoolId': 'school_003',
      'status': 'active',
      'passwordSet': true,
      'mustChangePassword': false,
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
        're-enrollment-requests',
      ])
        kind: <Map<String, dynamic>>[],
    };

List<Map<String, dynamic>> get adminAcademicYears => [
      {
        'id': 'year-active',
        'name': '2026-2027',
        'start': '2026-09-01',
        'end': '2027-07-31',
        'schoolId': 'school_003',
        'status': 'active',
        'isActive': true,
      },
      {
        'id': 'year-history',
        'name': '2025-2026',
        'start': '2025-09-01',
        'end': '2026-07-31',
        'schoolId': 'school_003',
        'status': 'inactive',
        'isActive': false,
      },
    ];

Map<String, dynamic> get adminBootstrap => {
      ...emptyBootstrap,
      'establishments': [
        {
          'id': 'school_003',
          'name': 'École PostgreSQL',
          'type': 'Primaire',
          'institutionType': 'primary',
          'status': 'active',
          'enabledModules': <String>[],
        }
      ],
    };

MockClient backendClient() => MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        final body = Map<String, dynamic>.from(jsonDecode(request.body));
        if (body['identifier'] != email || body['password'] != validPassword) {
          return http.Response(
              jsonEncode({'detail': 'Identifiants invalides'}), 401);
        }
        return http.Response(
            jsonEncode({'accessToken': validTestJwt, 'user': user}), 200);
      }
      if (request.url.path == '/api/v1/bootstrap' &&
          request.headers['authorization'] == 'Bearer $validTestJwt') {
        return http.Response(jsonEncode(adminBootstrap), 200);
      }
      if (request.url.path == '/api/v1/admin/establishment') {
        return http.Response(
            jsonEncode({
              'id': 'school_003',
              'name': 'École PostgreSQL',
              'type': 'Établissement scolaire',
              'institutionType': 'school',
              'status': 'active',
              'enabledModules': ['teachers'],
            }),
            200);
      }
      if (request.url.path == '/api/v1/school/academic-years') {
        return http.Response(jsonEncode(adminAcademicYears), 200);
      }
      if (request.url.path == '/api/v1/school/classes') {
        return http.Response(jsonEncode(<Map<String, dynamic>>[]), 200);
      }
      if (request.url.path == '/api/v1/school/teachers') {
        return http.Response(
            jsonEncode([
              {
                'id': 'teacher-1',
                'schoolId': 'school_003',
                'firstName': 'Aline',
                'lastName': 'Mabiala',
                'employeeNumber': 'ENS-2026-001',
                'status': 'active',
              }
            ]),
            200);
      }
      if (request.url.path == '/api/v1/school/organization-summary') {
        return http.Response(
            jsonEncode({
              'activeAcademicYear': adminAcademicYears.first,
              'selectedAcademicYear': adminAcademicYears.first,
              'activeCycleCount': 0,
              'classCount': 0,
              'studentCount': 0,
              'teacherCount': 0,
              'attendanceRate': null,
              'overallAverage': null,
            }),
            200);
      }
      if (request.url.path == '/api/v1/auth/me' &&
          request.headers['authorization'] == 'Bearer $validTestJwt') {
        return http.Response(jsonEncode(user), 200);
      }
      return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
    });

MockClient superAdminClient() => MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return http.Response(
            jsonEncode({
              'accessToken': validTestJwt,
              'user': {
                ...user,
                'email': 'adminm@gmail.com',
                'name': 'Super Admin',
                'role': 'superadmin',
                'roleName': 'superadmin',
                'schoolId': null,
              }
            }),
            200);
      }
      if (request.url.path == '/api/v1/bootstrap')
        return http.Response(jsonEncode(emptyBootstrap), 200);
      if (request.url.path == '/api/v1/superadmin/dashboard') {
        return http.Response(
            jsonEncode({
              'establishments': {
                'total': 4,
                'active': 4,
                'suspended': 0,
                'recent': []
              },
              'subscriptions': {
                'total': 3,
                'active': 3,
                'upcoming': 0,
                'overdue': 0,
                'expired': 0,
                'activeAmountTotal': 25000
              },
              'users': {'total': 8, 'admins': 5},
            }),
            200);
      }
      if (request.url.path == '/api/v1/superadmin/establishments')
        return http.Response('[]', 200);
      return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
    });

MockClient behaviorEnabledLoginClient() => MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return http.Response(
            jsonEncode({'accessToken': validTestJwt, 'user': user}), 200);
      }
      if (request.url.path == '/api/v1/bootstrap') {
        return http.Response(jsonEncode(adminBootstrap), 200);
      }
      if (request.url.path == '/api/v1/admin/establishment') {
        return http.Response(
            jsonEncode({
              'id': 'school_003',
              'name': 'École PostgreSQL',
              'institutionType': 'school',
              'status': 'active',
              'enabledModules': ['behavior'],
            }),
            200);
      }
      if (request.url.path == '/api/v1/school/academic-years') {
        return http.Response(jsonEncode(adminAcademicYears), 200);
      }
      if (request.url.path == '/api/v1/school/classes') {
        return http.Response('[]', 200);
      }
      if (request.url.path == '/api/v1/school/behavior') {
        return http.Response(
            jsonEncode({'detail': 'Sélectionnez une classe et un trimestre'}),
            422);
      }
      return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
    });

MockClient authenticatedButBootstrapFailsClient() =>
    MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return http.Response(
            jsonEncode({'accessToken': validTestJwt, 'user': user}), 200);
      }
      if (request.url.path == '/api/v1/bootstrap') {
        return http.Response(
            jsonEncode({'detail': 'Service temporairement indisponible'}), 503);
      }
      if (request.url.path == '/api/v1/auth/me') {
        return http.Response(jsonEncode(user), 200);
      }
      return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
    });

MockClient studentLoginClient() => MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        final body = Map<String, dynamic>.from(jsonDecode(request.body));
        if (body['identifier'] != 'mat-school-2026-0001' ||
            body['password'] != validPassword) {
          return http.Response(
              jsonEncode({'detail': 'Identifiant ou mot de passe incorrect.'}),
              401);
        }
        return http.Response(
            jsonEncode({
              'accessToken': validTestJwt,
              'user': {
                'id': 'student-user-1',
                'name': 'Mabiala Léa',
                'email': 'student-internal@accounts.edupro.local',
                'role': 'student',
                'roleName': 'student',
                'schoolId': 'school_003',
                'status': 'active',
                'passwordSet': true,
                'mustChangePassword': false,
              }
            }),
            200);
      }
      if (request.url.path == '/api/v1/bootstrap') {
        return http.Response(jsonEncode(emptyBootstrap), 200);
      }
      if (request.url.path == '/api/v1/school/student/workspace') {
        return http.Response(
            jsonEncode({
              'establishment': {
                'id': 'school_003',
                'name': 'École PostgreSQL',
                'institutionType': 'school',
                'type': 'Établissement scolaire',
                'status': 'active',
                'enabledModules': [
                  'grades',
                  'schedule',
                  'messages',
                  'documents'
                ],
              },
              'student': {
                'id': 'student-1',
                'userId': 'student-user-1',
                'firstName': 'Léa',
                'lastName': 'Mabiala',
                'matricule': 'MAT-SCHOOL-2026-0001',
                'classId': 'class-1',
                'class': 'CM2 A',
                'cycle': 'Primaire',
                'level': 'CM2',
                'schoolId': 'school_003',
                'academicYearId': 'year-active',
                'status': 'active',
              },
              'academicYears': adminAcademicYears.take(1).toList(),
              'classes': [
                {
                  'id': 'class-1',
                  'name': 'CM2 A',
                  'schoolId': 'school_003',
                  'academicYearId': 'year-active',
                  'cycleId': 'cycle-1',
                  'cycle': 'Primaire',
                  'level': 'CM2',
                  'status': 'active',
                }
              ],
              'cycles': [
                {
                  'id': 'cycle-1',
                  'code': 'PRIMAIRE',
                  'name': 'Primaire',
                  'schoolId': 'school_003',
                  'status': 'active',
                }
              ],
              'schoolLevels': <Map<String, dynamic>>[],
              'registrations': <Map<String, dynamic>>[],
            }),
            200);
      }
      if (request.url.path == '/api/v1/school/schedule') {
        return http.Response(
            jsonEncode([
              {
                'id': 'student-schedule-1',
                'academicYearId': 'year-active',
                'classId': 'class-1',
                'class': 'CM2 A',
                'subject': 'Mathématiques',
                'teacher': 'Aline Mabiala',
                'weekday': 1,
                'startTime': '08:00',
                'endTime': '09:00',
                'room': '12',
                'status': 'active',
              }
            ]),
            200);
      }
      return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
    });

Future<StoreService> freshStore(http.Client client) async {
  SharedPreferences.setMockInitialValues({});
  final store = StoreService(api: ApiClient(client: client));
  await store.init();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ApiClient handles 200 and 401', () async {
    final api = ApiClient(client: backendClient());
    final response =
        Map<String, dynamic>.from(await api.post('/api/v1/auth/login', {
      'identifier': email,
      'password': validPassword,
    }));
    expect(response['accessToken'], validTestJwt);
    expect(Map<String, dynamic>.from(response['user'] as Map)['role'], 'admin');
    await expectLater(
      api.post(
          '/api/v1/auth/login', {'identifier': email, 'password': 'wrong'}),
      throwsA(isA<ApiException>()
          .having((error) => error.statusCode, 'statusCode', 401)),
    );
  });

  test('SchoolRepository forwards login credentials and response', () async {
    final repository = SchoolRepository(ApiClient(client: backendClient()));
    final response = await repository.login(email, validPassword);
    expect(response['accessToken'], validTestJwt);
    expect(Map<String, dynamic>.from(response['user'] as Map)['role'], 'admin');
  });

  test('StoreService saves and restores a password-free session', () async {
    final store = await freshStore(backendClient());
    expect(await store.login(email, validPassword), isTrue);
    expect(store.isAuthenticated, isTrue);
    expect(store.currentUser?.email, email);

    final preferences = await SharedPreferences.getInstance();
    final savedUser = Map<String, dynamic>.from(
      jsonDecode(preferences.getString('edupro_currentUser')!),
    );
    expect(preferences.getString('edupro_accessToken'), isNotNull);
    expect(
        savedUser.keys
            .where((key) => key == 'password' || key == 'passwordHash'),
        isEmpty);

    final restored = StoreService(api: ApiClient(client: backendClient()));
    await restored.init();
    expect(restored.isAuthenticated, isTrue);
    expect(restored.currentUser?.email, email);
  });

  test('a valid login remains valid when Behavior has no selected context',
      () async {
    final store = await freshStore(behaviorEnabledLoginClient());
    expect(await store.login(email, validPassword), isTrue);
    expect(store.isAuthenticated, isTrue);
    expect(store.currentUser?.email, email);
  });

  test('a secondary bootstrap failure does not invalidate a valid login',
      () async {
    final store = await freshStore(authenticatedButBootstrapFailsClient());
    expect(await store.login(email, validPassword), isTrue);
    expect(store.isAuthenticated, isTrue);
    expect(store.currentUser?.email, email);
    expect(store.sessionWarning, isNotNull);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('edupro_accessToken'), isNotNull);
  });

  test('logout clears the local token and current user', () async {
    final store = await freshStore(backendClient());
    expect(await store.login(email, validPassword), isTrue);
    expect(store.getTeachers(), isNotEmpty);
    store.logout();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final preferences = await SharedPreferences.getInstance();
    expect(store.isAuthenticated, isFalse);
    expect(store.getStudents(), isEmpty);
    expect(store.getTeachers(), isEmpty);
    expect(store.getClasses(), isEmpty);
    expect(preferences.getString('edupro_accessToken'), isNull);
    expect(preferences.getString('edupro_currentUser'), isNull);
  });

  test(
      'la configuration PostgreSQL canonique charge la liste relationnelle des enseignants',
      () async {
    final store = await freshStore(backendClient());
    expect(await store.login(email, validPassword), isTrue);

    expect(store.getCurrentSchool()?.enabledModules, contains('teachers'));
    expect(store.getTeachers(), hasLength(1));
    expect(store.getTeachers().single.employeeNumber, 'ENS-2026-001');
  });

  testWidgets('LoginPage handles wrong password without creating a session',
      (tester) async {
    final store = await freshStore(backendClient());
    await tester.pumpWidget(
      ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), email);
    await tester.enterText(fields.at(1), 'wrong');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    expect(find.text('Identifiants invalides'), findsOneWidget);
    expect(store.isAuthenticated, isFalse);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('LoginPage handles an unknown email without creating a session',
      (tester) async {
    final store = await freshStore(backendClient());
    await tester.pumpWidget(
      ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'missing.login.test@edupro.local');
    await tester.enterText(fields.at(1), validPassword);
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    expect(find.text('Identifiants invalides'), findsOneWidget);
    expect(store.isAuthenticated, isFalse);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('valid LoginPage flow navigates an admin to SchoolShell',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await freshStore(backendClient());
    await tester.pumpWidget(
      ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const EduProApp(),
      ),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), email);
    await tester.enterText(fields.at(1), validPassword);
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    expect(store.isAuthenticated, isTrue);
    expect(store.currentUser?.role.value, 'admin');
    expect(find.byType(LoginPage), findsNothing);
    expect(find.byType(SchoolShell), findsOneWidget);
    final layoutErrors = <Object>[];
    Object? error;
    while ((error = tester.takeException()) != null) {
      layoutErrors.add(error!);
    }
    expect(layoutErrors, isEmpty);
  });

  testWidgets('superadmin dashboard and navigation render without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await freshStore(superAdminClient());
    expect(await store.login('adminm@gmail.com', 'runtime-secret'), isTrue);
    await tester.pumpWidget(ChangeNotifierProvider<StoreService>.value(
        value: store, child: const EduProApp()));
    await tester.pumpAndSettle();
    expect(find.byType(SuperAdminDashboard), findsOneWidget);
    expect(find.text('Vue d’ensemble'), findsOneWidget);
    expect(find.text('Administrateurs scolaires'), findsOneWidget);
    expect(find.text('Présences'), findsNothing);
    expect(find.text('Comportement'), findsNothing);
    await tester.tap(find.text('Établissements').first);
    await tester.pumpAndSettle();
    expect(find.text('Établissements partenaires'), findsOneWidget);
    await tester.tap(find.text('Abonnements').first);
    await tester.pumpAndSettle();
    expect(find.text('Gestion des Abonnements SaaS'), findsOneWidget);
    final errors = <Object>[];
    Object? error;
    while ((error = tester.takeException()) != null) errors.add(error!);
    expect(errors, isEmpty);
  });

  testWidgets('student logs in with matricule and reaches the linked workspace',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await freshStore(studentLoginClient());

    expect(await store.login('MAT-SCHOOL-2026-0001', validPassword), isTrue);
    expect(store.currentUser?.role, UserRole.student);
    expect(store.getStudents().single.userId, 'student-user-1');
    expect(store.getStudents().single.matricule, 'MAT-SCHOOL-2026-0001');

    await tester.pumpWidget(ChangeNotifierProvider<StoreService>.value(
        value: store, child: const EduProApp()));
    await tester.pumpAndSettle();
    expect(find.byType(SchoolShell), findsOneWidget);
    expect(find.text('Mon espace scolaire'), findsOneWidget);
    expect(find.text('CM2 A'), findsWidgets);
    expect(find.text('Mes documents'), findsNothing);
    await tester.tap(find.text('Emploi du temps'));
    await tester.pumpAndSettle();
    expect(find.text('Mon emploi du temps'), findsOneWidget);
    expect(find.text('Lundi'), findsOneWidget);
    expect(find.text('Mathématiques'), findsOneWidget);
    expect(find.text('CM2 A'), findsWidgets);
    expect(find.text('Aline Mabiala'), findsOneWidget);
    expect(find.text('Salle : 12'), findsOneWidget);
    expect(find.text('Ajouter un cours'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.byTooltip('Retirer'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('superadmin dashboard is responsive on tablet and mobile',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    final store = await freshStore(superAdminClient());
    expect(await store.login('adminm@gmail.com', 'runtime-secret'), isTrue);
    for (final size in const [Size(900, 900), Size(390, 844)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(ChangeNotifierProvider<StoreService>.value(
          value: store, child: const EduProApp()));
      await tester.pumpAndSettle();
      expect(find.byType(SuperAdminDashboard), findsOneWidget);
      final errors = <Object>[];
      Object? error;
      while ((error = tester.takeException()) != null) errors.add(error!);
      expect(errors, isEmpty, reason: 'Layout ${size.width}x${size.height}');
    }
  });

  testWidgets(
      'admin context has one year selector without duplicate on every viewport',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    final store = await freshStore(backendClient());
    expect(await store.login(email, validPassword), isTrue);

    for (final size in const [
      Size(1440, 1000),
      Size(900, 900),
      Size(390, 844)
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(ChangeNotifierProvider<StoreService>.value(
          value: store, child: const EduProApp()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('global-academic-year-selector')),
          findsOneWidget);
      expect(
          find.byKey(const Key('admin-academic-context-notice')), findsNothing);
      expect(find.text('École PostgreSQL'), findsOneWidget);
      expect(find.textContaining('Année sélectionnée'), findsNothing);
      expect(find.textContaining('Établissement :'), findsNothing);

      final errors = <Object>[];
      Object? error;
      while ((error = tester.takeException()) != null) {
        errors.add(error!);
      }
      expect(errors, isEmpty, reason: 'Layout ${size.width}x${size.height}');
    }
  });

  testWidgets('historical context is explicit and returns to the active year',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await freshStore(backendClient());
    expect(await store.login(email, validPassword), isTrue);
    store.setSelectedAcademicYearId('year-history');

    await tester.pumpWidget(ChangeNotifierProvider<StoreService>.value(
        value: store, child: const EduProApp()));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('global-academic-year-selector')), findsOneWidget);
    expect(
        find.byKey(const Key('admin-academic-context-notice')), findsOneWidget);
    expect(find.text('Consultation historique : 2025-2026'), findsOneWidget);
    expect(find.text('Revenir à 2026-2027'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('return-to-active-year')));
    await tester.pumpAndSettle();
    expect(store.getSelectedAcademicYearId(), 'year-active');
    expect(
        find.byKey(const Key('admin-academic-context-notice')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('network failure returns false without creating a session', () async {
    final failing = MockClient(
        (_) async => throw http.ClientException('backend unavailable'));
    final store = await freshStore(failing);
    final result = await store.login(email, validPassword);
    expect(result, isFalse);
    expect(store.isAuthenticated, isFalse);
  });

  testWidgets('LoginPage recovers from a network failure', (tester) async {
    final failing = MockClient(
        (_) async => throw http.ClientException('backend unavailable'));
    final store = await freshStore(failing);
    await tester.pumpWidget(
      ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), email);
    await tester.enterText(fields.at(1), validPassword);
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Serveur indisponible. Vérifiez la connexion puis réessayez.'),
        findsOneWidget);
    expect(store.isAuthenticated, isFalse);
    expect(find.text('Se connecter'), findsOneWidget);
  });

  test('a hanging HTTP request is observable', () async {
    final hanging = MockClient((_) => Completer<http.Response>().future);
    final api =
        ApiClient(client: hanging, timeout: const Duration(milliseconds: 100));
    await expectLater(
      api.post('/api/v1/auth/login',
          {'identifier': email, 'password': validPassword}),
      throwsA(isA<TimeoutException>()),
    );
  });
}
