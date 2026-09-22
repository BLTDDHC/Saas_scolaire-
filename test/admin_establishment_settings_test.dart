import 'dart:async';
import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> establishment({String phone = '067216193'}) => {
      'id': 'school_003',
      'name': 'Lycée majorant',
      'type': 'Lycée',
      'institutionType': 'high_school',
      'address': null,
      'city': 'Brazzaville',
      'country': 'Congo',
      'phone': phone,
      'email': 'leader@gmail.com',
      'status': 'active',
      'plan': 'pro',
      'date': '2026-08-21',
      'createdAt': '2026-08-21T20:56:55Z',
    };

Future<Widget> page(MockClient client) async {
  SharedPreferences.setMockInitialValues({});
  final store = StoreService(api: ApiClient(client: client));
  await store.init();
  return ChangeNotifierProvider.value(
    value: store,
    child: const MaterialApp(home: Scaffold(body: SettingsPage())),
  );
}

void main() {
  testWidgets('affiche le chargement initial', (tester) async {
    final pending = Completer<http.Response>();
    await tester.pumpWidget(await page(MockClient((_) => pending.future)));
    expect(find.byKey(const Key('establishment-loading')), findsOneWidget);
    pending.complete(http.Response(jsonEncode(establishment()), 200));
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets(
      'affiche les données réelles puis sauvegarde après confirmation API',
      (tester) async {
    var putCalls = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET')
        return http.Response(jsonEncode(establishment()), 200);
      if (request.method == 'PUT') {
        putCalls++;
        final body = Map<String, dynamic>.from(jsonDecode(request.body));
        expect(body.keys.toSet(), {'address', 'country', 'phone', 'email'});
        expect(body['phone'], '+242 06 721 61 93');
        return http.Response(
            jsonEncode(establishment(phone: body['phone'])), 200);
      }
      return http.Response('{}', 404);
    });
    await tester.pumpWidget(await page(client));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Lycée majorant'), findsOneWidget);

    await tester.ensureVisible(find.text('Modifier les coordonnées'));
    await tester.tap(find.text('Modifier les coordonnées'));
    await tester.pump();
    await tester.enterText(
        find.byType(TextFormField).at(5), '+242 06 721 61 93');
    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.tap(find.text('Enregistrer'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(putCalls, 1);
    expect(find.text('Informations de l’établissement enregistrées.'),
        findsOneWidget);
    expect(find.text('Modifier les coordonnées'), findsOneWidget);
  });

  testWidgets('bloque un formulaire invalide sans appel API', (tester) async {
    var putCalls = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET')
        return http.Response(jsonEncode(establishment()), 200);
      putCalls++;
      return http.Response('{}', 200);
    });
    await tester.pumpWidget(await page(client));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.text('Modifier les coordonnées'));
    await tester.tap(find.text('Modifier les coordonnées'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).at(6), 'email-invalide');
    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(find.text('Adresse e-mail invalide.'), findsOneWidget);
    expect(putCalls, 0);
  });

  testWidgets('une erreur backend ne produit aucun faux succès',
      (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET')
        return http.Response(jsonEncode(establishment()), 200);
      return http.Response(jsonEncode({'detail': 'Écriture refusée'}), 500);
    });
    await tester.pumpWidget(await page(client));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.text('Modifier les coordonnées'));
    await tester.tap(find.text('Modifier les coordonnées'));
    await tester.pump();
    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.tap(find.text('Enregistrer'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Écriture refusée'), findsOneWidget);
    expect(find.text('Informations de l’établissement enregistrées.'),
        findsNothing);
    expect(find.text('Enregistrer'), findsOneWidget);
  });

  testWidgets('affiche une erreur de chargement avec nouvelle tentative',
      (tester) async {
    final client = MockClient((_) async =>
        http.Response(jsonEncode({'detail': 'Indisponible'}), 500));
    await tester.pumpWidget(await page(client));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        find.text('Impossible de charger les informations de l’établissement.'),
        findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });
}
