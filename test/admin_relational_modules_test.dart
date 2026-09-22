import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/models/academic_year_model.dart';
import 'package:edupro_flutter_web/data/models/class_model.dart';
import 'package:edupro_flutter_web/data/models/teacher_model.dart';
import 'package:edupro_flutter_web/data/repositories/school_repository.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/schedule/schedule_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('le matricule metier enseignant reste disponible dans Flutter', () {
    final teacher = TeacherModel.fromJson({
      'id': 'teacher-uuid',
      'firstName': 'Marie',
      'lastName': 'Test',
      'schoolId': 'school-1',
      'employeeNumber': 'ENS-2026-001',
    });

    expect(teacher.employeeNumber, 'ENS-2026-001');
    expect(teacher.toJson()['employeeNumber'], 'ENS-2026-001');
    expect(teacher.fullName, 'Test Marie');
  });

  test('une classe expose un seul professeur principal persistant', () {
    final schoolClass = ClassModel.fromJson({
      'id': 'class-1',
      'name': '3e A',
      'schoolId': 'school-1',
      'mainTeacherId': 'teacher-1',
      'mainTeacher': 'MABIALA Aline',
      'createdAt': '2026-09-01T08:00:00Z',
    });

    expect(schoolClass.mainTeacherId, 'teacher-1');
    expect(schoolClass.mainTeacher, 'MABIALA Aline');
    expect(schoolClass.createdAt, '2026-09-01T08:00:00Z');
    expect(schoolClass.toJson()['mainTeacherId'], 'teacher-1');
  });

  test('repository ADMIN utilise les routes relationnelles des lots B a F',
      () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add(request.method + ' ' + request.url.path);
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      if (request.url.path.endsWith('/grades') && request.method == 'PUT') {
        expect(body['entries'], isA<List>());
        return _json(<Map<String, dynamic>>[], 200);
      }
      if (request.url.path == '/api/v1/school/attendance' &&
          request.method == 'PUT') {
        expect(body['entries'], isA<List>());
        expect(body['scheduleId'], 'schedule-1');
        return _json(<Map<String, dynamic>>[], 200);
      }
      if (request.url.path == '/api/v1/school/behavior' &&
          request.method == 'PUT') {
        expect(body['entries'], isA<List>());
        expect(body['periodId'], 'p-1');
        return _json(<Map<String, dynamic>>[], 200);
      }
      if (request.url.path.endsWith('/status')) {
        expect(body['status'], 'submitted');
        return _json(_evaluation(status: 'submitted'), 200);
      }
      if (request.url.path.endsWith('/bulletin')) {
        return _json({'annualCalculable': true, 'annualAverage': 15}, 200);
      }
      if (request.url.path.endsWith('/results')) {
        return _json({'students': <Object?>[]}, 200);
      }
      if (request.url.path == '/api/v1/school/evaluation-programs' &&
          request.method == 'POST') {
        expect(body.containsKey('subjectId'), isFalse);
        expect(body.containsKey('teacherId'), isFalse);
        expect(body['classIds'], ['c-1', 'c-2']);
        return _json({
          'program': {'id': 'program-1'},
          'evaluations': <Map<String, dynamic>>[],
        }, 201);
      }
      if (request.method == 'DELETE') return http.Response('', 204);
      if (request.method == 'GET') return _json(<Map<String, dynamic>>[], 200);
      if (request.url.path.endsWith('/evaluations')) {
        return _json(_evaluation(), 201);
      }
      return _json(body, request.method == 'POST' ? 201 : 200);
    });
    final repository = SchoolRepository(ApiClient(client: client));

    await repository.students(academicYearId: 'year-1', search: 'EDU-1');
    await repository.createStudent({'firstName': 'Alice', 'lastName': 'Test'});
    await repository.updateStudent('st-1', {'firstName': 'Alicia'});
    await repository.studentRegistrations('st-1');
    await repository.createStudentRegistration('st-1', 'c-1');
    await repository.preEnrollments(academicYearId: 'year-1');
    await repository.createPreEnrollment({
      'studentId': 'st-1',
      'academicYearId': 'year-1',
      'desiredClassId': 'c-1',
    });
    await repository.approvePreEnrollment('pre-1', classId: 'c-1');
    await repository.guardians(search: 'Parent');
    await repository
        .createGuardian({'firstName': 'Parent', 'lastName': 'Test'});
    await repository.linkStudentGuardian('st-1', 'g-1', 'mere', true);
    await repository.teachers(search: 'Paul');
    await repository.createTeacher({'firstName': 'Paul', 'lastName': 'Test'});
    await repository.subjects();
    await repository.createSubject({'name': 'Sciences'});
    await repository.affectations(academicYearId: 'year-1');
    await repository.createAffectation(
        {'teacherId': 't-1', 'classId': 'c-1', 'subjectId': 's-1'});
    await repository.setClassMainTeacher('c-1', 't-1');
    await repository.clearClassMainTeacher('c-1');
    await repository.academicPeriods('year-1');
    await repository.evaluations(academicYearId: 'year-1');
    await repository.createEvaluation({
      'title': 'D1',
      'type': 'devoir',
      'classId': 'c-1',
      'subjectId': 's-1',
      'periodId': 'p-1',
    });
    await repository.createEvaluationProgram({
      'title': 'Devoir 1',
      'type': 'devoir',
      'classIds': ['c-1', 'c-2'],
      'periodId': 'p-1',
      'maxScore': 20,
    });
    await repository.updateEvaluationStatus('e-1', 'submitted');
    await repository.saveEvaluationGrades('e-1', [
      {'studentId': 'st-1', 'value': 15, 'presence': 'present'}
    ]);
    await repository.attendance('c-1', date: '2026-09-15');
    await repository.saveAttendance({
      'classId': 'c-1',
      'scheduleId': 'schedule-1',
      'date': '2026-09-15',
      'entries': <Map<String, dynamic>>[],
    });
    await repository.behaviorEvents(academicYearId: 'year-1', periodId: 'p-1');
    await repository.createBehaviorEvent({
      'studentId': 'st-1',
      'classId': 'c-1',
      'periodId': 'p-1',
      'category': 'comportement',
      'eventType': 'positive',
      'severity': 'normal',
      'title': 'Participation',
    });
    await repository.submitBehavior({
      'classId': 'c-1',
      'periodId': 'p-1',
      'entries': [
        {'studentId': 'st-1', 'stars': 4, 'comment': 'Très bien'}
      ],
    });
    await repository.archiveBehaviorEvent('behavior-1');
    await repository.assignments(academicYearId: 'year-1');
    await repository.createAssignment({
      'classId': 'c-1',
      'subjectId': 's-1',
      'title': 'Exercices',
      'dueDate': '2026-09-20',
    });
    await repository.updateAssignment('assignment-1', {
      'classId': 'c-1',
      'subjectId': 's-1',
      'title': 'Exercices corriges',
      'dueDate': '2026-09-21',
    });
    await repository.archiveAssignment('assignment-1');
    await repository.schedule('year-1', classId: 'c-1');
    await repository.createScheduleEntry({
      'classId': 'c-1',
      'subjectId': 's-1',
      'teacherId': 't-1',
      'dayOfWeek': 1,
      'startTime': '08:00',
      'endTime': '09:00',
    });
    await repository.archiveScheduleEntry('schedule-1');
    await repository.studentBulletin('st-1', 'year-1');
    await repository.schoolResults('c-1', 'p-1');
    await repository.calculateSchoolResults('c-1', 'p-1');

    expect(calls, contains('GET /api/v1/school/students'));
    expect(calls, contains('POST /api/v1/school/students'));
    expect(calls, contains('POST /api/v1/school/students/st-1/registrations'));
    expect(calls, contains('GET /api/v1/school/pre-enrollments'));
    expect(calls, contains('POST /api/v1/school/guardians'));
    expect(calls, contains('POST /api/v1/school/students/st-1/guardians'));
    expect(calls, contains('GET /api/v1/school/teachers'));
    expect(calls, contains('POST /api/v1/school/teachers'));
    expect(calls, contains('GET /api/v1/school/subjects'));
    expect(calls, contains('POST /api/v1/school/affectations'));
    expect(calls, contains('PUT /api/v1/school/classes/c-1/main-teacher'));
    expect(calls, contains('DELETE /api/v1/school/classes/c-1/main-teacher'));
    expect(calls, contains('GET /api/v1/school/academic-periods'));
    expect(calls, contains('POST /api/v1/school/evaluations'));
    expect(calls, contains('POST /api/v1/school/evaluation-programs'));
    expect(calls, contains('PUT /api/v1/school/evaluations/e-1/grades'));
    expect(calls, contains('PUT /api/v1/school/attendance'));
    expect(calls, contains('GET /api/v1/school/behavior'));
    expect(calls, contains('POST /api/v1/school/behavior'));
    expect(calls, contains('PUT /api/v1/school/behavior'));
    expect(calls, contains('DELETE /api/v1/school/behavior/behavior-1'));
    expect(calls, contains('GET /api/v1/school/assignments'));
    expect(calls, contains('POST /api/v1/school/assignments'));
    expect(calls, contains('PUT /api/v1/school/assignments/assignment-1'));
    expect(calls, contains('DELETE /api/v1/school/assignments/assignment-1'));
    expect(calls, contains('GET /api/v1/school/schedule'));
    expect(calls, contains('POST /api/v1/school/schedule'));
    expect(calls, contains('DELETE /api/v1/school/schedule/schedule-1'));
    expect(calls, contains('GET /api/v1/school/students/st-1/bulletin'));
    expect(calls, contains('GET /api/v1/school/results'));
    expect(calls, contains('POST /api/v1/school/results/calculate'));
    expect(calls.where((call) => call.contains('/api/v1/teachers')), isEmpty);
  });

  test('repository propage un module metier desactive', () async {
    final repository = SchoolRepository(ApiClient(
        client: MockClient((_) async =>
            _json({'detail': "Module 'attendance' desactive"}, 403))));
    await expectLater(
      repository.attendance('class-1'),
      throwsA(isA<ApiException>()
          .having((error) => error.statusCode, 'statusCode', 403)),
    );
  });

  test('un responsable existant est reutilise pour un second enfant', () async {
    SharedPreferences.setMockInitialValues({
      'edupro_initialized': 'true',
      'edupro_usersList': '[]',
      'edupro_establishments': '[]',
      'edupro_academicYears': '[]',
      'edupro_students': '[]',
    });
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/school/guardians') {
        expect(request.url.queryParameters['search'], '+242 06 000 0000');
        return _json([
          {
            'id': 'guardian-1',
            'firstName': 'Marie',
            'lastName': 'Test',
            'phone': '+242060000000',
          }
        ], 200);
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/school/students/student-2/guardians') {
        final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        expect(body['guardianId'], 'guardian-1');
        expect(body['relationship'], 'tutrice');
        expect(body['isPrimary'], isTrue);
        return _json({'id': 'student-2'}, 201);
      }
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/school/students') {
        return _json(<Map<String, dynamic>>[], 200);
      }
      return _json(<String, dynamic>{}, 200);
    });
    final store = StoreService(api: ApiClient(client: client));
    await store.init();

    await store.createGuardianAndLinkRemote(
      studentId: 'student-2',
      firstName: 'Marie',
      lastName: 'Test',
      phone: '+242 06 000 0000',
      address: 'Brazzaville',
      profession: 'Commercante',
      relationship: 'tutrice',
    );

    expect(calls, contains('POST /api/v1/school/students/student-2/guardians'));
    expect(calls, isNot(contains('POST /api/v1/school/guardians')));
  });

  testWidgets('emploi du temps affiche un etat vide PostgreSQL explicite',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'edupro_initialized': 'true',
      'edupro_usersList': '[]',
      'edupro_establishments': '[]',
      'edupro_academicYears': '[]',
      'edupro_students': '[]',
    });
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/school/schedule') {
        return _json(<Map<String, dynamic>>[], 200);
      }
      if (request.method == 'POST' || request.method == 'PUT') {
        final body = request.body.isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        return _json(
            body['payload'] ?? body, request.method == 'POST' ? 201 : 200);
      }
      return _json(<Map<String, dynamic>>[], 200);
    });
    final store = StoreService(api: ApiClient(client: client));
    await store.init();
    store.addAcademicYear(AcademicYearModel(
      id: 'year-1',
      name: '2026-2027',
      start: '2026-09-01',
      end: '2027-07-15',
      schoolId: 'school-1',
      isActive: true,
    ));
    store.addClass(ClassModel(
      id: 'class-1',
      name: '6e A',
      schoolId: 'school-1',
      academicYearId: 'year-1',
    ));
    store.setSelectedAcademicYearId('year-1');

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: const MaterialApp(home: Scaffold(body: SchedulePage())),
    ));
    await tester.pumpAndSettle();

    expect(
        find.text('Aucun cours planifié pour cette classe.'), findsOneWidget);
    expect(find.text('Mathematiques\nSalle 102'), findsNothing);
  });
}

Map<String, dynamic> _evaluation({String status = 'draft'}) => {
      'id': 'e-1',
      'title': 'D1',
      'type': 'devoir',
      'academicYearId': 'year-1',
      'periodId': 'p-1',
      'classId': 'c-1',
      'subjectId': 's-1',
      'status': status,
      'maxScore': 20,
      'createdBy': 'u-1',
      'createdAt': '2026-09-01T00:00:00Z',
      'schoolId': 'school-1',
    };

http.Response _json(Object? value, int status) => http.Response(
      jsonEncode(value),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
