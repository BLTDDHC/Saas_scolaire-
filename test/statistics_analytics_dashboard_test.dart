import 'dart:async';

import 'package:edupro_flutter_web/features/school/statistics/statistics_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> snapshot({
  required int students,
  required double average,
  required double success,
}) =>
    {
      'studentCount': students,
      'officialStudentCount': students,
      'overallAverage': average,
      'successRate': success,
      'failureRate': 100 - success,
      'attendanceRate': 90,
      'teacherCount': 4,
      'classCount': 2,
      'absenceCount': 3,
      'lateCount': 1,
      'gradeCompletionRate': 75,
      'teacherStatistics': const {
        'plannedCourses': 12,
        'completedCourses': 9,
      },
      'distribution': const {
        'Excellent': 1,
        'Très bien': 1,
        'Bien': 2,
        'Assez bien': 1,
        'Passable': 1,
        'Insuffisant': 0,
      },
      'evolution': const [
        {'period': 'T1', 'average20': 11.5},
        {'period': 'T2', 'average20': 13.0},
      ],
      'byClass': const [
        {
          'className': '3e A',
          'studentCount': 3,
          'average20': 14,
          'successRate': 100,
        },
        {
          'className': '3e B',
          'studentCount': 3,
          'average20': 10,
          'successRate': 66.67,
        },
      ],
      'byCycle': const [],
      'byLevel': const [
        {'level': '3e', 'studentCount': 6, 'average20': 12},
      ],
      'bySubject': const [
        {
          'subject': 'Mathématiques',
          'studentCount': 6,
          'average20': 12,
          'successRate': 83.33,
        },
      ],
      'monthlyEvolution': const [],
      'attendanceByClass': const [],
      'gradeCompletion': const [],
      'top10': const [],
      'decisions': const {},
      'insights': const [
        {
          'title': 'Progression',
          'message': 'La moyenne officielle progresse entre T1 et T2.',
        },
      ],
      'alerts': const [],
    };

Widget app(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('affiche une hiérarchie analytique avec de vrais graphiques',
      (tester) async {
    await tester.pumpWidget(app(StatisticsSnapshotView(
      request: Future.value(snapshot(students: 6, average: 12, success: 80)),
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('statistics-kpi-grid')), findsOneWidget);
    expect(find.byKey(const Key('statistics-evolution-chart')), findsOneWidget);
    expect(find.byKey(const Key('statistics-level-distribution')), findsOneWidget);
    expect(find.byKey(const Key('statistics-class-bars')), findsOneWidget);
    expect(find.byKey(const Key('statistics-class-ranking')), findsOneWidget);
    expect(find.byKey(const Key('statistics-detail-table')), findsOneWidget);
    expect(find.text('Ce qu’il faut retenir'), findsOneWidget);
    expect(find.text('6'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('masque l ancien instantané pendant la mise à jour',
      (tester) async {
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();

    await tester.pumpWidget(app(StatisticsSnapshotView(request: first.future)));
    first.complete(snapshot(students: 6, average: 12, success: 80));
    await tester.pumpAndSettle();
    debugPrint(
        'stats-regression:first 80=${find.text('80.0 %').evaluate().length} loading=${find.text('Mise à jour des analyses…').evaluate().length}');
    expect(find.text('80.0 %'), findsOneWidget);

    await tester.pumpWidget(app(StatisticsSnapshotView(request: second.future)));
    await tester.pump();
    debugPrint(
        'stats-regression:loading 80=${find.text('80.0 %').evaluate().length} loading=${find.text('Mise à jour des analyses…').evaluate().length}');
    expect(find.text('Mise à jour des analyses…'), findsOneWidget);
    expect(find.text('80.0 %'), findsNothing);

    second.complete(snapshot(students: 3, average: 9, success: 40));
    await tester.pumpAndSettle();
    debugPrint(
        'stats-regression:second 40=${find.text('40.0 %').evaluate().length} 80=${find.text('80.0 %').evaluate().length} loading=${find.text('Mise à jour des analyses…').evaluate().length}');
    expect(find.text('40.0 %'), findsOneWidget);
    expect(find.text('80.0 %'), findsNothing);
  });

  testWidgets('reste lisible sur un écran moyen avec libellés complets',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(StatisticsSnapshotView(
      request: Future.value(snapshot(students: 6, average: 12, success: 80)),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Évolution des résultats'), findsOneWidget);
    expect(find.text('Performance par matière'), findsOneWidget);
    expect(find.text('Moyenne générale'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reste lisible sur un écran étroit', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(StatisticsSnapshotView(
      request: Future.value(snapshot(students: 6, average: 12, success: 80)),
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('statistics-evolution-chart')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
