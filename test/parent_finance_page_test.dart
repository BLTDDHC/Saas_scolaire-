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

const _jwt = 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.signature';

Map<String, dynamic> _workspace() => {
      'establishment': {
        'id': 'school-parent',
        'name': 'École Parent',
        'type': 'Établissement scolaire',
        'institutionType': 'school',
        'status': 'active',
        'enabledModules': ['students', 'grades', 'finance'],
      },
      'guardian': {
        'id': 'guardian-1',
        'schoolId': 'school-parent',
        'firstName': 'Parent',
        'lastName': 'Test',
        'status': 'active',
      },
      'academicYears': [
        {
          'id': 'year-1',
          'schoolId': 'school-parent',
          'name': '2026-2027',
          'start': '2026-09-01',
          'end': '2027-07-01',
          'status': 'active',
          'isActive': true,
        }
      ],
      'cycles': [
        {
          'id': 'cycle-primary',
          'schoolId': 'school-parent',
          'code': 'PRIMAIRE',
          'name': 'Primaire',
          'status': 'active',
        }
      ],
      'schoolLevels': [],
      'classes': [
        {
          'id': 'class-a',
          'schoolId': 'school-parent',
          'name': 'CM1 A',
          'academicYearId': 'year-1',
          'cycleId': 'cycle-primary',
          'status': 'active',
        },
        {
          'id': 'class-b',
          'schoolId': 'school-parent',
          'name': 'CM2 B',
          'academicYearId': 'year-1',
          'cycleId': 'cycle-primary',
          'status': 'active',
        }
      ],
      'students': [
        {
          'id': 'student-a',
          'schoolId': 'school-parent',
          'firstName': 'Alice',
          'lastName': 'Enfant',
          'classId': 'class-a',
          'class': 'CM1 A',
          'cycle': 'Primaire',
          'academicYearId': 'year-1',
          'status': 'active',
        },
        {
          'id': 'student-b',
          'schoolId': 'school-parent',
          'firstName': 'Bob',
          'lastName': 'Enfant',
          'classId': 'class-b',
          'class': 'CM2 B',
          'cycle': 'Primaire',
          'academicYearId': 'year-1',
          'status': 'active',
        }
      ],
      'registrations': [
        {
          'id': 'registration-a',
          'studentId': 'student-a',
          'schoolId': 'school-parent',
          'academicYearId': 'year-1',
          'classId': 'class-a',
          'className': 'CM1 A',
          'schoolRegime': 'full_time',
          'status': 'active',
        },
        {
          'id': 'registration-b',
          'studentId': 'student-b',
          'schoolId': 'school-parent',
          'academicYearId': 'year-1',
          'classId': 'class-b',
          'className': 'CM2 B',
          'schoolRegime': 'part_time',
          'status': 'active',
        }
      ],
    };

Map<String, dynamic> _finance(String studentId) {
  final alice = studentId == 'student-a';
  return {
    'studentId': studentId,
    'studentName': alice ? 'Enfant Alice' : 'Enfant Bob',
    'className': alice ? 'CM1 A' : 'CM2 B',
    'academicYearId': 'year-1',
    'academicYearName': '2026-2027',
    'cycleCode': 'PRIMAIRE',
    'schoolRegime': alice ? 'full_time' : 'part_time',
    'regimeHistory': [],
    'totalExpected': alice ? 30000 : 18000,
    'totalPaid': alice ? 10000 : 12000,
    'totalRemaining': alice ? 20000 : 6000,
    'advanceAmount': alice ? 0 : 6000,
    'advanceMonths': alice
        ? []
        : [
            {
              'month': '2026-12',
              'expected': 6000,
              'paid': 6000,
              'remaining': 0,
              'status': 'paid',
              'schoolRegime': 'part_time',
              'regimeLabel': 'Mi-temps',
              'overdue': false,
            }
          ],
    'unpaidMonths': [
      {
        'month': '2026-11',
        'expected': alice ? 10000 : 6000,
        'paid': 0,
        'remaining': alice ? 10000 : 6000,
        'status': 'unpaid',
        'schoolRegime': alice ? 'full_time' : 'part_time',
        'regimeLabel': alice ? 'Plein temps' : 'Mi-temps',
        'overdue': false,
      }
    ],
    'overdueMonths': alice
        ? [
            {
              'month': '2026-09',
              'expected': 10000,
              'paid': 0,
              'remaining': 10000,
              'status': 'unpaid',
              'schoolRegime': 'full_time',
              'regimeLabel': 'Plein temps',
              'overdue': true,
            }
          ]
        : [],
    'months': [
      {
        'month': '2026-09',
        'expected': alice ? 10000 : 6000,
        'paid': alice ? 0 : 6000,
        'remaining': alice ? 10000 : 0,
        'status': alice ? 'unpaid' : 'paid',
        'schoolRegime': alice ? 'full_time' : 'part_time',
        'regimeLabel': alice ? 'Plein temps' : 'Mi-temps',
        'overdue': alice,
      },
      {
        'month': '2026-10',
        'expected': alice ? 10000 : 6000,
        'paid': alice ? 10000 : 6000,
        'remaining': 0,
        'status': 'paid',
        'schoolRegime': alice ? 'full_time' : 'part_time',
        'regimeLabel': alice ? 'Plein temps' : 'Mi-temps',
        'overdue': false,
      },
      {
        'month': '2026-11',
        'expected': alice ? 10000 : 6000,
        'paid': 0,
        'remaining': alice ? 10000 : 6000,
        'status': 'unpaid',
        'schoolRegime': alice ? 'full_time' : 'part_time',
        'regimeLabel': alice ? 'Plein temps' : 'Mi-temps',
        'overdue': false,
      },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'parent finance reloads per child and stays readable on narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final user = {
      'id': 'parent-user',
      'name': 'Parent Test',
      'email': 'parent@example.invalid',
      'role': 'parent',
      'roleName': 'parent',
      'schoolId': 'school-parent',
      'status': 'active',
      'mustChangePassword': false,
    };
    final requestedStudents = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return http.Response(
            jsonEncode({'accessToken': _jwt, 'user': user}), 200);
      }
      if (request.url.path == '/api/v1/bootstrap') {
        return http.Response(jsonEncode(<String, dynamic>{}), 200);
      }
      if (request.url.path == '/api/v1/school/parent/workspace') {
        return http.Response(jsonEncode(_workspace()), 200);
      }
      if (request.url.path.startsWith(
          '/api/v1/school/finance/parent-situation/')) {
        final studentId = request.url.pathSegments.last;
        requestedStudents.add(studentId);
        expect(request.url.queryParameters['academic_year_id'], 'year-1');
        return http.Response(jsonEncode(_finance(studentId)), 200);
      }
      return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
    });
    final store = StoreService(api: ApiClient(client: client));
    await store.init();
    expect(await store.login('parent@example.invalid', 'Temporary!9'), isTrue);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(
          home: Scaffold(body: ParentFinancePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Enfant Alice'), findsOneWidget);
    expect(find.text('Régime actuel'), findsOneWidget);
    expect(find.text('Plein temps'), findsWidgets);
    expect(find.text('Reste à payer'), findsOneWidget);
    expect(find.text('20 000 FCFA'), findsWidgets);
    expect(find.text('En retard'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('parent-finance-child')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enfant Bob').last);
    await tester.pumpAndSettle();

    expect(find.text('Enfant Bob'), findsOneWidget);
    expect(find.text('Mi-temps'), findsWidgets);
    expect(find.text('6 000 FCFA'), findsWidgets);
    expect(find.text('20 000 FCFA'), findsNothing);
    expect(requestedStudents, containsAllInOrder(['student-a', 'student-b']));
    expect(tester.takeException(), isNull);
  });
}
