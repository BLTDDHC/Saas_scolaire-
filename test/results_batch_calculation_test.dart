import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/grades/canonical_grades_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('ADMIN calcule en une action toutes les classes prêtes',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    final calculatedClassIds = <String>{};
    final classes = [
      _schoolClass('class-a', 'Terminale A'),
      _schoolClass('class-b', 'Terminale B'),
    ];
    final bootstrap = {
      'establishments': [
        {
          'id': 'school-1',
          'name': 'École test',
          'status': 'active',
          'enabledModules': ['grades'],
        }
      ],
      'subscriptions': [],
      'academic-years': [_academicYear],
      'students': [],
      'teachers': [],
      'classes': classes,
      'subjects': [],
      'evaluations': [],
      'grades': [],
      'behavior-assessments': [],
      'affectations': [],
      'absences': [],
      'assignments': [],
      'notifications': [],
      'documents': [],
      'cycles': [
        {
          'id': 'cycle-lycee',
          'schoolId': 'school-1',
          'code': 'LYCEE',
          'name': 'Lycée',
          'status': 'active',
        }
      ],
      'school-levels': [
        {
          'id': 'level-terminale',
          'schoolId': 'school-1',
          'cycleId': 'cycle-lycee',
          'code': 'TERMINALE',
          'name': 'Terminale',
          'status': 'active',
        }
      ],
    };
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return _json({
          'accessToken': 'admin.jwt',
          'user': {
            'id': 'admin-1',
            'name': 'ADMIN Test',
            'email': 'admin@test.local',
            'role': 'admin',
            'roleName': 'admin',
            'schoolId': 'school-1',
            'status': 'active',
            'mustChangePassword': false,
          },
        });
      }
      if (request.url.path == '/api/v1/bootstrap') return _json(bootstrap);
      if (request.url.path == '/api/v1/auth/me') {
        return _json({
          'id': 'admin-1',
          'name': 'ADMIN Test',
          'email': 'admin@test.local',
          'role': 'admin',
          'roleName': 'admin',
          'schoolId': 'school-1',
          'status': 'active',
          'mustChangePassword': false,
        });
      }
      if (request.url.path == '/api/v1/school/academic-years') {
        return _json([_academicYear]);
      }
      if (request.url.path == '/api/v1/school/classes') {
        return _json(classes);
      }
      if (request.url.path == '/api/v1/school/academic-periods') {
        return _json([
          {
            'id': 'period-t1',
            'schoolId': 'school-1',
            'academicYearId': 'year-1',
            'code': 'T1',
            'name': '1er trimestre',
            'periodType': 'trimester',
            'sortOrder': 1,
            'status': 'active',
          }
        ]);
      }
      if (request.url.path == '/api/v1/school/evaluations') {
        return _json([
          _evaluation('evaluation-d1', 'Devoir 1', 'devoir', 'devoir_1'),
          _evaluation('evaluation-bac', 'BAC test', 'test', 'bac_test'),
        ]);
      }
      if (request.url.path == '/api/v1/school/submissions') {
        return _json({
          'expectedCount': 1,
          'receivedCount': 1,
          'missingCount': 0,
          'readyForCalculation': true,
          'submissions': [
            {
              'teacherId': 'teacher-1',
              'teacher': 'MBAN Parfait',
              'class': 'Terminale A',
              'subject': 'Mathématiques',
              'status': 'submitted',
              'elements': [
                {
                  'name': 'Devoir 1',
                  'status': 'submitted',
                  'submittedAt': '2026-09-02T09:00:00Z',
                },
                {
                  'name': 'Devoir 2',
                  'status': 'submitted',
                  'submittedAt': '2026-09-02T10:00:00Z',
                },
                {
                  'name': 'Composition',
                  'status': 'submitted',
                  'submittedAt': '2026-09-02T11:00:00Z',
                },
              ],
            },
          ],
        });
      }
      if (request.url.path == '/api/v1/school/results' &&
          request.method == 'GET') {
        final classId = request.url.queryParameters['class_id']!;
        return _json({
          'classId': classId,
          'periodId': 'period-t1',
          'readyForCalculation': true,
          'calculationStatus':
              calculatedClassIds.contains(classId) ? 'official' : 'ready',
          'students': [],
          'submissions': [],
        });
      }
      if (request.url.path == '/api/v1/school/results/calculate') {
        final classId = request.url.queryParameters['class_id']!;
        calculatedClassIds.add(classId);
        return _json({
          'classId': classId,
          'periodId': 'period-t1',
          'readyForCalculation': true,
          'calculationStatus': 'official',
          'students': [],
          'submissions': [],
        });
      }
      return _json([]);
    });
    final store = StoreService(api: ApiClient(client: client));
    await store.init();
    expect(await store.login('admin@test.local', 'test-password'), isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<StoreService>.value(
          value: store,
          child: const Scaffold(body: CanonicalGradesPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> choose(int index, String label) async {
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(index));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await choose(0, 'Lycée');
    await choose(1, 'Terminale');
    await choose(2, 'Terminale A');
    await tester.tap(find.byKey(const Key('result-event-filter')));
    await tester.pumpAndSettle();
    expect(find.text('BAC test'), findsOneWidget);
    expect(find.text('Devoir 1'), findsNothing);
    await tester.tap(find.text('Moyenne de la période').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Actualiser le suivi'));
    await tester.pumpAndSettle();

    expect(find.text('MBAN Parfait'), findsOneWidget);
    expect(find.text('Devoir 1, Devoir 2, Composition'), findsOneWidget);

    expect(
      find.text('Calculer toutes les classes prêtes (2)'),
      findsOneWidget,
    );
    await tester.tap(find.text('Calculer toutes les classes prêtes (2)'));
    await tester.pumpAndSettle();

    expect(calculatedClassIds, {'class-a', 'class-b'});
    expect(
      find.text('2 classes calculées. Les classements sont disponibles.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

const _academicYear = {
  'id': 'year-1',
  'schoolId': 'school-1',
  'name': '2026-2027',
  'startDate': '2026-09-01',
  'endDate': '2027-07-31',
  'status': 'active',
  'isActive': true,
};

Map<String, dynamic> _schoolClass(String id, String name) => {
      'id': id,
      'schoolId': 'school-1',
      'name': name,
      'academicYearId': 'year-1',
      'cycleId': 'cycle-lycee',
      'structuredLevelId': 'level-terminale',
      'levelId': 'level-terminale',
      'level': 'Terminale',
      'status': 'active',
    };

Map<String, dynamic> _evaluation(
        String id, String title, String type, String examCode) =>
    {
      'id': id,
      'schoolId': 'school-1',
      'classId': 'class-a',
      'subjectId': 'subject-math',
      'academicYearId': 'year-1',
      'periodId': 'period-t1',
      'title': title,
      'type': type,
      'examCode': examCode,
      'period': 'T1',
      'maxScore': 20,
      'status': 'submitted',
      'date': '2026-09-02',
    };

http.Response _json(Object value, [int status = 200]) => http.Response(
      jsonEncode(value),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
