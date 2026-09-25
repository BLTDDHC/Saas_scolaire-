import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/models/student_model.dart';
import 'package:edupro_flutter_web/data/repositories/school_repository.dart';
import 'package:edupro_flutter_web/core/utils/school_module_access.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/grades/student_results_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  test('repository expose les ressources canoniques du coeur Admin', () async {
    final calls = <String>[];
    final payloads = <String, Map<String, dynamic>>{};
    final repository =
        SchoolRepository(ApiClient(client: MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.body.isNotEmpty) {
        payloads[request.url.path] =
            Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      }
      if (request.method == 'GET' &&
          request.url.path.endsWith('/calendar/settings')) {
        return _json(null, 200);
      }
      if (request.method == 'GET' &&
          (request.url.path.endsWith('/attendance/statistics') ||
              request.url.path.endsWith('/results') ||
              request.url.path.endsWith('/my-results'))) {
        return _json(<String, dynamic>{}, 200);
      }
      if (request.method == 'GET') return _json(<Map<String, dynamic>>[], 200);
      return _json(payloads[request.url.path] ?? <String, dynamic>{},
          request.method == 'POST' ? 201 : 200);
    })));

    await repository.schoolSeries(cycleId: 'cycle-1');
    await repository.createSchoolSeries(
        {'cycleId': 'cycle-1', 'code': 'C', 'name': 'Serie C'});
    await repository.calendarSettings('year-1');
    await repository.saveCalendarSettings({
      'academicYearId': 'year-1',
      'teachingDays': [1, 2, 3, 4, 5],
      'dayStart': '07:00',
      'dayEnd': '17:00',
      'courseDurationMinutes': 60,
      'pauseDurationMinutes': 15,
      'pauseFrequency': 2,
    });
    await repository.evaluationRules('year-1');
    await repository.createAcademicPeriod({
      'academicYearId': 'year-1',
      'code': 'T1',
      'name': 'Trimestre 1',
      'periodType': 'trimester',
    });
    await repository.updateAcademicPeriod('period-1', {
      'academicYearId': 'year-1',
      'code': 'T1',
      'name': 'Premier trimestre',
      'periodType': 'trimester',
    });
    await repository.createCalendarEvent({
      'academicYearId': 'year-1',
      'title': 'Composition',
      'eventType': 'pedagogical',
      'startDate': '2026-10-01',
      'endDate': '2026-10-01',
    });
    await repository.updateCalendarEvent('event-1', {
      'academicYearId': 'year-1',
      'title': 'Composition octobre',
      'eventType': 'pedagogical',
      'startDate': '2026-10-01',
      'endDate': '2026-10-01',
    });
    await repository.createEvaluationRule({
      'academicYearId': 'year-1',
      'cycleId': 'cycle-1',
      'evaluationType': 'composition',
      'label': 'Composition mensuelle',
    });
    await repository.updateEvaluationRule('rule-1', {
      'academicYearId': 'year-1',
      'cycleId': 'cycle-1',
      'evaluationType': 'composition',
      'label': 'Composition mensuelle',
    });
    await repository.annualDecisions('year-1');
    await repository.updateScheduleEntry('entry-1', {
      'classId': 'class-1',
      'subjectId': 'subject-1',
      'teacherId': 'teacher-1',
      'weekday': 1,
      'startTime': '08:00',
      'endTime': '09:00',
    });
    await repository.saveAnnualDecision(
        'student-1', {'academicYearId': 'year-1', 'decision': 'admitted'});
    await repository.createStudentRegistration('student-1', 'class-1',
        schoolRegime: 'full_time', hasTd: true);
    await repository.attendanceStatistics('class-1', month: 10);
    await repository.studentResults('student-1', 'year-1');
    await repository.myStudentResults();

    expect(calls, contains('GET /api/v1/school/series'));
    expect(calls, contains('POST /api/v1/school/series'));
    expect(calls, contains('PUT /api/v1/school/calendar/settings'));
    expect(calls, contains('GET /api/v1/school/evaluation-rules'));
    expect(calls, contains('POST /api/v1/school/academic-periods'));
    expect(calls, contains('PUT /api/v1/school/academic-periods/period-1'));
    expect(calls, contains('POST /api/v1/school/calendar/events'));
    expect(calls, contains('PUT /api/v1/school/calendar/events/event-1'));
    expect(calls, contains('POST /api/v1/school/evaluation-rules'));
    expect(calls, contains('PUT /api/v1/school/evaluation-rules/rule-1'));
    expect(calls, contains('GET /api/v1/school/annual-decisions'));
    expect(calls, contains('PUT /api/v1/school/schedule/entry-1'));
    expect(calls,
        contains('PUT /api/v1/school/students/student-1/annual-decision'));
    expect(calls,
        contains('POST /api/v1/school/students/student-1/registrations'));
    expect(payloads['/api/v1/school/students/student-1/registrations'], {
      'classId': 'class-1',
      'schoolRegime': 'full_time',
      'hasTd': true,
      'options': <String, dynamic>{},
    });
    expect(calls, contains('GET /api/v1/school/attendance/statistics'));
    expect(calls, contains('GET /api/v1/school/students/student-1/results'));
    expect(calls, contains('GET /api/v1/school/my-results'));
    expect(payloads['/api/v1/school/calendar/settings']?['teachingDays'],
        [1, 2, 3, 4, 5]);
  });

  testWidgets('un eleve consulte ses resultats sans ecran de saisie',
      (tester) async {
    final store = StoreService(
      api: ApiClient(
        client: MockClient((request) async => _json({
              'studentId': 'student-1',
              'studentName': 'Jean Test',
              'years': [
                {
                  'registration': {
                    'academicYearName': '2026-2027',
                    'className': '6e A',
                    'cycle': 'College',
                    'cycleCode': 'COLLEGE',
                    'level': '6e',
                  },
                  'notes': [
                    {
                      'period': 'Trimestre 1',
                      'periodOrder': 1,
                      'date': '2026-10-01',
                      'subject': 'Mathematiques',
                      'evaluation': 'Devoir 1',
                      'evaluationType': 'devoir',
                      'examCode': 'devoir_1',
                      'presence': 'present',
                      'value': 15,
                      'maxValue': 20,
                    }
                  ],
                  'periods': [
                    {
                      'period': 'Trimestre 1',
                      'average': 14.5,
                      'averageScale': 20,
                      'rank': 2,
                      'mention': 'Bien',
                      'subjects': [
                        {
                          'subject': 'Mathematiques',
                          'average': 14.5,
                          'grades': [
                            {
                              'evaluation': 'Devoir 1',
                              'type': 'devoir',
                              'value': 15,
                              'maxValue': 20,
                            },
                            {
                              'evaluation': 'Devoir 2',
                              'type': 'devoir',
                              'value': 14,
                              'maxValue': 20,
                            },
                            {
                              'evaluation': 'Composition',
                              'type': 'composition',
                              'value': 14.5,
                              'maxValue': 20,
                            },
                          ],
                        }
                      ],
                      'exams': [
                        {
                          'code': 'bepc_blanc',
                          'name': 'BEPC Blanc',
                          'average': 13,
                          'rank': 3,
                          'subjects': [
                            {
                              'subject': 'Mathematiques',
                              'average': 13,
                              'grades': [
                                {'value': 13, 'maxValue': 20}
                              ],
                            }
                          ],
                        }
                      ],
                      'ranking': [
                        {
                          'studentId': 'student-1',
                          'studentName': 'Jean Test',
                          'average': 14.5,
                          'rank': 2,
                        }
                      ],
                    }
                  ],
                }
              ],
            }, 200)),
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(home: StudentResultsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Notes'), findsWidgets);
    expect(find.text('Voir les résultats'), findsOneWidget);
    expect(find.text('Jean Test'), findsOneWidget);
    expect(find.text('2026-2027'), findsOneWidget);
    expect(find.text('Notes récemment soumises'), findsOneWidget);
    expect(find.text('15 / 20'), findsOneWidget);
    expect(find.textContaining('Moyenne : 14.5'), findsNothing);

    await tester.tap(find.byKey(const Key('student-results-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Résultats'), findsWidgets);
    expect(find.byKey(const Key('student-result-selector')), findsOneWidget);

    await tester.tap(find.byKey(const Key('student-result-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trimestre 1').last);
    await tester.pumpAndSettle();
    expect(find.text('Moyenne générale'), findsOneWidget);
    expect(find.text('Mention'), findsOneWidget);
    expect(find.text('Bien'), findsWidgets);
    expect(find.text('Devoir 1'), findsOneWidget);
    expect(find.text('Devoir 2'), findsOneWidget);
    expect(find.text('Composition'), findsOneWidget);
    expect(find.text('BEPC Blanc'), findsNothing);

    await tester.tap(find.byKey(const Key('student-result-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BEPC Blanc').last);
    await tester.pumpAndSettle();
    expect(find.text('BEPC Blanc'), findsWidgets);
    expect(find.textContaining('Moyenne : 13'), findsOneWidget);
    expect(find.text('13 / 20'), findsOneWidget);
    expect(find.text('Devoir 1'), findsNothing);
    expect(find.text('Coefficient'), findsNothing);
    expect(find.text('Nouvelle évaluation'), findsNothing);
  });

  test('la navigation applique enabled_modules a tous les modules scolaires',
      () {
    const enabled = {'students', 'classes', 'grades'};

    expect(isSchoolPageEnabled('students', enabled), isTrue);
    expect(isSchoolPageEnabled('grades', enabled), isTrue);
    expect(isSchoolPageEnabled('assignments', enabled), isTrue);
    expect(isSchoolPageEnabled('attendance', enabled), isFalse);
    expect(isSchoolPageEnabled('teachers', enabled), isFalse);
    expect(isSchoolPageEnabled('dashboard', enabled), isTrue);
    expect(isSchoolPageEnabled('settings', enabled), isTrue);
  });

  test('identite eleve conserve nationalite et matricule annuel recu', () {
    final student = StudentModel.fromJson({
      'id': 'student-1',
      'firstName': 'Aline',
      'lastName': 'Test',
      'schoolId': 'school-1',
      'nationality': 'Congolaise',
      'matricule': 'MAT-SCHOOL-2026-0001',
    });

    expect(student.nationality, 'Congolaise');
    expect(student.matricule, 'MAT-SCHOOL-2026-0001');
    expect(student.toJson()['nationality'], 'Congolaise');
  });
}

http.Response _json(Object? value, int status) => http.Response(
      jsonEncode(value),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
