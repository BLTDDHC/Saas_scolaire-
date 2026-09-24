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

Map<String, dynamic> _user() => {
      'id': 'parent-user',
      'name': 'Parent Test',
      'email': 'parent@test.invalid',
      'role': 'parent',
      'roleName': 'parent',
      'schoolId': 'school-1',
      'status': 'active',
      'mustChangePassword': false,
    };

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
      'cycles': const [],
      'schoolLevels': const [],
      'classes': const [],
      'students': const [],
      'registrations': const [],
    };

List<Map<String, dynamic>> _children() => [
      {
        'id': 'student-a',
        'fullName': 'Enfant A',
        'years': [
          {'id': 'year-1', 'name': '2026-2027', 'className': 'CP A'}
        ],
      },
      {
        'id': 'student-b',
        'fullName': 'Enfant B',
        'years': [
          {'id': 'year-1', 'name': '2026-2027', 'className': 'CE1 B'}
        ],
      },
    ];

Map<String, dynamic> _situation(String child) => {
      'registrationId': 'reg-$child',
      'studentId': child,
      'studentName': child == 'student-a' ? 'Enfant A' : 'Enfant B',
      'className': child == 'student-a' ? 'CP A' : 'CE1 B',
      'currentRegime': child == 'student-a' ? 'part_time' : 'full_time',
      'summary': {
        'expected': child == 'student-a' ? 30000 : 45000,
        'paid': child == 'student-a' ? 10000 : 45000,
        'remaining': child == 'student-a' ? 20000 : 0,
        'unpaidMonths': child == 'student-a' ? 2 : 0,
        'overdueMonths': child == 'student-a' ? 1 : 0,
      },
      'months': [
        {
          'month': '2026-10',
          'expected': child == 'student-a' ? 10000 : 15000,
          'paid': child == 'student-a' ? 0 : 15000,
          'remaining': child == 'student-a' ? 10000 : 0,
          'status': child == 'student-a' ? 'unpaid' : 'paid',
          'regime': child == 'student-a' ? 'part_time' : 'full_time',
        }
      ],
      'overdueMonths': child == 'student-a'
          ? [
              {
                'month': '2026-10',
                'expected': 10000,
                'paid': 0,
                'remaining': 10000,
                'status': 'unpaid',
                'regime': 'part_time',
              }
            ]
          : [],
      'advanceMonths': const [],
    };

void main() {
  testWidgets('parent finance reloads and isolates each selected child',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final requestedChildren = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return http.Response(
            jsonEncode({'accessToken': _jwt, 'user': _user()}), 200);
      }
      if (request.url.path == '/api/v1/bootstrap') {
        return http.Response(jsonEncode(<String, dynamic>{}), 200);
      }
      if (request.url.path == '/api/v1/school/parent/workspace') {
        return http.Response(jsonEncode(_workspace()), 200);
      }
      if (request.url.path == '/api/v1/school/my-children') {
        return http.Response(jsonEncode(_children()), 200);
      }
      if (request.url.path.startsWith(
          '/api/v1/school/finance/parent-situation/')) {
        final child = request.url.pathSegments.last;
        requestedChildren.add(child);
        return http.Response(jsonEncode(_situation(child)), 200);
      }
      return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
    });
    final store = StoreService(api: ApiClient(client: client));
    await store.init();
    expect(await store.login('parent@test.invalid', 'Temporary!9'), isTrue);

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: const MaterialApp(home: Scaffold(body: ParentFinancePage())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Enfant A'), findsWidgets);
    expect(find.text('Mi-temps'), findsWidgets);
    expect(find.text('20 000 FCFA'), findsWidgets);

    await tester.tap(find.widgetWithText(
        DropdownButtonFormField<String>, 'Enfant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enfant B').last);
    await tester.pumpAndSettle();

    expect(find.text('Plein temps'), findsWidgets);
    expect(find.text('20 000 FCFA'), findsNothing);
    expect(find.text('0 FCFA'), findsWidgets);
    expect(requestedChildren, ['student-a', 'student-b']);
    expect(tester.takeException(), isNull);
  });
}
