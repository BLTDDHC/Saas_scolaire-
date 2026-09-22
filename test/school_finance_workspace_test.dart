import 'dart:convert';
import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/finance/finance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_flow_test.dart' as fixtures;

void main() {
  for (final scenario in [(false, 1600.0), (true, 1600.0), (false, 520.0)]) {
    final (unavailable, width) = scenario;
    testWidgets(
        width < 700
            ? 'financial overview fits a narrow window'
            : unavailable
                ? 'server error never becomes a zero financial summary'
                : 'school roster payment receipt without manual finance enrollment',
        (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'edupro_initialized': 'true'});
      final fallback = fixtures.backendClient();
      var paid = 0;
      Map<String, dynamic>? payment;
      Map<String, dynamic>? tariff;
      final requests = <String>[];
      final queries = <Map<String, String>>[];
      final receipt = {
        'id': 'receipt',
        'paymentId': 'payment',
        'receiptNumber': 'REC-TEST',
        'totalPaid': 4000,
        'remaining': 6000,
        'studentName': 'BOUAKO Leader',
        'amount': 4000,
        'label': "Frais du mois d'octobre",
        'status': 'active',
        'schoolName': 'École',
        'className': '3e A',
        'date': '2026-10-01'
      };
      final store =
          StoreService(api: ApiClient(client: MockClient((request) async {
        requests.add(request.url.path);
        if (request.url.path.endsWith('/finance/roster')) {
          queries.add(request.url.queryParameters);
          if (unavailable)
            return http.Response(
                jsonEncode({'detail': 'Résumé indisponible'}), 503);
          return http.Response(
              jsonEncode({
                'students': [
                  {
                    'registrationId': 'reg',
                    'studentId': 'student',
                    'lastName': 'BOUAKO',
                    'firstName': 'Leader',
                    'studentName': 'BOUAKO Leader',
                    'className': '3e A',
                    'classId': 'class',
                    'type': 'tuition',
                    'month': '2026-10',
                    'label': "Frais du mois d'octobre",
                    'expected': 10000,
                    'paid': paid,
                    'remaining': 10000 - paid,
                    'status': paid == 0 ? 'unpaid' : 'partial'
                  }
                ],
                'classes': [
                  {
                    'id': 'class',
                    'name': '3e A',
                    'levelId': 'level',
                    'levelName': '3e'
                  }
                ],
                'fees': [],
                'receipts': paid > 0 ? [receipt] : [],
                'budget': {
                  'registrationCount': 1,
                  'months': ['2026-10'],
                  'counts': {
                    'paid': 17,
                    'partial': 23,
                    'unpaid': 31,
                    'unconfigured': 0
                  },
                  'summary': {
                    'expected': 110000,
                    'paid': paid,
                    'remaining': 110000 - paid
                  },
                  'breakdown': [
                    {
                      'label': 'Frais mensuels',
                      'expected': 110000,
                      'paid': paid,
                      'remaining': 110000 - paid
                    }
                  ]
                },
                'summary': {
                  'expected': 10000,
                  'paid': paid,
                  'remaining': 10000 - paid
                },
                'unconfiguredCount': 0
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (request.url.path.endsWith('/finance/school-payments')) {
          payment = Map<String, dynamic>.from(jsonDecode(request.body));
          paid = 4000;
          return http.Response(
              jsonEncode({
                'receipt': receipt,
                'balance': {
                  'paid': 4000,
                  'remaining': 6000,
                  'status': 'partial'
                }
              }),
              201);
        }
        if (request.url.path.contains('/finance/monthly-situation/')) {
          return http.Response(
              jsonEncode({
                'registrationId': 'reg',
                'studentId': 'student',
                'studentName': 'BOUAKO Leader',
                'lastName': 'BOUAKO',
                'firstName': 'Leader',
                'matricule': 'KHE26-001',
                'classId': 'class',
                'className': '3e A',
                'months': [
                  {
                    'month': '2026-10',
                    'expected': 10000,
                    'paid': 0,
                    'remaining': 10000,
                    'status': 'unpaid'
                  },
                  {
                    'month': '2026-11',
                    'expected': 10000,
                    'paid': 0,
                    'remaining': 10000,
                    'status': 'unpaid'
                  },
                ]
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (request.url.path.endsWith('/finance/fees')) {
          tariff = Map<String, dynamic>.from(jsonDecode(request.body));
          return http.Response(
              jsonEncode({
                'fee': {'id': 'fee', ...tariff!},
                'assignments': []
              }),
              201);
        }
        if (request.url.path.endsWith('/finance/receipts/receipt')) {
          return http.Response(jsonEncode(receipt), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        final copy = http.Request(request.method, request.url)
          ..headers.addAll(request.headers)
          ..body = request.body;
        return http.Response.fromStream(await fallback.send(copy));
      })));
      await store.init();
      expect(await store.login(fixtures.email, fixtures.validPassword), true);
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: store,
          child: const MaterialApp(home: Scaffold(body: FinancePage()))));
      await tester.pumpAndSettle();
      if (width < 700) {
        expect(find.text('ATTENDU'), findsOneWidget);
        expect(find.text('PAYÉS : 17'), findsOneWidget);
        expect(tester.takeException(), isNull);
        return;
      }
      if (unavailable) {
        expect(find.textContaining('indisponible'), findsWidgets);
        expect(find.text('Encaissé : 0 FCFA'), findsNothing);
      } else {
        expect(find.text('PAYÉS : 17'), findsOneWidget);
        await tester.tap(find.text('Paiement mensuel'));
        await tester.pumpAndSettle();
        expect(find.text('BOUAKO Leader'), findsNothing);
        await tester.tap(
            find.widgetWithText(DropdownButtonFormField<String>, 'Classe'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('3e A').last);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextField, 'Rechercher un élève'),
            findsOneWidget);
        await tester.enterText(
            find.widgetWithText(TextField, 'Rechercher un élève'), 'boua');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(queries.last['search'], 'boua');
        expect(queries.last['class_id'], 'class');
        expect(find.text('BOUAKO Leader'), findsOneWidget);
        expect(find.text('Nouvelle inscription'), findsNothing);
        await tester.tap(find.text('BOUAKO Leader'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('pay-month-button')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Référence'), findsNothing);
        expect(find.byKey(const ValueKey('payment-month-2026-10')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('payment-month-2026-11')),
            findsOneWidget);
        await tester.tap(
            find.byKey(const ValueKey('payment-month-2026-11')));
        await tester.pump();
        await tester.enterText(
            find.widgetWithText(TextField, 'Montant payé (FCFA)'), '15000');
        await tester.tap(find.text('Encaisser'));
        await tester.pump(const Duration(seconds: 1));
        expect(payment?['registrationId'], 'reg');
        expect(payment?['amount'], 15000);
        expect(payment?['months'], containsAll(['2026-10', '2026-11']));
        expect(payment?.containsKey('studentName'), false);
        expect(find.text('Paiement enregistré avec succès'), findsOneWidget);
        await tester.tap(find.text('Fermer'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reçus'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Consulter'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Reçu REC-TEST'), findsOneWidget);
        await tester.tap(find.text('Fermer'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tarifs'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ajouter un tarif'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(
            DropdownButtonFormField<String>, 'Portée du tarif'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Niveau').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('tariff-level')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('3e').last);
        await tester.pumpAndSettle();
        await tester.enterText(
            find.widgetWithText(TextField, 'Libellé du tarif'),
            'Mensualité 3e');
        await tester.enterText(
            find.widgetWithText(TextField, 'Montant officiel (FCFA)'), '12000');
        await tester.tap(find.text('Enregistrer'));
        await tester.pumpAndSettle();
        expect(tariff?['scope'], 'level');
        expect(tariff?['levelId'], 'level');
        expect(tariff?['amount'], 12000);
        await tester.tap(find.text('Vue d’ensemble'));
        await tester.pumpAndSettle();
        expect(find.text(money(110000)), findsWidgets);
        expect(requests.where((p) => p.contains('finance-registrations')),
            isEmpty);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('missing tariffs are never presented as a free zero budget',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'edupro_initialized': 'true'});
    final fallback = fixtures.backendClient();
    final store =
        StoreService(api: ApiClient(client: MockClient((request) async {
      if (request.url.path.endsWith('/finance/roster')) {
        return http.Response(
            jsonEncode({
              'students': [],
              'classes': [
                {
                  'id': 'gs-a',
                  'name': 'Grande Section A',
                  'levelId': 'gs',
                  'levelName': 'Grande Section',
                  'cycleId': 'maternelle',
                  'cycleName': 'Maternelle'
                }
              ],
              'fees': [],
              'receipts': [],
              'budget': {
                'registrationCount': 16,
                'months': ['2026-10'],
                'counts': {
                  'paid': 0,
                  'partial': 0,
                  'unpaid': 0,
                  'unconfigured': 16
                },
                'summary': {
                  'expected': 0,
                  'paid': 0,
                  'remaining': 0,
                  'credit': 0,
                  'unconfiguredCount': 160
                },
                'breakdown': [
                  {
                    'label': 'Inscription',
                    'expected': 0,
                    'paid': 0,
                    'remaining': 0,
                    'unconfiguredCount': 16
                  }
                ]
              },
              'summary': {
                'expected': 0,
                'paid': 0,
                'remaining': 0,
                'credit': 0
              },
              'unconfiguredCount': 16
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      final copy = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..body = request.body;
      return http.Response.fromStream(await fallback.send(copy));
    })));
    await store.init();
    expect(await store.login(fixtures.email, fixtures.validPassword), isTrue);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(home: Scaffold(body: FinancePage()))));
    await tester.pumpAndSettle();

    expect(find.textContaining('Budget non calculable'), findsOneWidget);
    expect(find.text('À CONFIGURER'), findsNWidgets(2));
    expect(find.text('À configurer : 16'), findsOneWidget);
    expect(find.text('16 tarif(s) manquant(s)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
