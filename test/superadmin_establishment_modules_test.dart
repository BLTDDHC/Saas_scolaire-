import 'package:edupro_flutter_web/features/superadmin/establishment_modules_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const catalog = <Map<String, dynamic>>[
  {'id': 'students', 'label': 'Élèves'},
  {'id': 'teachers', 'label': 'Enseignants'},
  {'id': 'grades', 'label': 'Notes & Évaluations'},
];

Map<String, dynamic> response([List<String> enabled = const []]) => {
      'establishment': {
        'id': 'school-test',
        'name': 'École Test',
        'status': 'active',
      },
      'availableModules': catalog,
      'currentPlan': {'id': 'plan-pro', 'name': 'PRO', 'status': 'active'},
      'planFeatures': ['students', 'teachers', 'grades'],
      'enabledModules': enabled,
    };

Widget app({
  required ModulesLoader loader,
  required ModulesSaver saver,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: EstablishmentModulesDialog(
            establishmentId: 'school-test',
            establishmentName: 'École Test',
            loader: loader,
            saver: saver,
          ),
        ),
      ),
    );

void main() {
  testWidgets('loads backend catalog and persisted selections', (tester) async {
    await tester.pumpWidget(app(
      loader: (_) async => response(['students']),
      saver: (_, enabled) async => response(enabled),
    ));
    expect(find.byKey(const Key('modules-loading')), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('Élèves'), findsOneWidget);
    expect(find.text('Enseignants'), findsOneWidget);
    expect(find.text('Plan actuel : PRO'), findsOneWidget);
    expect(
        find.text('Élèves, Enseignants, Notes & Évaluations'), findsOneWidget);
    expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('module-students')))
            .value,
        isTrue);
    expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('module-teachers')))
            .value,
        isFalse);
  });

  testWidgets('activation is persisted and confirmed by backend response',
      (tester) async {
    List<String>? sent;
    await tester.pumpWidget(app(
      loader: (_) async => response(),
      saver: (_, enabled) async {
        sent = List<String>.from(enabled);
        return response(enabled);
      },
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('module-teachers')));
    await tester.tap(find.byKey(const Key('modules-save')));
    await tester.pumpAndSettle();

    expect(sent, ['teachers']);
    expect(find.byKey(const Key('modules-save-success')), findsOneWidget);
    expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('module-teachers')))
            .value,
        isTrue);
  });

  testWidgets('deactivation requires confirmation before persistence',
      (tester) async {
    var saveCalls = 0;
    await tester.pumpWidget(app(
      loader: (_) async => response(['students', 'grades']),
      saver: (_, enabled) async {
        saveCalls++;
        return response(enabled);
      },
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('module-grades')));
    await tester.tap(find.byKey(const Key('modules-save')));
    await tester.pumpAndSettle();
    expect(find.text('Désactiver des modules'), findsOneWidget);
    expect(saveCalls, 0);

    await tester.tap(find.text('Désactiver'));
    await tester.pumpAndSettle();
    expect(saveCalls, 1);
    expect(find.byKey(const Key('modules-save-success')), findsOneWidget);
  });

  testWidgets('backend failure never shows a false success', (tester) async {
    await tester.pumpWidget(app(
      loader: (_) async => response(),
      saver: (_, __) async => throw Exception('validation'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('module-students')));
    await tester.tap(find.byKey(const Key('modules-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('modules-save-error')), findsOneWidget);
    expect(find.byKey(const Key('modules-save-success')), findsNothing);
  });

  testWidgets('load error has a working retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(app(
      loader: (_) async {
        calls++;
        if (calls == 1) throw Exception('network');
        return response(['students']);
      },
      saver: (_, enabled) async => response(enabled),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('modules-error')), findsOneWidget);

    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Élèves'), findsOneWidget);
  });

  testWidgets('empty backend catalog is explicit', (tester) async {
    await tester.pumpWidget(app(
      loader: (_) async => {
        'availableModules': <Map<String, dynamic>>[],
        'enabledModules': <String>[],
      },
      saver: (_, enabled) async => response(enabled),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('modules-empty')), findsOneWidget);
  });
}
