import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/subjects/subjects_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('création Matière envoie uniquement le champ réellement persisté',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    Map<String, dynamic>? posted;
    final store = StoreService(
      api: ApiClient(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/school/subjects') {
            posted = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
            return _json(
                {'id': 'subject-1', 'name': posted!['name'], 'schoolId': ''},
                status: 201);
          }
          return _json([]);
        }),
      ),
    );

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: const MaterialApp(home: Scaffold(body: SubjectsPage())),
    ));
    await tester.tap(find.text('Nouvelle matière'));
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);
    expect(find.descendant(of: dialog, matching: find.text('Coefficient *')),
        findsNothing);
    expect(find.descendant(of: dialog, matching: find.text('Icône (Emoji)')),
        findsNothing);
    expect(find.descendant(of: dialog, matching: find.text('Enseignant')),
        findsNothing);
    expect(
        find.descendant(of: dialog, matching: find.text('Classes associées')),
        findsNothing);
    expect(
      find.textContaining('affectée depuis une classe'),
      findsOneWidget,
    );

    final fields = find.byType(TextField);
    await tester.enterText(
        fields.at(fields.evaluate().length - 1), 'Mathématiques');
    await tester.tap(find.text('Créer la matière'));
    await tester.pumpAndSettle();

    expect(posted, {'name': 'Mathématiques'});
  });
}

http.Response _json(Object value, {int status = 200}) => http.Response(
      jsonEncode(value),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
