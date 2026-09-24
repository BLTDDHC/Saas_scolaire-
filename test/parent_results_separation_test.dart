import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/grades/student_results_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

http.Response jsonResponse(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> resultFor(String studentName, int note, double average) => {
      'registration': {
        'academicYearName': '2026-2027',
        'className': '3e A',
        'cycle': 'Collège',
        'cycleCode': 'COLLEGE',
        'level': '3e',
      },
      'notes': [
        {
          'period': '1er trimestre',
          'periodOrder': 1,
          'date': '2026-10-01',
          'subject': 'Mathématiques',
          'evaluation': 'Devoir 1',
          'evaluationType': 'devoir',
          'examCode': 'devoir_1',
          'presence': 'present',
          'value': note,
          'maxValue': 20,
        }
      ],
      'periods': [
        {
          'period': '1er trimestre',
          'periodType': 'trimester',
          'average': average,
          'averageScale': 20,
          'rank': 1,
          'mention': 'Bien',
          'subjects': [
            {
              'subject': 'Mathématiques',
              'average': average,
              'grades': [
                {
                  'evaluation': 'Devoir 1',
                  'type': 'devoir',
                  'value': note,
                  'maxValue': 20,
                }
              ],
            }
          ],
          'exams': const [],
          'ranking': [
            {
              'studentId': 'self',
              'studentName': studentName,
              'average': average,
              'rank': 1,
            }
          ],
        }
      ],
    };

void main() {
  testWidgets(
      'parent sépare notes/résultats et recharge sans fuite au changement d enfant',
      (tester) async {
    final calls = <String>[];
    final api = ApiClient(
      client: MockClient((request) async {
        calls.add(request.url.path);
        if (request.url.path == '/api/v1/school/my-children') {
          return jsonResponse([
            {
              'id': 'child-a',
              'fullName': 'Enfant Alpha',
              'years': [
                {'id': 'year-1', 'name': '2026-2027', 'className': '3e A'}
              ],
            },
            {
              'id': 'child-b',
              'fullName': 'Enfant Beta',
              'years': [
                {'id': 'year-1', 'name': '2026-2027', 'className': '3e B'}
              ],
            },
          ]);
        }
        if (request.url.path == '/api/v1/school/students/child-a/results') {
          return jsonResponse(resultFor('Enfant Alpha', 15, 14.5));
        }
        if (request.url.path == '/api/v1/school/students/child-b/results') {
          return jsonResponse(resultFor('Enfant Beta', 11, 12.0));
        }
        return jsonResponse({'detail': 'Not Found'});
      }),
    );
    final store = StoreService(api: api);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(
          home: Scaffold(body: ParentResultsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Enfant Alpha'), findsWidgets);
    expect(find.text('15 / 20'), findsOneWidget);
    expect(find.text('Voir les résultats'), findsOneWidget);
    expect(find.text('Enfant Beta'), findsOneWidget);

    final childSelector = find.byType(DropdownButtonFormField<String>).first;
    await tester.tap(childSelector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enfant Beta').last);
    await tester.pumpAndSettle();

    expect(find.text('11 / 20'), findsOneWidget);
    expect(find.text('15 / 20'), findsNothing);
    expect(calls.where((path) => path.contains('child-a/results')).length, 1);
    expect(calls.where((path) => path.contains('child-b/results')).length, 1);

    await tester.tap(find.byKey(const Key('student-results-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('student-result-selector')), findsOneWidget);
    await tester.tap(find.byKey(const Key('student-result-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1er trimestre').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Moyenne : 12.0'), findsOneWidget);
    expect(find.textContaining('Moyenne : 14.5'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
