import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/settings/pedagogical_coefficients_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('ADMIN configure un coefficient Lycée contextualisé',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    Map<String, dynamic>? savedSetting;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return _json({
          'accessToken': 'jwt-test',
          'user': {
            'id': 'user-admin',
            'name': 'Admin Test',
            'email': 'admin@test.local',
            'role': 'admin',
            'schoolId': 'school-1',
            'status': 'active',
            'mustChangePassword': false,
          }
        });
      }
      if (request.url.path == '/api/v1/bootstrap') {
        return _json({
          'establishments': [
            {
              'id': 'school-1',
              'name': 'École Test',
              'status': 'active',
              'enabledModules': ['subjects', 'grades', 'classes'],
            }
          ],
          'academic-years': <Object?>[],
          'cycles': [
            {
              'id': 'cycle-primary',
              'schoolId': 'school-1',
              'code': 'PRIMAIRE',
              'name': 'Primaire',
              'status': 'active',
            },
            {
              'id': 'cycle-lycee',
              'schoolId': 'school-1',
              'code': 'LYCEE',
              'name': 'Lycée',
              'status': 'active',
            },
          ],
          'school-levels': [
            {
              'id': 'level-cm2',
              'schoolId': 'school-1',
              'cycleId': 'cycle-primary',
              'cycle': 'Primaire',
              'code': 'CM2',
              'name': 'CM2',
              'status': 'active',
            },
            {
              'id': 'level-terminale',
              'schoolId': 'school-1',
              'cycleId': 'cycle-lycee',
              'cycle': 'Lycée',
              'code': 'TERMINALE',
              'name': 'Terminale',
              'status': 'active',
            },
          ],
          'subjects': [_subject()],
          for (final key in [
            'subscriptions',
            'students',
            'teachers',
            'classes',
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
            key: <Object?>[],
        });
      }
      if (request.url.path == '/api/v1/school/academic-years') {
        return _json([
          {
            'id': 'year-1',
            'schoolId': 'school-1',
            'name': '2026-2027',
            'startDate': '2026-10-01',
            'endDate': '2027-06-30',
            'status': 'active',
            'isActive': true,
          }
        ]);
      }
      if (request.url.path == '/api/v1/school/classes') return _json([]);
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/school/subjects') {
        return _json([_subject()]);
      }
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/school/series') {
        return _json([
          {
            'id': 'series-d',
            'schoolId': 'school-1',
            'cycleId': 'cycle-lycee',
            'code': 'D',
            'name': 'D',
          }
        ]);
      }
      if (request.method == 'PUT' &&
          request.url.path ==
              '/api/v1/school/subjects/subject-math/level-setting') {
        savedSetting =
            Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        return _json(_subject(levelSettings: [
          {
            'id': 'setting-1',
            ...savedSetting!,
            'seriesId': savedSetting!.containsKey('seriesId')
                ? savedSetting!['seriesId']
                : null,
            'status': 'active',
          }
        ]));
      }
      return _json([]);
    });
    final store = StoreService(api: ApiClient(client: client));
    expect(await store.login('admin@test.local', 'secret'), isTrue);

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: const MaterialApp(
          home: Scaffold(body: PedagogicalCoefficientsCard())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Matières et coefficients'), findsOneWidget);
    expect(find.text('Terminale'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pedagogy-series')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('D').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('enabled-subject-math')));
    await tester.pumpAndSettle();

    final coefficient = find.byKey(
        const ValueKey('coefficient-subject-math-level-terminale-series-d'));
    await tester.enterText(coefficient, '5');
    await tester.tap(find.byKey(const Key('save-all-subject-settings')));
    await tester.pumpAndSettle();

    expect(savedSetting, {
      'academicYearId': 'year-1',
      'schoolLevelId': 'level-terminale',
      'seriesId': 'series-d',
      'coefficient': 5.0,
      'gradingScale': 20,
      'contributesToAverage': true,
      'enabled': true,
    });
    expect(find.byKey(const ValueKey('enabled-subject-math')), findsNothing);
    expect(find.text('1 matière(s) configurée(s)'), findsOneWidget);
    expect(find.text('1. Mathématiques'), findsOneWidget);
    expect(find.byKey(const Key('edit-subject-selection')), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit-subject-selection')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('enabled-subject-math')), findsOneWidget);
    expect(find.text('Enregistrer les modifications'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pedagogy-cycle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Primaire').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('enabled-subject-math')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('grading-scale-subject-math-level-cm2-null')),
      '10',
    );
    await tester.tap(find.byKey(const Key('save-all-subject-settings')));
    await tester.pumpAndSettle();

    expect(savedSetting, {
      'academicYearId': 'year-1',
      'schoolLevelId': 'level-cm2',
      'coefficient': null,
      'gradingScale': 10.0,
      'contributesToAverage': true,
      'enabled': true,
    });
    expect(find.text('1. Mathématiques — sur 10'), findsOneWidget);
  });
}

Map<String, dynamic> _subject(
        {List<Map<String, dynamic>> levelSettings = const []}) =>
    {
      'id': 'subject-math',
      'schoolId': 'school-1',
      'name': 'Mathématiques',
      'status': 'active',
      'levelSettings': levelSettings,
    };

http.Response _json(Object value, {int status = 200}) => http.Response(
      jsonEncode(value),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
