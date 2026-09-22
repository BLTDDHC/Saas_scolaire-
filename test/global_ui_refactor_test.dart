import 'package:edupro_flutter_web/core/theme/app_theme.dart';
import 'package:edupro_flutter_web/shared/widgets/app_button.dart';
import 'package:edupro_flutter_web/shared/widgets/app_card.dart';
import 'package:edupro_flutter_web/shared/widgets/app_toast.dart';
import 'package:edupro_flutter_web/shared/widgets/responsive_grid.dart';
import 'package:edupro_flutter_web/shared/widgets/workspace_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'le cadre de page commun reste utilisable dans une fenêtre étroite',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: WorkspacePage(
          title: 'Élèves et inscriptions',
          subtitle: 'Retrouvez rapidement le dossier recherché.',
          actions: [
            AppButton(
              label: 'Nouvelle inscription',
              onPressed: () {},
              icon: Icons.person_add_alt_1,
            ),
          ],
          children: const [
            AppCard(child: Text('Contenu métier')),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Élèves et inscriptions'), findsOneWidget);
    expect(find.text('Nouvelle inscription'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('une erreur technique est remplacée par un message humain',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => AppToast.error(
              context,
              'HTTP 500 sur /api/v1/students avec PostgreSQL exception',
            ),
            child: const Text('Déclencher'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Déclencher'));
    await tester.pump();
    expect(find.text('Une erreur est survenue. Veuillez réessayer.'),
        findsOneWidget);
    expect(find.textContaining('/api/'), findsNothing);
  });

  test('le thème commun garde une densité de gestion lisible', () {
    final theme = AppTheme.light();
    expect(theme.dataTableTheme.dataRowMinHeight, 56);
    expect(theme.filledButtonTheme.style, isNotNull);
    expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
  });
  for (final width in <double>[900, 1366, 1440, 1920]) {
    testWidgets('la zone de travail exploite une largeur de $width px',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: WorkspacePage(
            title: 'Tableau de gestion',
            subtitle: 'Validation de la largeur utile.',
            children: [
              AppCard(
                padding: EdgeInsets.zero,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Élève')),
                      DataColumn(label: Text('Classe')),
                    ],
                    rows: const [
                      DataRow(cells: [
                        DataCell(Text('Élève test')),
                        DataCell(Text('Terminale C')),
                      ]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final tableWidth = tester.getSize(find.byType(DataTable)).width;
      expect(tableWidth, greaterThan(width * .78));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('les formulaires passent de trois colonnes à une sans overflow',
      (tester) async {
    Future<void> pumpAt(double width) => tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: const ResponsiveFormGrid(
                maxColumns: 3,
                children: [
                  SizedBox(key: Key('field-a'), height: 48),
                  SizedBox(key: Key('field-b'), height: 48),
                  SizedBox(key: Key('field-c'), height: 48),
                ],
              ),
            ),
          ),
        ));

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpAt(1000);
    expect(tester.getTopLeft(find.byKey(const Key('field-a'))).dy,
        tester.getTopLeft(find.byKey(const Key('field-c'))).dy);

    await pumpAt(390);
    expect(tester.getTopLeft(find.byKey(const Key('field-b'))).dy,
        greaterThan(tester.getTopLeft(find.byKey(const Key('field-a'))).dy));
    expect(tester.takeException(), isNull);
  });
}
