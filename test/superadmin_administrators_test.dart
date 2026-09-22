import 'package:edupro_flutter_web/core/constants/establishment_types.dart';
import 'package:edupro_flutter_web/data/models/user_model.dart';
import 'package:edupro_flutter_web/features/superadmin/administrators_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

UserModel admin({
  String id = 'admin-1',
  AccountStatus status = AccountStatus.active,
  bool mustChange = true,
}) =>
    UserModel(
      id: id,
      name: 'Administrateur Réel',
      email: 'admin@ecole.test',
      phone: '+242 06 000 00 00',
      role: UserRole.admin,
      schoolId: 'school-1',
      establishment: 'École PostgreSQL',
      establishmentStatus: 'suspended',
      status: status,
      mustChangePassword: mustChange,
      createdAt: '2026-08-23T08:00:00Z',
    );

Widget app(AdministratorsPage page) => MaterialApp(home: Scaffold(body: page));

void useDesktopSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(2200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('charge la liste réelle et sépare les trois statuts',
      (tester) async {
    useDesktopSize(tester);
    await tester.pumpWidget(app(AdministratorsPage(
      loader: ({search, status, establishmentId}) async => [admin()],
    )));
    await tester.pumpAndSettle();

    expect(find.text('Administrateur Réel'), findsOneWidget);
    expect(find.text('admin@ecole.test'), findsOneWidget);
    expect(find.text('École PostgreSQL'), findsOneWidget);
    expect(find.text('À changer'), findsOneWidget);
    expect(find.text('Suspendu'), findsOneWidget);
    expect(find.byKey(const Key('admins-loading')), findsNothing);
  });

  testWidgets('transmet recherche, statut et établissement au backend',
      (tester) async {
    useDesktopSize(tester);
    String? receivedSearch;
    String? receivedStatus;
    String? receivedSchool;
    await tester.pumpWidget(app(AdministratorsPage(
      loader: ({search, status, establishmentId}) async {
        receivedSearch = search;
        receivedStatus = status;
        receivedSchool = establishmentId;
        return [admin()];
      },
    )));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('admin-search')), 'admin@ecole.test');
    await tester.tap(find.byKey(const Key('admin-search-button')));
    await tester.pumpAndSettle();
    expect(receivedSearch, 'admin@ecole.test');

    await tester.tap(find.byKey(const Key('admin-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Actif').last);
    await tester.pumpAndSettle();
    expect(receivedStatus, 'active');

    await tester.tap(find.byKey(const Key('admin-establishment-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('École PostgreSQL').last);
    await tester.pumpAndSettle();
    expect(receivedSchool, 'school-1');
  });

  testWidgets('affiche un détail sans mot de passe ni hash', (tester) async {
    useDesktopSize(tester);
    await tester.pumpWidget(app(AdministratorsPage(
      loader: ({search, status, establishmentId}) async => [admin()],
      detailLoader: (_) async => admin(),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Consulter'));
    await tester.pumpAndSettle();

    expect(find.text('Détail administrateur'), findsOneWidget);
    expect(find.text('Dernière connexion : non disponible'), findsOneWidget);
    expect(find.textContaining('hash'), findsNothing);
    expect(find.textContaining('password'), findsNothing);
  });

  testWidgets('reset affiche le secret une seule fois et recharge la liste',
      (tester) async {
    useDesktopSize(tester);
    var loads = 0;
    await tester.pumpWidget(app(AdministratorsPage(
      loader: ({search, status, establishmentId}) async {
        loads++;
        return [admin()];
      },
      passwordResetter: (_) async => 'secret-temporaire-unique',
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Réinitialiser le mot de passe'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('temporary-admin-password')), findsOneWidget);
    expect(find.text('secret-temporaire-unique'), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    expect(loads, 2);
  });

  testWidgets('suspension du compte utilise un statut indépendant',
      (tester) async {
    useDesktopSize(tester);
    AccountStatus? received;
    await tester.pumpWidget(app(AdministratorsPage(
      loader: ({search, status, establishmentId}) async => [admin()],
      statusUpdater: (_, status) async {
        received = status;
        return admin(status: status);
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Suspendre le compte'));
    await tester.pumpAndSettle();
    expect(received, AccountStatus.suspended);
  });

  testWidgets('affiche erreur et état vide explicitement', (tester) async {
    useDesktopSize(tester);
    var calls = 0;
    await tester.pumpWidget(app(AdministratorsPage(
      loader: ({search, status, establishmentId}) async {
        calls++;
        if (calls == 1) throw Exception('network');
        return [];
      },
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admins-error')), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admins-empty')), findsOneWidget);
  });
}
