import 'dart:convert';

import 'package:edupro_flutter_web/app.dart';
import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/behavior/behavior_page.dart';
import 'package:edupro_flutter_web/features/school/attendance/attendance_page.dart';
import 'package:edupro_flutter_web/features/school/grades/canonical_grades_page.dart';
import 'package:edupro_flutter_web/features/school/teachers/teachers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/legacy_store_test_harness.dart';

const _email = 'teacher.workspace@edupro.local';
const _password = 'runtime-only-password';
const _validTestJwt = 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.test-signature';

Map<String, dynamic> get _teacherUser => {
      'id': 'user-teacher-1',
      'name': 'Aline Mabiala',
      'email': _email,
      'role': 'teacher',
      'roleName': 'teacher',
      'schoolId': 'school_003',
      'status': 'active',
      'mustChangePassword': false,
    };

Map<String, dynamic> get _emptyBootstrap => {
      for (final key in [
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
        'notifications',
        'documents',
        'cycles',
        'school-levels',
      ])
        key: <Map<String, dynamic>>[],
    };

List<Map<String, dynamic>> get _teacherEvaluations => [
      {
        'id': 'evaluation-1',
        'schoolId': 'school_003',
        'title': 'Devoir 1',
        'type': 'devoir',
        'academicYearId': 'year-active',
        'periodId': 'period-t1',
        'classId': 'class-1',
        'subjectId': 'subject-1',
        'status': 'draft',
        'maxScore': 20,
        'createdBy': 'user-teacher-1',
        'createdAt': '2026-10-01T08:00:00Z',
      },
      {
        'id': 'evaluation-2',
        'schoolId': 'school_003',
        'title': 'Composition',
        'type': 'composition',
        'academicYearId': 'year-active',
        'periodId': 'period-t1',
        'classId': 'class-1',
        'subjectId': 'subject-1',
        'status': 'draft',
        'maxScore': 20,
        'createdBy': 'user-teacher-1',
        'createdAt': '2026-10-02T08:00:00Z',
      },
    ];

Map<String, dynamic> get _workspace => {
      'establishment': {
        'id': 'school_003',
        'name': 'École PostgreSQL',
        'type': 'Établissement scolaire',
        'institutionType': 'school',
        'status': 'active',
        'enabledModules':
            ['students', 'grades', 'attendance', 'behavior', 'schedule'],
      },
      'teacher': {
        'id': 'teacher-1',
        'userId': 'user-teacher-1',
        'schoolId': 'school_003',
        'firstName': 'Aline',
        'lastName': 'Mabiala',
        'employeeNumber': 'ENS-2026-001',
        'email': _email,
        'status': 'active',
      },
      'academicYears': [
        {
          'id': 'year-active',
          'schoolId': 'school_003',
          'name': '2026-2027',
          'start': '2026-09-01',
          'end': '2027-07-31',
          'status': 'active',
          'isActive': true,
        }
      ],
      'cycles': [
        {
          'id': 'cycle-college',
          'schoolId': 'school_003',
          'code': 'COLLEGE',
          'name': 'CollÃ¨ge',
          'status': 'active',
        }
      ],
      'schoolLevels': [
        {
          'id': 'level-3e',
          'schoolId': 'school_003',
          'cycleId': 'cycle-college',
          'cycle': 'CollÃ¨ge',
          'code': '3E',
          'name': '3e',
          'status': 'active',
        }
      ],
      'classes': [
        {
          'id': 'class-1',
          'schoolId': 'school_003',
          'name': '3e A',
          'academicYearId': 'year-active',
          'cycleId': 'cycle-college',
          'structuredLevelId': 'level-3e',
          'levelId': 'level-3e',
          'level': '3e',
          'status': 'active',
        }
      ],
      'subjects': [
        {
          'id': 'subject-1',
          'schoolId': 'school_003',
          'name': 'Mathématiques',
          'status': 'active',
        }
      ],
      'affectations': [
        {
          'id': 'affectation-1',
          'schoolId': 'school_003',
          'teacherId': 'teacher-1',
          'teacherName': 'Aline Mabiala',
          'classId': 'class-1',
          'className': '3e A',
          'subjectId': 'subject-1',
          'subject': 'Mathématiques',
          'academicYearId': 'year-active',
          'status': 'active',
        }
      ],
      'students': [
        {
          'id': 'student-1',
          'schoolId': 'school_003',
          'firstName': 'Chris',
          'lastName': 'Massamba',
          'classId': 'class-1',
          'class': '3e A',
          'level': '3e',
          'matricule': 'ECOLE-2026-001',
          'academicYearId': 'year-active',
          'status': 'active',
        }
      ],
    };

MockClient _teacherClient(
    {List<Map<String, dynamic>> initialBehavior = const [],
    Map<String, dynamic>? officialResults}) {
  final behaviorEvents = <Map<String, dynamic>>[...initialBehavior];
  String attendanceStatus = 'draft';
  List<Map<String, dynamic>> attendanceRecords = [];
  return MockClient((request) async {
    if (request.url.path == '/api/v1/auth/login') {
      final body = Map<String, dynamic>.from(jsonDecode(request.body));
      if (body['identifier'] != _email || body['password'] != _password) {
        return http.Response(
            jsonEncode({'detail': 'Identifiants invalides'}), 401);
      }
      return http.Response(
          jsonEncode({'accessToken': _validTestJwt, 'user': _teacherUser}),
          200);
    }
    if (request.url.path == '/api/v1/bootstrap') {
      return http.Response(jsonEncode(_emptyBootstrap), 200);
    }
    if (request.url.path == '/api/v1/auth/me') {
      return http.Response(jsonEncode(_teacherUser), 200);
    }
    if (request.url.path == '/api/v1/school/teacher/workspace') {
      return http.Response(jsonEncode(_workspace), 200);
    }
    if (request.url.path == '/api/v1/school/evaluations') {
      return http.Response(jsonEncode(_teacherEvaluations), 200);
    }
    if (request.url.path.startsWith('/api/v1/school/evaluations/') &&
        request.url.path.endsWith('/grades')) {
      return http.Response('[]', 200);
    }
    if (request.url.path == '/api/v1/school/academic-periods') {
      return http.Response(
          jsonEncode([
            {
              'id': 'period-t1',
              'schoolId': 'school_003',
              'academicYearId': 'year-active',
              'code': 'T1',
              'name': '1er trimestre',
              'periodType': 'trimester',
              'sortOrder': 1,
              'startDate': '2026-08-01',
              'endDate': '2026-10-31',
              'status': 'active',
            }
          ]),
          200);
    }
    if (request.url.path == '/api/v1/school/behavior' &&
        request.method == 'PUT') {
      final body = Map<String, dynamic>.from(jsonDecode(request.body));
      final entries = List<Map<String, dynamic>>.from((body['entries'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map)));
      behaviorEvents
        ..clear()
        ..addAll(entries.map((entry) => {
              'id': 'behavior-${entry['studentId']}',
              'studentId': entry['studentId'],
              'teacherId': 'teacher-1',
              'schoolId': 'school_003',
              'academicYearId': 'year-active',
              'classId': body['classId'],
              'periodId': body['periodId'],
              'period': '1er trimestre',
              'score': entry['stars'],
              'date': '2026-09-01',
              'comment': entry['comment'],
              'status': 'locked',
              'recordedBy': 'user-teacher-1',
            }));
      return http.Response(jsonEncode(behaviorEvents), 200);
    }
    if (request.url.path == '/api/v1/school/behavior') {
      return http.Response(jsonEncode(behaviorEvents), 200);
    }
    if (request.url.path == '/api/v1/school/attendance/statistics') {
      return http.Response(
          jsonEncode({
            'present': 0,
            'absent': 0,
            'justified': 0,
            'attendanceRate': 0,
          }),
          200);
    }
    if (request.url.path == '/api/v1/school/schedule') {
      return http.Response(
          jsonEncode([
            {
              'id': 'schedule-1',
              'schoolId': 'school_003',
              'academicYearId': 'year-active',
              'classId': 'class-1',
              'class': '3e A',
              'subjectId': 'subject-1',
              'subject': 'Mathématiques',
              'teacherId': 'teacher-1',
              'teacher': 'Aline Mabiala',
              'affectationId': 'affectation-1',
              'weekday': DateTime.now().weekday,
              'startTime': '00:00',
              'endTime': '23:59',
              'canTakeAttendance': true,
              'status': 'active',
            }
          ]),
          200);
    }
    if (request.url.path == '/api/v1/school/attendance/sheet') {
      return http.Response(
          jsonEncode({
            'sheetStatus': attendanceStatus,
            'students': [
              {'id': 'student-1', 'fullName': 'Élève du serveur'}
            ],
            'records': attendanceRecords,
          }),
          200);
    }
    if (request.url.path == '/api/v1/school/attendance' &&
        request.method == 'PUT') {
      if (attendanceStatus == 'locked')
        return http.Response(jsonEncode({'detail': 'Déjà envoyé'}), 409);
      final body = Map<String, dynamic>.from(jsonDecode(request.body));
      attendanceStatus = body['action'] == 'submit' ? 'locked' : 'draft';
      attendanceRecords = (body['entries'] as List)
          .map((entry) => <String, dynamic>{
                'id': 'attendance-${entry['studentId']}',
                'studentId': entry['studentId'],
                'classId': body['classId'],
                'scheduleId': body['scheduleId'],
                'teacherId': 'teacher-1',
                'subjectId': 'subject-1',
                'date': body['date'],
                'status': entry['status'],
                'sheetStatus': attendanceStatus,
              })
          .toList();
      return http.Response(jsonEncode(attendanceRecords), 200);
    }
    if (request.url.path == '/api/v1/school/attendance') {
      return http.Response('[]', 200);
    }
    if (request.url.path == '/api/v1/school/submissions') {
      return http.Response(
          jsonEncode({'readyForCalculation': officialResults != null}), 200);
    }
    if (request.url.path == '/api/v1/school/results' &&
        officialResults != null) {
      return http.Response(jsonEncode(officialResults), 200);
    }
    return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
  });
}

Future<StoreService> _store(http.Client client) async {
  SharedPreferences.setMockInitialValues({});
  final store = StoreService(api: ApiClient(client: client));
  await store.init();
  return store;
}

void main() {
  for (final author in ['teacher-1', 'teacher-2']) {
    testWidgets('comportement recharge uniquement le relevé de $author',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _store(_teacherClient(initialBehavior: [
        {
          'id': 'other-sheet',
          'studentId': 'student-1',
          'teacherId': author,
          'schoolId': 'school_003',
          'academicYearId': 'year-active',
          'classId': 'class-1',
          'periodId': 'period-1',
          'score': 5,
          'date': '2026-09-01',
          'status': 'locked',
        }
      ]));
      expect(await store.login(_email, _password), isTrue);
      await tester.pumpWidget(MaterialApp(
          home: ChangeNotifierProvider<StoreService>.value(
              value: store, child: const Scaffold(body: BehaviorPage()))));
      await tester.pumpAndSettle();
      for (final selection in [
        (0, 'Coll'),
        (1, '3e'),
        (2, '3e A'),
        (3, '1er trimestre')
      ]) {
        await tester.tap(
            find.byType(DropdownButtonFormField<String?>).at(selection.$1));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining(selection.$2).last);
        await tester.pumpAndSettle();
      }
      expect(find.text('Envoyé · verrouillé'),
          author == 'teacher-1' ? findsOneWidget : findsNothing);
      expect(find.text('À renseigner'),
          author == 'teacher-2' ? findsOneWidget : findsNothing);
    });
  }

  test('la moyenne officielle vient du serveur avec classe et trimestre',
      () async {
    final requests = <Uri>[];
    final fallback = _teacherClient();
    final store = await _store(MockClient((request) async {
      if (request.url.path == '/api/v1/school/behavior/results') {
        requests.add(request.url);
        return http.Response(
            jsonEncode({
              'calculationStatus': 'official',
              'students': [
                {
                  'studentId': 'student-1',
                  'average': 4.5,
                  'contributionCount': 2
                }
              ]
            }),
            200);
      }
      return http.Response.fromStream(await fallback.send(request));
    }));
    final result = await store.behaviorResultsRemote('class-1', 'period-2');
    expect(result['students'][0]['average'], 4.5);
    expect(requests.single.queryParameters,
        {'class_id': 'class-1', 'period_id': 'period-2'});
  });

  testWidgets('un enseignant consulte les résultats officiels de sa classe',
      (tester) async {
    final store = await _store(_teacherClient(officialResults: {
      'calculationStatus': 'official',
      'students': [
        {
          'studentId': 'student-1',
          'studentName': 'Massamba Chris',
          'lastName': 'Massamba',
          'firstName': 'Chris',
          'rank': 1,
          'average': 15.5
        }
      ],
    }));
    expect(await store.login(_email, _password), isTrue);
    await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
            value: store, child: const Scaffold(body: CanonicalGradesPage()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('3e A').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1er trimestre').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voir mes résultats'));
    await tester.pumpAndSettle();
    expect(find.text('Classement / ordre de mérite'), findsOneWidget);
    expect(find.text('Massamba'), findsOneWidget);
    expect(find.text('15.5'), findsOneWidget);
  });
  TestWidgetsFlutterBinding.ensureInitialized();

  test('le login enseignant charge uniquement son workspace relationnel',
      () async {
    final store = await _store(_teacherClient());
    expect(await store.login(_email, _password), isTrue);

    expect(store.currentUser?.role.value, 'teacher');
    expect(store.getTeachers().single.employeeNumber, 'ENS-2026-001');
    expect(store.getClasses().single.name, '3e A');
    expect(store.getSubjects().single.name, 'Mathématiques');
    expect(store.getAffectations().single.teacherId, 'teacher-1');
    expect(store.getSchoolCycles().single.code, 'COLLEGE');
    expect(store.getSchoolLevels().single.code, '3E');
    expect(store.getStudents().single.classId, 'class-1');

    final restored = StoreService(api: ApiClient(client: _teacherClient()));
    await restored.init();
    expect(restored.currentUser?.role.value, 'teacher');
    expect(restored.getTeachers().single.employeeNumber, 'ENS-2026-001');
    expect(restored.getAffectations().single.className, '3e A');
  });

  testWidgets('le dashboard enseignant affiche ses données et ouvre les notes',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store(_teacherClient());
    expect(await store.login(_email, _password), isTrue);

    await tester.pumpWidget(ChangeNotifierProvider<StoreService>.value(
      value: store,
      child: const EduProApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Mon espace enseignant'), findsOneWidget);
    expect(find.text('ENS-2026-001'), findsOneWidget);
    expect(find.text('3e A'), findsOneWidget);
    expect(find.text('Mathématiques'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'Le dashboard enseignant ne doit pas déborder.');

    await tester.tap(find.text('Saisir les notes'));
    await tester.pumpAndSettle();
    expect(find.text('Mes notes et résultats'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mes élèves reste limité au workspace de l enseignant',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store(_teacherClient());
    expect(await store.login(_email, _password), isTrue);

    await tester.pumpWidget(ChangeNotifierProvider<StoreService>.value(
      value: store,
      child: const EduProApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mes élèves'));
    await tester.pumpAndSettle();

    expect(find.text('Mes élèves'), findsWidgets);
    expect(find.byKey(const Key('teacher-students-class-filter')), findsOneWidget);
    expect(find.text('Toutes mes classes'), findsOneWidget);
    expect(find.text('Massamba'), findsOneWidget);
    expect(find.text('Chris'), findsOneWidget);
    expect(find.text('Matricule : ECOLE-2026-001'), findsOneWidget);
    expect(find.text('3e A'), findsWidgets);
    expect(find.text('Ajouter un élève'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'les notes enseignant utilisent uniquement les évaluations préparées par ADMIN',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store(_teacherClient());
    expect(await store.login(_email, _password), isTrue);

    await tester.pumpWidget(ChangeNotifierProvider<StoreService>.value(
      value: store,
      child: const EduProApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saisir les notes'));
    await tester.pumpAndSettle();

    Future<void> choose(int index, String labelPrefix) async {
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(index));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(labelPrefix).last);
      await tester.pumpAndSettle();
    }

    await choose(0, '3e A');
    expect(find.text('Matière : Mathématiques'), findsOneWidget);
    await choose(1, '1er trimestre');

    expect(find.textContaining('Mes évaluations à compléter'), findsOneWidget);

    await tester.tap(find.text('Devoir 1 · draft'));
    await tester.pump();
    await tester.tap(find.text('Composition · draft'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Note /20'), findsOneWidget);
    expect(find.text('Tous ont été notés'), findsNothing);
    expect(find.text('État'), findsNothing);
    expect(find.byKey(const ValueKey('grade-presence-student-1')), findsNothing);
    expect(find.byTooltip('Marquer absent'), findsOneWidget);
    await tester.tap(find.byTooltip('Marquer absent'));
    await tester.pump();
    expect(find.textContaining('Absent'), findsOneWidget);
    expect(find.byTooltip('Retirer l’absence'), findsOneWidget);
    final gradeField = tester.widget<TextField>(
      find.byKey(const ValueKey('grade-value-student-1')),
    );
    expect(gradeField.enabled, isTrue);
    expect(gradeField.controller?.text, isEmpty);

    expect(find.text('Nouvelle évaluation'), findsNothing);
    expect(find.text('Préparer une évaluation'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'la saisie combinée affiche uniquement les évaluations ordinaires programmées',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store(_teacherClient());
    expect(await store.login(_email, _password), isTrue);

    await tester.pumpWidget(ChangeNotifierProvider<StoreService>.value(
      value: store,
      child: const MaterialApp(
        home: Scaffold(body: CanonicalGradesPage()),
      ),
    ));
    await tester.pumpAndSettle();

    Future<void> choose(int index, String labelPrefix) async {
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(index));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(labelPrefix).last);
      await tester.pumpAndSettle();
    }

    await choose(0, '3e A');
    await choose(1, '1er trimestre');
    expect(find.byKey(const Key('grade-entry-combined')), findsOneWidget);

    await tester.tap(find.byKey(const Key('grade-entry-combined')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('combined-grade-entry-card')), findsOneWidget);
    expect(find.text('Devoir 1'), findsWidgets);
    expect(find.text('Composition'), findsWidgets);
    expect(
      find.byKey(const ValueKey('combined-grade-evaluation-1|student-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('combined-grade-evaluation-2|student-1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('submit-combined-grades')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('l emploi du temps enseignant est strictement en lecture seule',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store(_teacherClient());
    expect(await store.login(_email, _password), isTrue);

    await tester.pumpWidget(ChangeNotifierProvider<StoreService>.value(
      value: store,
      child: const EduProApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mon Emploi du temps'));
    await tester.pumpAndSettle();

    expect(find.text('Mon emploi du temps'), findsOneWidget);
    expect(find.text('Ajouter un cours'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.byTooltip('Retirer'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'le comportement enseignant est envoyé puis verrouillé sans action ADMIN',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store(_teacherClient());
    expect(await store.login(_email, _password), isTrue);

    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const Scaffold(body: BehaviorPage()),
      ),
    ));
    await tester.pumpAndSettle();

    Future<void> choose(int index, String labelPrefix) async {
      await tester.tap(find.byType(DropdownButtonFormField<String?>).at(index));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(labelPrefix).last);
      await tester.pumpAndSettle();
    }

    await choose(0, 'Coll');
    await choose(1, '3e');
    await choose(2, '3e A');
    await choose(3, '1er trimestre');
    await tester.pumpAndSettle();

    expect(find.text('Brouillon'), findsOneWidget);
    expect(find.textContaining('Date :'), findsNothing);
    expect(find.text('Trimestre'), findsOneWidget);
    // Nothing is selected automatically: an incomplete sheet must not be sent.
    expect(find.text('À renseigner'), findsOneWidget);
    await tester.tap(find.text('Envoyer et verrouiller'));
    await tester.pumpAndSettle();
    expect(find.text('Envoyé · verrouillé'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('★★★ (3)').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField), 'Participation régulière');
    await tester.tap(find.text('Envoyer et verrouiller'));
    await tester.pumpAndSettle();

    expect(find.text('Envoyé · verrouillé'), findsOneWidget);
    expect(find.text('Déjà envoyé'), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
        isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('l appel reste journalier et expose les statistiques dérivées',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store(_teacherClient());
    expect(await store.login(_email, _password), isTrue);

    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const Scaffold(body: AttendancePage()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Aujourd’hui :'), findsOneWidget);
    expect(find.text('Faire l’appel'), findsOneWidget);
    await tester.tap(find.text('Faire l’appel'));
    await tester.pumpAndSettle();

    expect(find.text('Présent'), findsOneWidget);
    expect(find.text('Absent'), findsOneWidget);
    expect(find.text('Absent justifié'), findsOneWidget);
    expect(find.text('Statistiques du jour'), findsOneWidget);
    expect(find.text('Statistiques du mois'), findsOneWidget);
    expect(find.textContaining('Statistiques du trimestre'), findsOneWidget);
    expect(find.text('Trimestre'), findsNothing);
    expect(find.text('Élève du serveur'), findsOneWidget);
    await tester.tap(find.text('Soumettre et verrouiller'));
    await tester.pumpAndSettle();
    expect(find.text('Relevé envoyé · verrouillé'), findsNothing);
    await tester.tap(find.text('Marquer tous présents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer l’appel'));
    await tester.pumpAndSettle();
    expect(find.text('Relevé envoyé · verrouillé'), findsNothing);
    await tester.tap(find.text('Soumettre et verrouiller'));
    await tester.pumpAndSettle();
    expect(find.text('Relevé envoyé · verrouillé'), findsOneWidget);
    expect(find.text('Marquer tous présents'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'les résultats ADMIN affichent le classement global sans filtre matière',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await createLegacyStore(withSeedData: true);
    expect(await store.login('admin@edupro.com', legacyTestPassword), isTrue);

    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const Scaffold(body: CanonicalGradesPage()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Résultats — classement par ordre de mérite'),
        findsOneWidget);
    expect(find.text('Matière'), findsNothing);
    expect(find.text('Nouvelle évaluation'), findsNothing);
    expect(find.text('Programmer une évaluation'), findsOneWidget);
    expect(find.text('Actualiser le suivi'), findsOneWidget);
    expect(find.text('En attente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'le formulaire enseignant sépare les matières possibles des affectations',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await createLegacyStore(withSeedData: true);
    expect(await store.login('admin@edupro.com', legacyTestPassword), isTrue);

    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const Scaffold(body: TeachersPage()),
      ),
    ));
    await tester.tap(find.text('Nouvel enseignant'));
    await tester.pumpAndSettle();

    expect(find.text('Matières que cet enseignant peut enseigner'),
        findsOneWidget);
    expect(find.text('Classes assignées'), findsNothing);
    expect(
        find.textContaining('définies depuis chaque classe'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('le mot de passe temporaire enseignant ne persiste jamais localement',
      () async {
    SharedPreferences.setMockInitialValues({});
    const temporaryPassword = 'teacher-temporary-secret';
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/school/teachers/teacher-1/access');
      return http.Response(
          jsonEncode({
            'teacher': Map<String, dynamic>.from(_workspace['teacher'] as Map),
            'temporaryPassword': temporaryPassword,
          }),
          200);
    });
    final store = StoreService(api: ApiClient(client: client));
    await store.init();

    expect(await store.provisionTeacherAccess('teacher-1'), temporaryPassword);
    final preferences = await SharedPreferences.getInstance();
    expect(
        preferences.getKeys().any((key) =>
            preferences.get(key).toString().contains(temporaryPassword)),
        isFalse);
  });
}
