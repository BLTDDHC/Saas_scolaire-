import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/finance/parent_finance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _token = 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.signature';

Map<String, dynamic> _workspace() => {
      'establishment': {
        'id': 'school-1',
        'name': 'École Parent',
        'type': 'Établissement scolaire',
        'institutionType': 'school',
        'status': 'active',
        'enabledModules': ['students', 'grades', 'finance'],
      },
      'guardian': {
        'id': 'guardian-1',
        'schoolId': 'school-1',
        'firstName': 'Parent',
        'lastName': 'Test',
        'status': 'active',
      },
      'academicYears': [
        {
          'id': 'year-1',
          'schoolId': 'school-1',
          'name': '2026-2027',
          'start': '2026-09-01',
          'end': '2027-07-31',
          'status': 'active',
          'isActive': true,
        }
      ],
      'cycles': [],
      'schoolLevels': [],
      'classes': [],
      'students': [],
      'registrations': [],
    };

Map<String, dynamic> _finance(String studentId) => {
      'studentId': studentId,
      'studentName': studentId == 'child-a' ? 'Enfant Alpha' : 'Enfant Beta',
      'classId': studentId == 'child-a' ? 'class-a' : 'class-b',
      'className': studentId == 'child-a' ? 'CM2 A' : 'CM2 B',
      'academicYearId': 'year-1',
      'currentRegime': studentId == 'child-a' ? 'full_time' : 'part_time',
      'summary': {
        'expected': studentId == 'child-a' ? 20000 : 14000,
        'paid': studentId == 'child-a' ? 10000 : 7000,
        'remaining': studentId == 'child-a' ? 10000 : 7000,
        'credit': 0,
        'unpaidMonths': 1,
        'overdueMonths': 1,
        'advanceMonths': 0,
      },
      'months': [
        {
          'month': '2026-10',
          'expected': studentId == 'child-a' ? 10000 : 7000,
          'paid': studentId == 'child-a' ? 10000 : 7000,
          'remaining': 0,
          'status': 'paid',
          'schoolRegime': studentId == 'child-a' ? 'full_time' : 'part_time',
          'isOverdue': false,
        },
        {
          'month': '2026-11',
          'expected': studentId == 'child-a' ? 10000 : 7000,
          'paid': 0,
          'remaining': studentId == 'child-a' ? 10000 : 7000,
          'status': 'unpaid',
          'schoolRegime': studentId == 'child-a' ? 'full_time' : 'part_time',
          'isOverdue': true,
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('parent finance reloads and isolates each selected child',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final requestedChildren = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return http.Response(
          jsonEncode({
            'accessToken': _token,
            'user': {
              'id': 'parent-user',
              'name': 'Parent Test',
              'email': 'parent@test.invalid',
              'role': 'parent',
              'roleName': 'parent',
              'schoolId': 'school-1',
              'status': 'active',
              'mustChangePassword': false,
            },
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/bootstrap') {
        return http.Response('{}', 200);
      }
      if (request.url.path == '/api/v1/school/parent/workspace') {
        return http.Response(jsonEncode(_workspace()), 200);
      }
      if (request.url.path == '/api/v1/school/my-children') {
        return http.Response(
          jsonEncode([
            {
              'id': 'child-a',
              'fullName': 'Alpha Enfant',
              'years': [
                {'id': 'year-1', 'name': '2026-2027', 'className': 'CM2 A'}
              ],
            },
            {
              'id': 'child-b',
              'fullName': 'Beta Enfant',
              'years': [
                {'id': 'year-1', 'name': '2026-2027', 'className': 'CM2 B'}
              ],
            },
          ]),
          200,
        );
      }
      if (request.url.path.contains(
          '/api/v1/school/finance/parent/children/')) {
        final parts = request.url.path.split('/');
        final studentId = parts[parts.indexOf('children') + 1];
        requestedChildren.add(studentId);
        return http.Response(jsonEncode(_finance(studentId)), 200);
      }
      return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
    });

    final store = StoreService(api: ApiClient(client: client));
    await store.init();
    expect(await store.login('parent@test.invalid', 'Temporary!9'), isTrue);

    await tester.pumpWidget(
      ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const MaterialApp(
          home: Scaffold(body: ParentFinancePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Enfant Alpha'), findsOneWidget);
    expect(find.text('Régime actuel : Plein temps'), findsOneWidget);
    expect(find.text('10 000 FCFA'), findsWidgets);
    expect(requestedChildren, contains('child-a'));

    await tester.tap(find.byKey(const Key('parent-finance-child')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta Enfant').last);
    await tester.pumpAndSettle();

    expect(find.text('Enfant Alpha'), findsNothing);
    expect(find.text('Enfant Beta'), findsOneWidget);
    expect(find.text('Régime actuel : Mi-temps'), findsOneWidget);
    expect(find.text('7 000 FCFA'), findsWidgets);
    expect(requestedChildren.last, 'child-b');
    expect(tester.takeException(), isNull);
  });

  testWidgets('parent finance remains readable on a narrow viewport',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return http.Response(
          jsonEncode({
            'accessToken': _token,
            'user': {
              'id': 'parent-user',
              'name': 'Parent Test',
              'email': 'parent@test.invalid',
              'role': 'parent',
              'roleName': 'parent',
              'schoolId': 'school-1',
              'status': 'active',
              'mustChangePassword': false,
            },
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/bootstrap') {
        return http.Response('{}', 200);
      }
      if (request.url.path == '/api/v1/school/parent/workspace') {
        return http.Response(jsonEncode(_workspace()), 200);
      }
      if (request.url.path == '/api/v1/school/my-children') {
        return http.Response(
          jsonEncode([
            {
              'id': 'child-a',
              'fullName': 'Alpha Enfant',
              'years': [
                {'id': 'year-1', 'name': '2026-2027', 'className': 'CM2 A'}
              ],
            },
          ]),
          200,
        );
      }
      if (request.url.path.contains(
          '/api/v1/school/finance/parent/children/')) {
        return http.Response(jsonEncode(_finance('child-a')), 200);
      }
      return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
    });
    final store = StoreService(api: ApiClient(client: client));
    await store.init();
    expect(await store.login('parent@test.invalid', 'Temporary!9'), isTrue);

    await tester.pumpWidget(
      ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const MaterialApp(
          home: Scaffold(body: ParentFinancePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Échéances mensuelles'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
