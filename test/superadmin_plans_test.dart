import 'package:edupro_flutter_web/data/models/plan_model.dart';
import 'package:edupro_flutter_web/features/superadmin/plans_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';

const moduleCatalog = <Map<String, dynamic>>[
  {'id': 'students', 'label': 'Élèves'},
  {'id': 'teachers', 'label': 'Enseignants'},
  {'id': 'grades', 'label': 'Notes'},
];

const commercialCatalog = <Map<String, dynamic>>[
  {
    'id': 'students',
    'label': 'Élèves',
    'group': 'Scolarité',
    'capabilities': [
      {
        'id': 'parents.access',
        'label': 'Espace parent',
        'group': 'Parents / Élèves'
      },
      {
        'id': 'students.access',
        'label': 'Espace élève Collège/Lycée',
        'group': 'Parents / Élèves'
      },
    ]
  },
  {
    'id': 'grades',
    'label': 'Notes & Évaluations',
    'group': 'Notes & résultats',
    'capabilities': [
      {
        'id': 'grades.publish_teacher',
        'label': 'Résultats visibles par les enseignants',
        'group': 'Notes & résultats'
      },
      {
        'id': 'grades.publish_parent',
        'label': 'Résultats visibles par les parents',
        'group': 'Notes & résultats'
      },
      {
        'id': 'grades.publish_student',
        'label': 'Résultats visibles par les élèves',
        'group': 'Notes & résultats'
      },
    ]
  },
  {
    'id': 'documents',
    'label': 'Documents',
    'group': 'Documents',
    'capabilities': [
      {
        'id': 'documents.advanced_search',
        'label': 'Historique et recherches avancées',
        'group': 'Documents'
      }
    ]
  },
];

PlanModel plan({String status = 'active', int price = 49900}) => PlanModel(
      id: 'plan-pro',
      name: 'PRO',
      description: 'Offre réelle',
      price: price,
      durationDays: 365,
      currency: 'FCFA',
      status: status,
      features: const ['students', 'grades'],
      limits: const {},
      subscriptionCount: 5,
    );

Widget app(PlansPage page) => MaterialApp(home: Scaffold(body: page));

void desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('affiche les plans sans attendre le catalogue des modules',
      (tester) async {
    desktop(tester);
    final pendingCatalog = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(app(PlansPage(
      loader: () async => [plan()],
      catalogLoader: () => pendingCatalog.future,
    )));
    await tester.pump();
    await tester.pump();

    expect(find.text('PRO'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    pendingCatalog.complete(const []);
    await tester.pump();
  });

  testWidgets('affiche le catalogue réel et le détail', (tester) async {
    desktop(tester);
    await tester.pumpWidget(app(PlansPage(
      loader: () async => [plan()],
      detailLoader: (_) async => plan(),
      catalogLoader: () async => moduleCatalog,
    )));
    await tester.pumpAndSettle();
    expect(find.text('PRO'), findsOneWidget);
    expect(find.text('49900 FCFA'), findsOneWidget);
    expect(find.text('365 jours'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    await tester.tap(find.byTooltip('Consulter'));
    await tester.pumpAndSettle();
    expect(find.text('Abonnements liés : 5'), findsOneWidget);
    expect(find.text('Fonctionnalités : Élèves, Notes'), findsOneWidget);
  });

  testWidgets('crée un plan valide puis recharge la source', (tester) async {
    desktop(tester);
    final plans = <PlanModel>[];
    PlanModel? created;
    await tester.pumpWidget(app(PlansPage(
      loader: () async => plans,
      catalogLoader: () async => moduleCatalog,
      creator: (value) async {
        created = value;
        plans.add(value.copyWith(subscriptionCount: 0));
        return value;
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-plan')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('plan-name')), 'ÉDUCATION');
    await tester.enterText(find.byKey(const Key('plan-price')), '15000');
    await tester.enterText(find.byKey(const Key('plan-duration')), '180');
    expect(find.byKey(const Key('plan-features')), findsNothing);
    await tester.tap(find.byKey(const Key('plan-feature-students')));
    await tester.tap(find.byKey(const Key('plan-feature-teachers')));
    await tester.tap(find.byKey(const Key('plan-save')));
    await tester.pumpAndSettle();
    expect(created?.name, 'ÉDUCATION');
    expect(created?.price, 15000);
    expect(created?.durationDays, 180);
    expect(created?.features, ['students', 'teachers']);
    expect(find.text('ÉDUCATION'), findsOneWidget);
  });

  testWidgets('utilise le catalogue backend sans présélection commerciale Flutter',
      (tester) async {
    desktop(tester);
    final plans = <PlanModel>[];
    PlanModel? created;
    await tester.pumpWidget(app(PlansPage(
      loader: () async => plans,
      catalogLoader: () async => commercialCatalog,
      creator: (value) async {
        created = value;
        plans.add(value);
        return value;
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-plan')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('plan-preset-essential')), findsNothing);
    expect(find.byKey(const Key('plan-preset-professional')), findsNothing);
    expect(find.byKey(const Key('plan-preset-premium')), findsNothing);

    await tester.enterText(find.byKey(const Key('plan-name')), 'PROFESSIONNEL');
    await tester.enterText(find.byKey(const Key('plan-price')), '30000');
    await tester.tap(find.byKey(const Key('plan-feature-students')));
    await tester.tap(find.byKey(const Key('plan-feature-grades')));
    await tester.tap(find.byKey(const Key('plan-feature-documents')));
    await tester.ensureVisible(
        find.byKey(const Key('plan-capability-parents.access')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-capability-parents.access')));
    await tester.ensureVisible(
        find.byKey(const Key('plan-capability-grades.publish_teacher')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const Key('plan-capability-grades.publish_teacher')));
    await tester.ensureVisible(
        find.byKey(const Key('plan-capability-grades.publish_parent')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const Key('plan-capability-grades.publish_parent')));
    await tester.ensureVisible(
        find.byKey(const Key('plan-capability-documents.advanced_search')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const Key('plan-capability-documents.advanced_search')));
    await tester.tap(find.byKey(const Key('plan-save')));
    await tester.pumpAndSettle();

    expect(created?.features, containsAll(['students', 'grades', 'documents']));
    expect(created?.limits['capabilitiesConfigured'], isTrue);
    expect(
        created?.limits['capabilities'],
        containsAll([
          'parents.access',
          'grades.publish_teacher',
          'grades.publish_parent',
          'documents.advanced_search',
        ]));
    expect(created?.limits['capabilities'], isNot(contains('students.access')));
    expect(created?.limits['capabilities'],
        isNot(contains('grades.publish_student')));
  });

  testWidgets('bloque localement prix négatif et durée invalide',
      (tester) async {
    desktop(tester);
    var calls = 0;
    await tester.pumpWidget(app(PlansPage(
      loader: () async => const [],
      catalogLoader: () async => moduleCatalog,
      creator: (value) async {
        calls++;
        return value;
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-plan')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('plan-name')), 'X');
    await tester.enterText(find.byKey(const Key('plan-price')), '-1');
    await tester.enterText(find.byKey(const Key('plan-duration')), '0');
    await tester.tap(find.byKey(const Key('plan-save')));
    await tester.pump();
    expect(find.byKey(const Key('plan-form-error')), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('modifie prix et durée', (tester) async {
    desktop(tester);
    final plans = [plan()];
    PlanModel? updated;
    await tester.pumpWidget(app(PlansPage(
      loader: () async => plans,
      catalogLoader: () async => moduleCatalog,
      updater: (value) async {
        updated = value;
        plans[0] = value;
        return value;
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const Key('plan-feature-students')))
            .value,
        isTrue);
    await tester.enterText(find.byKey(const Key('plan-price')), '55000');
    await tester.enterText(find.byKey(const Key('plan-duration')), '400');
    await tester.tap(find.byKey(const Key('plan-save')));
    await tester.pumpAndSettle();
    expect(updated?.price, 55000);
    expect(updated?.durationDays, 400);
    expect(find.text('55000 FCFA'), findsOneWidget);
  });

  testWidgets('confirme la désactivation sans changer les abonnements',
      (tester) async {
    desktop(tester);
    final plans = [plan()];
    PlanModel? updated;
    await tester.pumpWidget(app(PlansPage(
      loader: () async => plans,
      catalogLoader: () async => moduleCatalog,
      updater: (value) async {
        updated = value;
        plans[0] = value;
        return value;
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Désactiver'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('abonnements existants resteront'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-plan-deactivation')));
    await tester.pumpAndSettle();
    expect(updated?.status, 'inactive');
    expect(updated?.subscriptionCount, 5);
    expect(find.text('Inactif'), findsOneWidget);
  });

  testWidgets('affiche erreur, retry et état vide', (tester) async {
    desktop(tester);
    var calls = 0;
    await tester.pumpWidget(app(PlansPage(
      loader: () async {
        calls++;
        if (calls == 1) throw Exception('network');
        return [];
      },
      catalogLoader: () async => moduleCatalog,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plans-error')), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plans-empty')), findsOneWidget);
  });

  testWidgets('catalogue vide est explicite dans le formulaire',
      (tester) async {
    desktop(tester);
    await tester.pumpWidget(app(PlansPage(
      loader: () async => const [],
      catalogLoader: () async => const [],
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-plan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan-catalog-empty')), findsOneWidget);
  });
}
