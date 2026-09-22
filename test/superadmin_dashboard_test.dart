import 'dart:async';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/superadmin/superadmin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

Map<String, dynamic> dashboard(
        {List<Map<String, dynamic>> recent = const []}) =>
    {
      'establishments': {
        'total': 5,
        'active': 4,
        'suspended': 1,
        'recent': recent,
      },
      'subscriptions': {
        'total': 4,
        'active': 1,
        'upcoming': 1,
        'overdue': 1,
        'expired': 1,
        'activeAmountTotal': 74900,
      },
      'users': {'total': 10, 'admins': 6},
    };

StoreService testStore() => StoreService(
      api: ApiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/superadmin/establishments') {
            return http.Response('[]', 200);
          }
          if (request.url.path == '/api/v1/superadmin/subscriptions') {
            return http.Response(
              '{"items":[],"summary":{},"expirationAutomatic":false}',
              200,
            );
          }
          return http.Response('{"detail":"Not Found"}', 404);
        }),
      ),
    );

Widget app(
        StoreService store, Future<Map<String, dynamic>> Function() loader) =>
    ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        home: SuperAdminDashboard(dashboardLoader: loader),
      ),
    );

void main() {
  testWidgets('loading does not expose temporary zero KPIs', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(app(testStore(), () => pending.future));
    await tester.pump();

    expect(
        find.byKey(const Key('superadmin-dashboard-loading')), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.text('Revenus Est. Mensuels'), findsNothing);
  });

  testWidgets('success renders only the canonical backend contract',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(
      testStore(),
      () async => dashboard(recent: const [
        {
          'id': 'school_real',
          'name': 'Établissement PostgreSQL',
          'status': 'active',
          'createdAt': '2026-08-23T08:00:00Z',
          'type': 'Lycée',
          'city': 'Oyo',
          'plan': 'standard',
        }
      ]),
    ));
    await tester.pumpAndSettle();

    for (final label in [
      'Établissements actifs',
      'Établissements suspendus',
      'Utilisateurs',
      'Administrateurs scolaires',
      'Abonnements actifs',
      'À venir',
      'En retard',
      'Expirés',
      'Valeur des abonnements actifs',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('74900 FCFA'), findsOneWidget);
    expect(find.text('Établissement PostgreSQL'), findsOneWidget);
    expect(find.text('Revenus Est. Mensuels'), findsNothing);
    expect(find.text('Élèves & Étudiants'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error clears data and retry can reach explicit empty state',
      (tester) async {
    var calls = 0;
    Future<Map<String, dynamic>> loader() async {
      calls++;
      if (calls == 1) throw Exception('backend unavailable');
      return dashboard();
    }

    await tester.pumpWidget(app(testStore(), loader));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('superadmin-dashboard-error')), findsOneWidget);
    expect(find.text('74900 FCFA'), findsNothing);

    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Aucun établissement récent'), findsOneWidget);
    expect(find.byKey(const Key('superadmin-dashboard-error')), findsNothing);
  });

  testWidgets('sidebar uses the canonical Super Admin navigation labels',
      (tester) async {
    await tester.pumpWidget(app(testStore(), () async => dashboard()));
    await tester.pumpAndSettle();

    expect(find.text('Tableau de bord'), findsOneWidget);
    expect(find.text('Établissements'), findsWidgets);
    expect(find.text('Administrateurs'), findsOneWidget);
    expect(find.text('Plans & Offres'), findsOneWidget);
    expect(find.text('Abonnements'), findsWidgets);
  });
}
