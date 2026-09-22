import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/documents/document_history.dart';
import 'package:edupro_flutter_web/features/school/grades/student_results_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_flow_test.dart' as fixtures;

Future<StoreService> blockedStore(String blockedPath) async {
  SharedPreferences.setMockInitialValues({'edupro_initialized': 'true'});
  final fallback = fixtures.backendClient();
  final store = StoreService(api: ApiClient(client: MockClient((request) async {
    if (request.url.path == blockedPath) {
      return http.Response(
        jsonEncode({
          'detail':
              'Cette fonctionnalité est disponible dans le forfait Professionnel. Changez de forfait pour l’activer.'
        }),
        403,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..body = request.body;
    return http.Response.fromStream(await fallback.send(copy));
  })));
  await store.init();
  expect(await store.login(fixtures.email, fixtures.validPassword), true);
  return store;
}

void main() {
  testWidgets('résultats bloqués affichent un message commercial sans jargon',
      (tester) async {
    final store = await blockedStore('/api/v1/school/my-results');
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: const MaterialApp(home: StudentResultsPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('forfait Professionnel'), findsOneWidget);
    expect(find.text('Changer de forfait'), findsOneWidget);
    expect(find.textContaining('HTTP 403'), findsNothing);
    expect(find.textContaining('API'), findsNothing);
  });

  testWidgets('historique avancé bloqué propose le changement de forfait',
      (tester) async {
    final store = await blockedStore('/api/v1/school/documents/history');
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child:
          const MaterialApp(home: DocumentCategoryPage(category: 'Bulletins')),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('forfait Professionnel'), findsOneWidget);
    expect(find.text('Changer de forfait'), findsOneWidget);
    expect(find.textContaining('permission'), findsNothing);
  });
}
