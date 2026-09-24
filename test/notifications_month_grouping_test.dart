import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/notifications/notifications_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('notifications are grouped by real month and newest first',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/notifications') {
        return http.Response(
          jsonEncode([
            {
              'id': 'aug-1',
              'title': 'Août ancien',
              'message': 'Ancienne information',
              'type': 'information',
              'read': true,
              'time': '2026-08-31T10:00:00Z',
            },
            {
              'id': 'sep-older',
              'title': 'Septembre ancien',
              'message': 'Deuxième',
              'type': 'information',
              'read': false,
              'time': '2026-09-02T08:00:00Z',
            },
            {
              'id': 'sep-new',
              'title': 'Septembre récent',
              'message': 'Premier',
              'type': 'information',
              'read': false,
              'time': '2026-09-24T11:00:00Z',
            },
          ]),
          200,
        );
      }
      if (request.url.path.contains('/read')) {
        return http.Response('', 204);
      }
      return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
    });
    final store = StoreService(api: ApiClient(client: client));
    await store.init();

    await tester.pumpWidget(
      ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const MaterialApp(
          home: Scaffold(body: NotificationsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('notification-month-Septembre 2026')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('notification-month-Août 2026')),
      findsOneWidget,
    );
    expect(find.text('Septembre récent'), findsOneWidget);
    expect(find.text('Septembre ancien'), findsOneWidget);
    expect(find.text('Août ancien'), findsOneWidget);

    final recentY = tester.getTopLeft(find.text('Septembre récent')).dy;
    final olderY = tester.getTopLeft(find.text('Septembre ancien')).dy;
    final augustY = tester.getTopLeft(find.text('Août ancien')).dy;
    expect(recentY, lessThan(olderY));
    expect(olderY, lessThan(augustY));
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification groups stay readable on narrow screens',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/notifications') {
        return http.Response(
          jsonEncode([
            {
              'id': 'narrow-1',
              'title':
                  'Information administrative dont le titre est volontairement long',
              'message':
                  'Le message reste lisible et peut passer sur plusieurs lignes.',
              'type': 'teacher_announcement',
              'read': false,
              'time': '2026-09-24T11:00:00Z',
            },
          ]),
          200,
        );
      }
      return http.Response('', 204);
    });
    final store = StoreService(api: ApiClient(client: client));
    await store.init();

    await tester.pumpWidget(
      ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const MaterialApp(
          home: Scaffold(body: NotificationsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Septembre 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
