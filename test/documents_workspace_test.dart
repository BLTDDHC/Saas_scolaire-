import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/documents/documents_page.dart';
import 'package:edupro_flutter_web/features/school/documents/document_history.dart';
import 'login_flow_test.dart' as fixtures;

void main() {
  for (final fail in [false, true]) {
    testWidgets(
        fail
            ? 'documents server error has retry, not empty history'
            : 'documents show human periods and hide unavailable models',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'edupro_initialized': 'true'});
      final fallback = fixtures.backendClient();
      final store =
          StoreService(api: ApiClient(client: MockClient((request) async {
        if (request.url.path == '/api/v1/school/documents/overview') {
          final bulletin = {
            'id': 'technical-document-id',
            'type': 'official_results',
            'title': 'technical-title',
            'academicYearId': 'year-active',
            'date': '2026-10-22',
            'status': 'generated',
            'metadata': {
              'documentKind': 'bulletin',
              'periodId': 'period-secret-id',
              'periodName': '1er trimestre'
            },
          };
          final receipt = {
            'id': 'DOC_RECEIPT_test',
            'type': 'payment_receipt',
            'title': 'Mensualité octobre',
            'entityId': 'receipt-test',
            'academicYearId': 'year-active',
            'date': '2026-10-23',
            'status': 'generated',
            'studentName': 'BOUAKO Leader',
            'className': 'CM2 A',
            'metadata': {'documentKind': 'receipt', 'receiptId': 'receipt-test'}
          };
          return http.Response(
              jsonEncode(fail
                  ? {'detail': 'Unavailable'}
                  : {
                      'Bulletins': {
                        'items': [bulletin],
                        'total': 1,
                      },
                      'Reçus': {
                        'items': [receipt],
                        'total': 1,
                      },
                      'Documents scolaires': {'items': [], 'total': 0},
                      'Documents administratifs': {'items': [], 'total': 0},
                    }),
              fail ? 503 : 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (request.url.path.contains('academic-periods')) {
          return http.Response(
              jsonEncode([
                {'id': 'period-secret-id', 'name': '1er trimestre'}
              ]),
              200,
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
          child: const MaterialApp(home: Scaffold(body: DocumentsPage()))));
      await tester.pumpAndSettle();
      expect(find.text('Préparer un bulletin'), findsOneWidget);
      expect(find.text('Autres modèles — indisponibles'), findsOneWidget);
      if (fail) {
        expect(find.text('Impossible de charger les documents. Réessayez.'),
            findsOneWidget);
        expect(find.text('Réessayer'), findsOneWidget);
      } else {
        expect(find.text('Bulletins (1)'), findsOneWidget);
        expect(find.text('Reçus (1)'), findsOneWidget);
        expect(find.text('Documents scolaires (0)'), findsOneWidget);
        expect(find.text('Documents administratifs (0)'), findsOneWidget);
        await tester.tap(find.text('Bulletins (1)'));
        await tester.pumpAndSettle();
        expect(find.text('Bulletin'), findsOneWidget);
        expect(find.text('1er trimestre'), findsOneWidget);
        expect(find.text('technical-title'), findsNothing);
        expect(find.text('period-secret-id'), findsNothing);
        await tester.tap(find.text('Reçus (1)'));
        await tester.pumpAndSettle();
        expect(find.text('Reçu de paiement'), findsOneWidget);
        expect(find.text('BOUAKO Leader'), findsOneWidget);
        await tester.enterText(
            find.widgetWithText(
                TextField, 'Rechercher un document ou un élève'),
            'absent');
        await tester.pumpAndSettle();
        expect(find.textContaining('Aucun document correspondant'),
            findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tous les bulletins filtre côté serveur et revient à la page 1',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'edupro_initialized': 'true'});
    final queries = <Map<String, String>>[];
    final fallback = fixtures.backendClient();
    final store =
        StoreService(api: ApiClient(client: MockClient((request) async {
      if (request.url.path == '/api/v1/school/documents/history') {
        queries.add(request.url.queryParameters);
        final page =
            int.tryParse(request.url.queryParameters['page'] ?? '') ?? 1;
        return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'bulletin-$page',
                  'type': 'official_results',
                  'title': 'Bulletin page $page',
                  'date': '2026-09-14',
                  'studentName': 'BOUAKO Leader',
                  'status': 'generated',
                  'metadata': {
                    'documentKind': 'bulletin',
                    'studentId': 'student-1',
                    'periodId': 'period-1',
                  },
                }
              ],
              'page': page,
              'pageSize': 100,
              'pageCount': 2,
              'total': 101,
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
    expect(await store.login(fixtures.email, fixtures.validPassword), true);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child:
          const MaterialApp(home: DocumentCategoryPage(category: 'Bulletins')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Année scolaire'), findsOneWidget);
    expect(find.text('Cycle'), findsOneWidget);
    expect(find.text('Niveau'), findsOneWidget);
    expect(find.text('Classe'), findsOneWidget);
    expect(find.text('Mois de génération'), findsOneWidget);
    expect(find.text('Nom'), findsOneWidget);
    expect(find.text('Prénom'), findsOneWidget);
    expect(find.text('Matricule'), findsOneWidget);
    expect(queries.single['page_size'], '100');
    expect(queries.single['page'], '1');
    expect(find.byTooltip('Actions du document'), findsOneWidget);

    await tester.tap(find.text('Suivante'));
    await tester.pumpAndSettle();
    expect(queries.last['page'], '2');

    final callsBeforeTyping = queries.length;
    await tester.enterText(
        find.widgetWithText(TextField, 'Matricule'), 'MAT-9');
    await tester.pump(const Duration(milliseconds: 399));
    expect(queries.length, callsBeforeTyping);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(queries.last['page'], '1');
    expect(queries.last['matricule'], 'MAT-9');

    await tester.tap(find.text('Réinitialiser les filtres'));
    await tester.pumpAndSettle();
    expect(queries.last['page'], '1');
    expect(queries.last.containsKey('matricule'), isFalse);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.text('Filtrer les bulletins'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tous les reçus combine les filtres côté serveur',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'edupro_initialized': 'true'});
    final queries = <Map<String, String>>[];
    final fallback = fixtures.backendClient();
    final store =
        StoreService(api: ApiClient(client: MockClient((request) async {
      if (request.url.path == '/api/v1/school/documents/history') {
        queries.add(request.url.queryParameters);
        return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'receipt-1',
                  'type': 'payment_receipt',
                  'title': 'Paiement mensuel novembre',
                  'date': '2026-11-14',
                  'studentName': 'BOUAKO Leader',
                  'className': 'CM2 A',
                  'matricule': 'MAT-9',
                  'nature': 'tuition',
                  'status': 'generated',
                  'metadata': {
                    'documentKind': 'receipt',
                    'receiptId': 'receipt-1',
                  },
                }
              ],
              'page': 1,
              'pageSize': 100,
              'pageCount': 1,
              'total': 1,
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
    expect(await store.login(fixtures.email, fixtures.validPassword), true);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: const MaterialApp(home: DocumentCategoryPage(category: 'Reçus')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Filtrer les reçus'), findsOneWidget);
    expect(find.text('Nature'), findsOneWidget);
    expect(find.text('Classe'), findsOneWidget);
    expect(find.text('Nom'), findsOneWidget);
    expect(find.text('Prénom'), findsOneWidget);
    expect(find.text('Matricule'), findsOneWidget);
    expect(queries.single['page_size'], '100');
    expect(find.byTooltip('Actions du document'), findsOneWidget);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Toutes les natures'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paiement mensuel').last);
    await tester.pumpAndSettle();
    expect(queries.last['nature'], 'tuition');

    await tester.enterText(find.widgetWithText(TextField, 'Nom'), 'BOUAKO');
    await tester.enterText(find.widgetWithText(TextField, 'Prénom'), 'Leader');
    await tester.enterText(find.widgetWithText(TextField, 'Matricule'), 'MAT-9');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(queries.last['page'], '1');
    expect(queries.last['last_name'], 'BOUAKO');
    expect(queries.last['first_name'], 'Leader');
    expect(queries.last['matricule'], 'MAT-9');

    await tester.tap(find.text('Réinitialiser les filtres'));
    await tester.pumpAndSettle();
    expect(queries.last.containsKey('nature'), isFalse);
    expect(queries.last.containsKey('matricule'), isFalse);
  });
}
