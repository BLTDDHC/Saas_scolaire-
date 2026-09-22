import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/models/establishment_model.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'appelle la route dédiée et ne sauvegarde pas le mot de passe temporaire',
      () async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
          request.url.path, '/api/v1/superadmin/users/admin-id/reset-password');
      expect(jsonDecode(request.body), isEmpty);
      return http.Response(
          jsonEncode({'temporaryPassword': 'temporaire-test-unique'}), 200);
    });
    final store = StoreService(api: ApiClient(client: client));
    await store.init();

    final password = await store.resetAdminPassword('admin-id');
    expect(password, 'temporaire-test-unique');

    final preferences = await SharedPreferences.getInstance();
    expect(
        preferences
            .getKeys()
            .any((key) => key.toLowerCase().contains('password')),
        isFalse);
    expect(
        preferences
            .getKeys()
            .any((key) => preferences.get(key).toString().contains(password)),
        isFalse);
  });

  test('propage un refus backend sans fabriquer de mot de passe', () async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((_) async =>
        http.Response(jsonEncode({'detail': 'Permission insuffisante'}), 403));
    final store = StoreService(api: ApiClient(client: client));
    await store.init();
    await expectLater(
        store.resetAdminPassword('admin-id'), throwsA(isA<ApiException>()));
  });

  test(
      'conserve l identifiant réel de l administrateur dans le modèle établissement',
      () {
    final establishment = EstablishmentModel.fromJson({
      'id': 'school_006',
      'name': 'Lycée d’Oyo',
      'type': 'Lycée',
      'institutionType': 'high_school',
      'administrator': {
        'id': 'admin-id',
        'name': 'Admin',
        'email': 'admin@example.com'
      },
    });
    expect(establishment.administrator?.id, 'admin-id');
  });
}
