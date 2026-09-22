import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/repositories/school_repository.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/auth/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const testEmail = String.fromEnvironment('TEST_LOGIN_EMAIL');
const testPassword = String.fromEnvironment('TEST_LOGIN_PASSWORD');
const hasLiveCredentials = testEmail != '' && testPassword != '';
const missingCredentialsReason =
    'TEST_LOGIN_EMAIL and TEST_LOGIN_PASSWORD are required for live tests';

class CurlClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().bytesToString();
    final arguments = <String>[
      '-sS',
      '-X',
      request.method,
      for (final header in request.headers.entries) ...[
        '-H',
        '${header.key}: ${header.value}'
      ],
      if (body.isNotEmpty) ...['--data-binary', body],
      '-w',
      '\n%{http_code}',
      request.url.toString(),
    ];
    final result = await Process.run('curl.exe', arguments);
    if (result.exitCode != 0) {
      throw http.ClientException(result.stderr.toString().trim(), request.url);
    }
    final output = result.stdout.toString();
    final split = output.lastIndexOf('\n');
    final responseBody = output.substring(0, split);
    final statusCode = int.parse(output.substring(split + 1).trim());
    return http.StreamedResponse(
      Stream.value(utf8.encode(responseBody)),
      statusCode,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }
}

void requireCredentials() {
  expect(testEmail, isNotEmpty, reason: 'TEST_LOGIN_EMAIL must be provided');
  expect(testPassword, isNotEmpty,
      reason: 'TEST_LOGIN_PASSWORD must be provided');
}

Future<StoreService> freshStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = StoreService(api: ApiClient(client: CurlClient()));
  await store.init();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('live backend', () {
    test('ApiClient and SchoolRepository use the real FastAPI login', () async {
      requireCredentials();
      final api = ApiClient(client: CurlClient());
      final valid =
          Map<String, dynamic>.from(await api.post('/api/v1/auth/login', {
        'email': testEmail,
        'password': testPassword,
      }));
      expect(valid['accessToken'], isA<String>());
      final user = Map<String, dynamic>.from(valid['user'] as Map);
      expect(user['email'], testEmail);
      expect(user['role'], 'admin');
      expect(
          user.keys.where((key) => key == 'password' || key == 'passwordHash'),
          isEmpty);

      await expectLater(
        api.post('/api/v1/auth/login',
            {'email': testEmail, 'password': 'MauvaisMotDePasse123!'}),
        throwsA(isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)),
      );
      await expectLater(
        api.post('/api/v1/auth/login', {
          'email': 'missing.login.test@edupro.local',
          'password': 'MauvaisMotDePasse123!',
        }),
        throwsA(isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)),
      );

      final repository = SchoolRepository(ApiClient(client: CurlClient()));
      final repositoryLogin = await repository.login(testEmail, testPassword);
      expect(repositoryLogin['accessToken'], isA<String>());
    }, skip: hasLiveCredentials ? false : missingCredentialsReason);

    test('StoreService saves and restores the real backend session', () async {
      requireCredentials();
      final store = await freshStore();
      expect(await store.login(testEmail, testPassword), isTrue);
      expect(store.currentUser?.email, testEmail);
      expect(store.currentUser?.role.value, 'admin');

      final preferences = await SharedPreferences.getInstance();
      final savedUser = Map<String, dynamic>.from(
        jsonDecode(preferences.getString('edupro_currentUser')!),
      );
      expect(preferences.getString('edupro_accessToken'), isNotNull);
      expect(
          savedUser.keys
              .where((key) => key == 'password' || key == 'passwordHash'),
          isEmpty);

      final restored = StoreService(api: ApiClient(client: CurlClient()));
      await restored.init();
      expect(restored.isAuthenticated, isTrue);
      expect(restored.currentUser?.email, testEmail);
    }, skip: hasLiveCredentials ? false : missingCredentialsReason);
  });

  testWidgets('stopped backend leaves LoginPage usable and unauthenticated',
      (tester) async {
    requireCredentials();
    final store = await freshStore();
    await tester.pumpWidget(
      ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), testEmail);
    await tester.enterText(fields.at(1), testPassword);
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle().timeout(const Duration(seconds: 20));
    expect(store.isAuthenticated, isFalse);
    expect(
        find.text('Email ou mot de passe incorrect, ou serveur indisponible.'),
        findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
  }, skip: !hasLiveCredentials);
}
