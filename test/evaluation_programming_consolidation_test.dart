import 'dart:convert';

import 'package:edupro_flutter_web/core/utils/date_utils.dart';
import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/grades/canonical_grades_page.dart';
import 'package:edupro_flutter_web/shared/widgets/app_date_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('les dates utilisateur sont uniformisées en JJ-MM-AAAA', () {
    expect(AppDateUtils.formatNumeric('2026-09-05'), '05-09-2026');
    expect(AppDateUtils.formatNumeric('05/09/2026'), '05-09-2026');
  });

  testWidgets('le champ date ouvre un calendrier sans saisie obligatoire',
      (tester) async {
    DateTime? selected = DateTime(2026, 9, 5);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AppDateField(
              label: 'Date de début',
              value: selected,
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );
    expect(find.text('05-09-2026'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    await tester.tap(find.text('05-09-2026'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'la programmation déduit les classes du niveau et exclut le niveau examen',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final payloads = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return _json({
          'accessToken': 'admin.jwt',
          'user': {
            'id': 'admin-1',
            'name': 'ADMIN Test',
            'email': 'admin@test.local',
            'role': 'admin',
            'schoolId': 'school-1',
            'status': 'active',
            'mustChangePassword': false,
          },
        });
      }
      if (request.url.path == '/api/v1/bootstrap') {
        return _json(_bootstrap);
      }
      if (request.url.path == '/api/v1/school/academic-years') {
        return _json([_academicYear]);
      }
      if (request.url.path == '/api/v1/school/classes') {
        return _json(_classes);
      }
      if (request.url.path == '/api/v1/school/academic-periods') {
        return _json([_period]);
      }
      if (request.url.path == '/api/v1/school/series' ||
          request.url.path == '/api/v1/school/evaluations') {
        return _json([]);
      }
      if (request.url.path == '/api/v1/school/evaluation-programs' &&
          request.method == 'POST') {
        payloads.add(Map<String, dynamic>.from(
            jsonDecode(request.body) as Map<String, dynamic>));
        return _json({'program': {}, 'evaluations': []}, 201);
      }
      return _json([]);
    });
    final store = StoreService(api: ApiClient(client: client));
    await store.init();
    expect(await store.login('admin@test.local', 'secret'), isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: store,
          child: const Scaffold(body: CanonicalGradesPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> openProgram() async {
      await tester.tap(find.text('Programmer une évaluation'));
      await tester.pumpAndSettle();
    }

    Future<void> choose(Key key, String label) async {
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    Future<void> create() async {
      await tester.tap(find.byKey(const Key('create-evaluation-program')));
      await tester.pumpAndSettle();
    }

    await openProgram();
    expect(find.text('Date prévue'), findsNothing);
    await choose(const Key('program-level-scope'), 'CP1');
    expect(find.textContaining('2 classe(s) concernée(s)'), findsOneWidget);
    await create();
    expect(payloads.last['classIds'], containsAll(['cp1-a', 'cp1-b']));
    expect((payloads.last['classIds'] as List).length, 2);
    expect(payloads.last.containsKey('date'), isFalse);
    expect(payloads.last.containsKey('maxScore'), isFalse);

    await openProgram();
    await choose(const Key('program-excluded-exam-level'), 'CM2');
    await create();
    expect(payloads.last['classIds'], containsAll(['cp1-a', 'cp1-b']));
    expect((payloads.last['classIds'] as List).length, 2);

    await openProgram();
    await choose(const Key('program-cycle'), 'Collège');
    await choose(const Key('program-excluded-exam-level'), '3e');
    await create();
    expect(payloads.last['classIds'], ['six-a']);

    await openProgram();
    await choose(const Key('program-cycle'), 'Lycée');
    await choose(const Key('program-excluded-exam-level'), 'Terminale');
    await create();
    expect(payloads.last['classIds'], ['seconde-a']);

    await openProgram();
    await choose(const Key('program-cycle'), 'Lycée');
    await choose(const Key('program-level-scope'), 'Terminale');
    await tester.tap(find.byKey(const Key('program-evaluation-kind')));
    await tester.pumpAndSettle();
    expect(find.text('BAC test'), findsOneWidget);
    expect(find.text('BAC blanc'), findsOneWidget);
    expect(find.text('Devoir départemental'), findsOneWidget);
    expect(find.text('BEPC test'), findsNothing);
    expect(find.text('CEPE test'), findsNothing);
    await tester.tap(find.text('Devoir 1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    await openProgram();
    await choose(const Key('program-level-scope'), 'CM2');
    await tester.tap(find.byKey(const Key('program-evaluation-kind')));
    await tester.pumpAndSettle();
    expect(find.text('CEPE test'), findsOneWidget);
    expect(find.text('CEPE blanc'), findsOneWidget);
    expect(find.text('Devoir départemental'), findsNothing);
    expect(find.text('BEPC test'), findsNothing);
    expect(find.text('BAC test'), findsNothing);
    await tester.tap(find.text('Composition').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    await openProgram();
    await choose(const Key('program-cycle'), 'Collège');
    await choose(const Key('program-level-scope'), '6e');
    await tester.tap(find.byKey(const Key('program-evaluation-kind')));
    await tester.pumpAndSettle();
    expect(find.text('Devoir départemental'), findsOneWidget);
    await tester.tap(find.text('Devoir départemental').last);
    await tester.pumpAndSettle();
    await create();
    expect(payloads.last['examCode'], 'devoir_departemental');
    expect(payloads.last['type'], 'exam');
    expect(payloads.last['classIds'], ['six-a']);

    await openProgram();
    await choose(const Key('program-cycle'), 'Collège');
    await choose(const Key('program-level-scope'), '3e');
    await tester.tap(find.byKey(const Key('program-evaluation-kind')));
    await tester.pumpAndSettle();
    expect(find.text('BEPC test'), findsOneWidget);
    expect(find.text('BEPC blanc'), findsOneWidget);
    expect(find.text('Devoir départemental'), findsOneWidget);
    expect(find.text('CEPE test'), findsNothing);
    expect(find.text('BAC test'), findsNothing);
    await tester.tap(find.text('Devoir 1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

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

const _period = {
  'id': 'period-t1',
  'schoolId': 'school-1',
  'academicYearId': 'year-1',
  'code': 'T1',
  'name': '1er trimestre',
  'periodType': 'trimester',
  'sortOrder': 1,
  'status': 'active',
};

const _cycles = [
  {
    'id': 'primary',
    'schoolId': 'school-1',
    'code': 'PRIMAIRE',
    'name': 'Primaire',
    'status': 'active',
    'sortOrder': 1
  },
  {
    'id': 'college',
    'schoolId': 'school-1',
    'code': 'COLLEGE',
    'name': 'Collège',
    'status': 'active',
    'sortOrder': 2
  },
  {
    'id': 'lycee',
    'schoolId': 'school-1',
    'code': 'LYCEE',
    'name': 'Lycée',
    'status': 'active',
    'sortOrder': 3
  },
];

const _levels = [
  {
    'id': 'cp1',
    'schoolId': 'school-1',
    'cycleId': 'primary',
    'code': 'CP1',
    'name': 'CP1',
    'status': 'active',
    'sortOrder': 1
  },
  {
    'id': 'cm2',
    'schoolId': 'school-1',
    'cycleId': 'primary',
    'code': 'CM2',
    'name': 'CM2',
    'status': 'active',
    'sortOrder': 6
  },
  {
    'id': 'six',
    'schoolId': 'school-1',
    'cycleId': 'college',
    'code': '6E',
    'name': '6e',
    'status': 'active',
    'sortOrder': 1
  },
  {
    'id': 'third',
    'schoolId': 'school-1',
    'cycleId': 'college',
    'code': '3E',
    'name': '3e',
    'status': 'active',
    'sortOrder': 4
  },
  {
    'id': 'seconde',
    'schoolId': 'school-1',
    'cycleId': 'lycee',
    'code': 'SECONDE',
    'name': 'Seconde',
    'status': 'active',
    'sortOrder': 1
  },
  {
    'id': 'terminale',
    'schoolId': 'school-1',
    'cycleId': 'lycee',
    'code': 'TERMINALE',
    'name': 'Terminale',
    'status': 'active',
    'sortOrder': 3
  },
];

const _classes = [
  {
    'id': 'cp1-a',
    'schoolId': 'school-1',
    'name': 'CP1 A',
    'academicYearId': 'year-1',
    'cycleId': 'primary',
    'structuredLevelId': 'cp1',
    'levelId': 'cp1'
  },
  {
    'id': 'cp1-b',
    'schoolId': 'school-1',
    'name': 'CP1 B',
    'academicYearId': 'year-1',
    'cycleId': 'primary',
    'structuredLevelId': 'cp1',
    'levelId': 'cp1'
  },
  {
    'id': 'cm2-a',
    'schoolId': 'school-1',
    'name': 'CM2 A',
    'academicYearId': 'year-1',
    'cycleId': 'primary',
    'structuredLevelId': 'cm2',
    'levelId': 'cm2'
  },
  {
    'id': 'six-a',
    'schoolId': 'school-1',
    'name': '6e A',
    'academicYearId': 'year-1',
    'cycleId': 'college',
    'structuredLevelId': 'six',
    'levelId': 'six'
  },
  {
    'id': 'third-a',
    'schoolId': 'school-1',
    'name': '3e A',
    'academicYearId': 'year-1',
    'cycleId': 'college',
    'structuredLevelId': 'third',
    'levelId': 'third'
  },
  {
    'id': 'seconde-a',
    'schoolId': 'school-1',
    'name': 'Seconde A',
    'academicYearId': 'year-1',
    'cycleId': 'lycee',
    'structuredLevelId': 'seconde',
    'levelId': 'seconde'
  },
  {
    'id': 'terminale-a',
    'schoolId': 'school-1',
    'name': 'Terminale A',
    'academicYearId': 'year-1',
    'cycleId': 'lycee',
    'structuredLevelId': 'terminale',
    'levelId': 'terminale'
  },
];

final _bootstrap = {
  'establishments': [
    {
      'id': 'school-1',
      'name': 'École test',
      'status': 'active',
      'enabledModules': ['grades'],
    }
  ],
  'academic-years': [_academicYear],
  'cycles': _cycles,
  'school-levels': _levels,
  'classes': _classes,
  for (final key in [
    'subscriptions',
    'students',
    'teachers',
    'subjects',
    'evaluations',
    'grades',
    'behavior-assessments',
    'affectations',
    'absences',
    'assignments',
    'notifications',
    'documents',
  ])
    key: <Object?>[],
};

http.Response _json(Object value, [int status = 200]) => http.Response(
      jsonEncode(value),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
