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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'parent finance reloads the selected child and shows backend balances',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final requestedChildren = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return http.Response(
          jsonEncode({
            'accessToken': _jwt,
            'user': {
              'id': 'parent-1',
              'name': 'Parent Test',
              'email': 'parent@test.local',
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
        return http.Response(jsonEncode(<String, dynamic>{}), 200);
      }
      if (request.url.path == '/api/v1/school/parent/workspace') {
        return http.Response(
          jsonEncode({
            'establishment': {
              'id': 'school-1',
              'name': 'École Parent',
              'type': 'Établissement scolaire',
              'institutionType': 'school',
              'status': 'active',
              'enabledModules': ['finance', 'grades'],
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
            'cycles': <Map<String, dynamic>>[],
            'schoolLevels': <Map<String, dynamic>>[],
            'classes': <Map<String, dynamic>>[],
            'students': <Map<String, dynamic>>[],
            'registrations': <Map<String, dynamic>>[],
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/school/my-children') {
        return http.Response(
          jsonEncode([
            {
              'id': 'student-a',
              'fullName': 'Alpha Alice',
              'years': [
                {'id': 'year-1', 'name': '2026-2027', 'className': 'CM2 A'}
              ],
            },
            {
              'id': 'student-b',
              'fullName': 'Beta Bob',
              'years': [
                {'id': 'year-1', 'name': '2026-2027', 'className': 'CM2 B'}
              ],
            },
          ]),
          200,
        );
      }
      if (request.url.path
          .startsWith('/api/v1/school/finance/parent-situation/')) {
        final child = request.url.pathSegments.last;
        requestedChildren.add(child);
        final isA = child == 'student-a';
        return http.Response(
          jsonEncode({
            'studentId': child,
            'studentName': isA ? 'Alpha Alice' : 'Beta Bob',
            'className': isA ? 'CM2 A' : 'CM2 B',
            'academicYearId': 'year-1',
            'academicYearName': '2026-2027',
            'schoolRegime': isA ? 'full_time' : 'part_time',
            'regimeHistory': [
              {
                'schoolRegime': isA ? 'full_time' : 'part_time',
                'effectiveDate': '2026-09-01',
                'endDate': null,
              }
            ],
            'months': [
              {
                'month': '2026-10',
                'expected': isA ? 10000 : 6000,
                'paid': isA ? 4000 : 6000,
                'remaining': isA ? 6000 : 0,
                'status': isA ? 'partial' : 'paid',
                'displayStatus': isA ? 'partial' : 'paid',
                'schoolRegime': isA ? 'full_time' : 'part_time',
              }
            ],
            'summary': {
              'expected': isA ? 10000 : 6000,
              'paid': isA ? 4000 : 6000,
              'remaining': isA ? 6000 : 0,
              'credit': 0,
              'advanceMonths': 0,
              'overdueMonths': 0,
              'unpaidMonths': isA ? 1 : 0,
            },
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
    });

    final store = StoreService(api: ApiClient(client: client));
    await store.init();
    expect(await store.login('parent@test.local', 'Temporary!9'), isTrue);

    await tester.pumpWidget(
      ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const MaterialApp(home: Scaffold(body: ParentFinancePage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Régime actuel : Plein temps'), findsOneWidget);
    expect(find.text('Reste à payer'), findsOneWidget);
    expect(find.text('6 000 FCFA'), findsWidgets);
    expect(requestedChildren.last, 'student-a');

    await tester.tap(find.byKey(const Key('parent-finance-child')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta Bob').last);
    await tester.pumpAndSettle();

    expect(requestedChildren.last, 'student-b');
    expect(find.text('Régime actuel : Mi-temps'), findsOneWidget);
    expect(find.text('Régime actuel : Plein temps'), findsNothing);
    expect(find.text('0 FCFA'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
