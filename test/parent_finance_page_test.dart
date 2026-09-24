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

const token = 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.signature';

Map<String, dynamic> situation(String id, String name, int remaining,
        {String? regime}) =>
    {
      'studentId': id,
      'studentName': name,
      'registrationId': 'registration-$id',
      'classId': 'class-$id',
      'className': id == 'student-a' ? 'CM2 A' : '3e B',
      'academicYearId': 'year-1',
      'regime': regime,
      'months': [
        {
          'month': '2026-10',
          'expected': remaining + 4000,
          'paid': 4000,
          'remaining': remaining,
          'status': remaining == 0 ? 'paid' : 'partial',
          'regime': regime,
        }
      ],
      'unpaidMonths': remaining == 0 ? [] : [{'month': '2026-10'}],
      'overdueMonths': remaining == 0 ? [] : [{'month': '2026-10'}],
      'advanceMonths': const [],
      'summary': {
        'expected': remaining + 4000,
        'paid': 4000,
        'remaining': remaining,
        'advanceMonthCount': 0,
      },
    };

void main() {
  testWidgets('parent finance reloads and isolates the selected child',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return http.Response(
            jsonEncode({
              'accessToken': token,
              'user': {
                'id': 'parent-user',
                'name': 'Parent Test',
                'email': 'parent@test.invalid',
                'role': 'parent',
                'roleName': 'parent',
                'schoolId': 'school-1',
                'status': 'active',
                'mustChangePassword': false,
              }
            }),
            200);
      }
      if (request.url.path == '/api/v1/bootstrap') {
        return http.Response('{}', 200);
      }
      if (request.url.path == '/api/v1/school/parent/workspace') {
        return http.Response(
            jsonEncode({
              'establishment': {
                'id': 'school-1',
                'name': 'École Parent',
                'type': 'École',
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
              'students': const [],
              'registrations': const [],
              'cycles': const [],
              'schoolLevels': const [],
              'classes': const [],
            }),
            200);
      }
      if (request.url.path == '/api/v1/school/my-children') {
        return http.Response(
            jsonEncode([
              {
                'id': 'student-a',
                'fullName': 'Alice Primaire',
                'years': [
                  {'id': 'year-1', 'name': '2026-2027', 'className': 'CM2 A'}
                ],
              },
              {
                'id': 'student-b',
                'fullName': 'Brice Collège',
                'years': [
                  {'id': 'year-1', 'name': '2026-2027', 'className': '3e B'}
                ],
              },
            ]),
            200);
      }
      if (request.url.path ==
          '/api/v1/school/finance/parent-situation/student-a') {
        return http.Response(
            jsonEncode(situation('student-a', 'Alice Primaire', 6000,
                regime: 'full_time')),
            200);
      }
      if (request.url.path ==
          '/api/v1/school/finance/parent-situation/student-b') {
        return http.Response(
            jsonEncode(situation('student-b', 'Brice Collège', 2000)),
            200);
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

    expect(find.text('Alice Primaire'), findsWidgets);
    expect(find.text('Régime actuel : Plein temps'), findsOneWidget);
    expect(find.text('6 000 FCFA'), findsWidgets);

    await tester.tap(find.byKey(const Key('parent-finance-child')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brice Collège').last);
    await tester.pumpAndSettle();

    expect(find.text('Brice Collège'), findsWidgets);
    expect(find.text('2 000 FCFA'), findsWidgets);
    expect(find.text('6 000 FCFA'), findsNothing);
    expect(find.textContaining('Régime actuel'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
