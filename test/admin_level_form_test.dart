import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/classes/classes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('ADMIN ajoute un niveau depuis le catalogue standard',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    Map<String, dynamic>? postedLevel;
    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/school/academic-years') {
        return _json([
          {
            'id': 'year-1',
            'schoolId': '',
            'name': '2026-2027',
            'startDate': '2026-10-01',
            'endDate': '2027-06-30',
            'status': 'active',
          }
        ]);
      }
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/school/classes') {
        return _json([]);
      }
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/school/cycles') {
        return _json([
          {
            'id': 'cycle-primary',
            'schoolId': '',
            'code': 'PRIMAIRE',
            'name': 'Primaire',
            'status': 'active',
            'sortOrder': 20,
          }
        ]);
      }
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/school/cycles/cycle-primary/levels') {
        return _json([]);
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/school/cycles/cycle-primary/levels') {
        postedLevel =
            Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        return _json({
          'id': 'level-cm2',
          'schoolId': '',
          'cycleId': 'cycle-primary',
          'cycleCode': 'PRIMAIRE',
          'cycleName': 'Primaire',
          'code': postedLevel!['code'],
          'name': postedLevel!['name'],
          'status': 'active',
          'sortOrder': 0,
        }, status: 201);
      }
      return _json([]);
    });
    final store = StoreService(api: ApiClient(client: client));

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: const MaterialApp(home: Scaffold(body: ClassesPage())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nouveau niveau'));
    await tester.pumpAndSettle();
    expect(find.text('Cycle *'), findsOneWidget);
    expect(find.text('Niveau standard *'), findsOneWidget);
    expect(find.textContaining('catalogue'), findsOneWidget);
    expect(find.textContaining('Code métier'), findsNothing);

    await tester.tap(find.text('CP1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CM2').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();

    expect(postedLevel, {
      'code': 'CM2',
      'name': 'CM2',
      'status': 'active',
    });
    expect(find.text('Nouveau niveau'), findsOneWidget);
  });
}

http.Response _json(Object value, {int status = 200}) => http.Response(
      jsonEncode(value),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
