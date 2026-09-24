import 'dart:convert';

import 'package:edupro_flutter_web/core/utils/notification_date_utils.dart';
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

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('notification month labels use persisted ISO dates', () {
    expect(notificationMonthLabel('2026-09-24T08:00:00Z'), 'Septembre 2026');
    expect(notificationMonthKey('2026-09-24T08:00:00Z'), '2026-09');
    expect(
      notificationDate('2026-10-01T08:00:00Z')
          .isAfter(notificationDate('2026-09-30T20:00:00Z')),
      isTrue,
    );
  });

  testWidgets('notifications are grouped by month newest first responsively',
      (tester) async {
    tester.view.physicalSize = const Size(420, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/notifications') {
        return http.Response(
            jsonEncode([
              {
                'id': 'n-sep-old',
                'title': 'Ancienne septembre',
                'message': 'Message',
                'type': 'information',
                'read': true,
                'time': '2026-09-02T08:00:00Z',
              },
              {
                'id': 'n-oct',
                'title': 'Octobre récent',
                'message': 'Message',
                'type': 'information',
                'read': false,
                'time': '2026-10-03T10:00:00Z',
              },
              {
                'id': 'n-sep-new',
                'title': 'Septembre récent',
                'message': 'Message',
                'type': 'information',
                'read': false,
                'time': '2026-09-28T10:00:00Z',
              },
            ]),
            200);
      }
      if (request.url.path.endsWith('/read') ||
          request.url.path == '/api/v1/notifications/read-all') {
        return http.Response('', 204);
      }
      return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
    });
    final store = StoreService(api: ApiClient(client: client));
    await store.init();
    await store.refreshWorkflowNotificationsRemote();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(home: Scaffold(body: NotificationsPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Octobre 2026'), findsOneWidget);
    expect(find.text('Septembre 2026'), findsOneWidget);
    expect(find.text('Octobre récent'), findsOneWidget);
    expect(find.text('Septembre récent'), findsOneWidget);
    expect(find.text('Ancienne septembre'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final octoberY = tester.getTopLeft(find.text('Octobre 2026')).dy;
    final septemberY = tester.getTopLeft(find.text('Septembre 2026')).dy;
    expect(octoberY, lessThan(septemberY));
  });
}
