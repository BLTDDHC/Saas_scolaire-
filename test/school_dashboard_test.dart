import 'dart:async';

import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/dashboard/school_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget dashboard(Future<Map<String, dynamic>> Function() loader) {
  return ChangeNotifierProvider(
    create: (_) => StoreService(),
    child: MaterialApp(
        home: Scaffold(body: SchoolDashboard(statisticsLoader: loader))),
  );
}

void main() {
  testWidgets('affiche le chargement tant que les statistiques sont attendues',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(dashboard(() => pending.future));

    expect(
        find.byKey(const Key('dashboard-statistics-loading')), findsOneWidget);
    expect(find.text('96.4%'), findsNothing);
  });

  testWidgets(
      'affiche uniquement les compteurs et le taux fournis par le backend',
      (tester) async {
    await tester.pumpWidget(dashboard(() async => {
          'studentCount': 12,
          'teacherCount': 4,
          'classCount': 3,
          'attendanceRate': 87.5,
        }));
    await tester.pumpAndSettle();

    expect(find.text('12'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('87.5%'), findsOneWidget);
    expect(find.text('96.4%'), findsNothing);
  });

  testWidgets('affiche un état vide si aucun relevé de présence existe',
      (tester) async {
    await tester.pumpWidget(dashboard(() async => {
          'studentCount': 0,
          'teacherCount': 0,
          'classCount': 0,
          'attendanceRate': null,
        }));
    await tester.pumpAndSettle();

    expect(find.text('Aucune donnée'), findsOneWidget);
    expect(find.text('Aucun relevé enregistré'), findsOneWidget);
  });

  testWidgets('affiche une erreur exploitable lorsque l API échoue',
      (tester) async {
    await tester.pumpWidget(
        dashboard(() async => throw Exception('backend indisponible')));
    await tester.pumpAndSettle();

    expect(
        find.text('Impossible de charger les statistiques.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.text('96.4%'), findsNothing);
  });

  testWidgets('signale les classes dont tous les relevés sont arrivés',
      (tester) async {
    await tester.pumpWidget(dashboard(() async => {
          'activeCycleCount': 1,
          'classCount': 1,
          'studentCount': null,
          'teacherCount': null,
          'attendanceRate': null,
          'overallAverage': null,
          'selectedAcademicYear': {'name': '2026-2027'},
          'readyResults': [
            {
              'class': 'Terminale C',
              'period': '1er trimestre',
              'expected': 8,
              'received': 8,
            }
          ],
        }));
    await tester.pumpAndSettle();

    expect(find.text('Résultats prêts à être calculés'), findsOneWidget);
    expect(find.text('Terminale C — 1er trimestre'), findsOneWidget);
    expect(find.text('8/8 relevés reçus'), findsOneWidget);
    expect(find.text('Calculer'), findsOneWidget);
  });
}
