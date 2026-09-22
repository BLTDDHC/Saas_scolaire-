import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/auth/change_password_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> get authUser => {
      'id': '10000000-0000-0000-0000-000000000099',
      'name': 'Compte Auth Test',
      'email': 'auth.rollback@example.invalid',
      'role': 'superadmin',
      'roleName': 'superadmin',
      'schoolId': null,
      'status': 'active',
      'passwordSet': true,
      'mustChangePassword': false,
    };

String testJwt({required int expiresAt}) {
  String encode(Object value) =>
      base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({
        'exp': expiresAt
      })}.test-signature';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a 500 from auth me preserves a locally valid unexpired session',
      () async {
    final token = testJwt(
        expiresAt: DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000);
    SharedPreferences.setMockInitialValues({
      'edupro_initialized': jsonEncode(true),
      'edupro_currentUser': jsonEncode(authUser),
      'edupro_accessToken': jsonEncode(token),
    });
    final store = StoreService(
        api: ApiClient(
            client: MockClient((_) async => http.Response(
                jsonEncode({'detail': 'Service temporairement indisponible'}),
                500))));

    await store.init();

    expect(store.isAuthenticated, isTrue);
    expect(store.currentUser?.email, authUser['email']);
    expect(store.sessionWarning, contains('Session conservée'));
    final preferences = await SharedPreferences.getInstance();
    expect(jsonDecode(preferences.getString('edupro_accessToken')!), token);
  });

  test('an expired persisted JWT is removed before opening a workspace',
      () async {
    var serverCalls = 0;
    SharedPreferences.setMockInitialValues({
      'edupro_initialized': jsonEncode(true),
      'edupro_currentUser': jsonEncode(authUser),
      'edupro_accessToken': jsonEncode(testJwt(
        expiresAt: DateTime.now()
                .subtract(const Duration(minutes: 1))
                .millisecondsSinceEpoch ~/
            1000,
      )),
    });
    final store = StoreService(api: ApiClient(client: MockClient((_) async {
      serverCalls++;
      return http.Response(jsonEncode(authUser), 200);
    })));

    await store.init();

    expect(store.isAuthenticated, isFalse);
    expect(serverCalls, 0);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('edupro_accessToken'), isNull);
    expect(preferences.getString('edupro_currentUser'), isNull);
  });

  test('a later 401 immediately closes the local session', () async {
    final token = testJwt(
        expiresAt: DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000);
    SharedPreferences.setMockInitialValues({
      'edupro_initialized': jsonEncode(true),
      'edupro_currentUser': jsonEncode(authUser),
      'edupro_accessToken': jsonEncode(token),
    });
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/me') {
        return http.Response(jsonEncode(authUser), 200);
      }
      if (request.url.path == '/api/v1/bootstrap') {
        return http.Response(jsonEncode(<String, dynamic>{}), 200);
      }
      return http.Response(jsonEncode({'detail': 'Session expirée'}), 401);
    });
    final store = StoreService(api: ApiClient(client: client));
    await store.init();
    expect(store.isAuthenticated, isTrue);

    await expectLater(
      store.scheduleRemote('00000000-0000-0000-0000-000000000001'),
      throwsA(isA<ApiException>()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(store.isAuthenticated, isFalse);
    expect(store.sessionWarning, contains('expiré'));
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('edupro_accessToken'), isNull);
    expect(preferences.getString('edupro_currentUser'), isNull);
  });

  testWidgets('voluntary password change sends current and confirmation once',
      (tester) async {
    const currentPassword = 'Current-password!7';
    const newPassword = 'New-password-secure!8';
    final renewedToken = testJwt(
        expiresAt: DateTime.now()
                .add(const Duration(hours: 8))
                .millisecondsSinceEpoch ~/
            1000);
    var changeCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/change-password') {
        changeCalls++;
        final body = Map<String, dynamic>.from(jsonDecode(request.body));
        expect(body['current_password'], currentPassword);
        expect(body['new_password'], newPassword);
        expect(body['new_password_confirmation'], newPassword);
        return http.Response(
            jsonEncode({'accessToken': renewedToken, 'user': authUser}), 200);
      }
      return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
    });
    SharedPreferences.setMockInitialValues({});
    final store = StoreService(api: ApiClient(client: client));
    await store.init();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showChangePasswordDialog(context),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('current-password')), currentPassword);
    await tester.enterText(find.byKey(const Key('new-password')), newPassword);
    await tester.enterText(
        find.byKey(const Key('new-password-confirmation')), newPassword);
    await tester.tap(find.byKey(const Key('submit-password-change')));
    await tester.pumpAndSettle();

    expect(changeCalls, 1);
    expect(find.text('Votre mot de passe a été modifié.'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(
        jsonDecode(preferences.getString('edupro_accessToken')!), renewedToken);
    final savedUser = jsonDecode(preferences.getString('edupro_currentUser')!)
        as Map<String, dynamic>;
    expect(savedUser.containsKey('password'), isFalse);
    expect(savedUser.containsKey('passwordHash'), isFalse);
  });
}
