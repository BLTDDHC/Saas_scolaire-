import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/grades/student_results_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

Map<String, dynamic> _year({
  required String studentMarker,
  double submitted = 16,
}) => {
      'registration': {
        'academicYearId': 'year-1',
        'academicYearName': '2026-2027',
        'className': '3e A',
        'cycle': 'Collège',
        'cycleCode': 'COLLEGE',
        'level': '3e',
      },
      'notes': [
        {
          'gradeId': 'grade-$studentMarker',
          'evaluationId': 'eval-$studentMarker',
          'evaluation': 'Devoir 1',
          'evaluationType': 'devoir',
          'examCode': 'devoir_1',
          'periodId': 'p1',
          'period': 'T1',
          'periodType': 'trimester',
          'periodOrder': 1,
          'subjectId': 'math',
          'subject': 'Mathématiques',
          'date': '2026-10-10',
          'value': submitted,
          'maxValue': 20,
          'presence': 'present',
          'status': 'submitted',
        },
      ],
      'periods': [
        {
          'periodId': 'p1',
          'period': 'T1',
          'periodType': 'trimester',
          'periodOrder': 1,
          'average': 14.5,
          'averageScale': 20,
          'rank': 2,
          'mention': 'Bien',
          'subjects': [
            {
              'subjectId': 'math',
              'subject': 'Mathématiques',
              'average': 14.5,
              'mc': 14,
              'grades': [
                {
                  'evaluation': 'Devoir 1',
                  'type': 'devoir',
                  'examCode': 'devoir_1',
                  'value': 14,
                  'maxValue': 20,
                },
              ],
            },
          ],
          'exams': [
            {
              'code': 'bac_blanc',
              'name': 'BAC Blanc',
              'average': 12.75,
              'rank': 5,
              'subjects': [
                {
                  'subject': 'Mathématiques',
                  'average': 12.75,
                  'grades': [
                    {'value': 12.75, 'maxValue': 20},
                  ],
                },
              ],
            },
            {
              'code': 'devoir_departemental',
              'name': 'Devoir départemental',
              'average': 15.25,
              'rank': 1,
              'subjects': [
                {
                  'subject': 'Mathématiques',
                  'average': 15.25,
                  'grades': [
                    {'value': 15.25, 'maxValue': 20},
                  ],
                },
              ],
            },
          ],
          'rankingCount': 30,
          'ranking': const [],
        },
      ],
    };

Map<String, dynamic> _studentPayload(String name, String marker,
        {double submitted = 16}) =>
    {
      'studentName': name,
      'years': [_year(studentMarker: marker, submitted: submitted)],
    };

Widget _studentApp(Map<String, dynamic> payload) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StudentResultsPage(
            embedded: true,
            request: Future.value(payload),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
      'Notes et résultats sont séparés et un résultat spécial est exclusif',
      (tester) async {
    await tester.pumpWidget(_studentApp(
        _studentPayload('Élève Test', 'student-a', submitted: 16)));
    await tester.pumpAndSettle();

    expect(find.text('Notes récemment soumises'), findsOneWidget);
    expect(find.text('16 / 20'), findsOneWidget);
    expect(find.byKey(const Key('student-show-results')), findsOneWidget);
    expect(find.text('Moyenne générale'), findsNothing);

    await tester.tap(find.byKey(const Key('student-show-results')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('student-result-selection')), findsOneWidget);
    expect(find.text('Sélectionnez un résultat.'), findsOneWidget);
    expect(find.text('16 / 20'), findsNothing);

    await tester.tap(find.byKey(const Key('student-result-selection')));
    await tester.pumpAndSettle();
    expect(find.text('T1'), findsWidgets);
    expect(find.text('T1 · BAC Blanc'), findsOneWidget);
    expect(find.text('T1 · Devoir départemental'), findsOneWidget);

    await tester.tap(find.text('T1 · BAC Blanc'));
    await tester.pumpAndSettle();
    expect(find.text('BAC Blanc'), findsWidgets);
    expect(find.textContaining('12.75'), findsWidgets);
    expect(find.text('Devoir départemental'), findsNothing);
    expect(find.text('Moyenne générale'), findsNothing);

    await tester.tap(find.byKey(const Key('student-result-selection')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('T1 · Devoir départemental'));
    await tester.pumpAndSettle();
    expect(find.text('Devoir départemental'), findsWidgets);
    expect(find.textContaining('15.25'), findsWidgets);
    expect(find.text('BAC Blanc'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Parent change réellement d enfant sans conserver les notes',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/school/my-children') {
        return http.Response(
            jsonEncode([
              {
                'id': 'child-a',
                'fullName': 'Enfant A',
                'years': [
                  {'id': 'year-1', 'name': '2026-2027'}
                ],
              },
              {
                'id': 'child-b',
                'fullName': 'Enfant B',
                'years': [
                  {'id': 'year-1', 'name': '2026-2027'}
                ],
              },
            ]),
            200);
      }
      if (request.url.path == '/api/v1/school/students/child-a/results') {
        return http.Response(
            jsonEncode(_year(studentMarker: 'child-a', submitted: 11)), 200);
      }
      if (request.url.path == '/api/v1/school/students/child-b/results') {
        return http.Response(
            jsonEncode(_year(studentMarker: 'child-b', submitted: 18)), 200);
      }
      return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
    });
    final store = StoreService(api: ApiClient(client: client));

    await tester.pumpWidget(
      ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const MaterialApp(home: ParentResultsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Enfant A'), findsWidgets);
    expect(find.text('11 / 20'), findsOneWidget);
    expect(find.text('18 / 20'), findsNothing);

    await tester.tap(find.byKey(const Key('parent-child-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enfant B').last);
    await tester.pumpAndSettle();

    expect(find.text('Enfant B'), findsWidgets);
    expect(find.text('18 / 20'), findsOneWidget);
    expect(find.text('11 / 20'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
