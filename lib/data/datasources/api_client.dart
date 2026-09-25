import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// HTTP client shared by repositories. Configure with --dart-define=API_BASE_URL=...
class ApiClient {
  ApiClient(
      {http.Client? client, Duration timeout = const Duration(seconds: 15)})
      : _client = client ?? http.Client(),
        _timeout = timeout;
  final http.Client _client;
  final Duration _timeout;
  String? _token;
  VoidCallback? onUnauthorized;
  static const _configuredUrl = String.fromEnvironment('API_BASE_URL');
  String get baseUrl {
    if (_configuredUrl.isNotEmpty) {
      return _configuredUrl.replaceAll(RegExp(r'/+$'), '');
    }
    if (kIsWeb) {
      final current = Uri.base;
      final isLocalDevelopment =
          current.host == 'localhost' || current.host == '127.0.0.1';
      // A hosted web build (for example through ngrok) uses the same origin as
      // FastAPI. Local Flutter development keeps the historical backend port.
      return isLocalDevelopment ? 'http://localhost:8000' : current.origin;
    }
    // Mobile/desktop release builds must never fall back to localhost.\n    // Developers can still override this URL with --dart-define=API_BASE_URL=...\n    return 'https://saas-scolaire-staging-api.onrender.com';
  }

  void setToken(String? token) => _token = token;
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        // Évite que la page d'avertissement du tunnel ngrok remplace une
        // réponse JSON pendant les démonstrations temporaires. Les serveurs
        // classiques ignorent simplement cet en-tête.
        'ngrok-skip-browser-warning': 'true',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };
  bool _shouldCloseSession(String path) =>
      path != '/api/v1/auth/login' &&
      path != '/api/v1/auth/change-password';

  Future<dynamic> get(String path) async => _decode(
      await _client
          .get(Uri.parse('$baseUrl$path'), headers: _headers)
          .timeout(_timeout),
      path);
  Future<Uint8List> getBytes(String path) async {
    final response = await _client
        .get(Uri.parse('$baseUrl$path'), headers: _headers)
        .timeout(_timeout);
    if (response.statusCode == 401 && _shouldCloseSession(path)) {
      onUnauthorized?.call();
    }
    if (response.statusCode >= 400) {
      throw ApiException(_message(response), response.statusCode);
    }
    return response.bodyBytes;
  }
  Future<dynamic> post(String path, Map<String, dynamic> body) async =>
      _decode(
          await _client
              .post(Uri.parse('$baseUrl$path'),
                  headers: _headers, body: jsonEncode(body))
              .timeout(_timeout),
          path);
  Future<dynamic> put(String path, Map<String, dynamic> body) async =>
      _decode(
          await _client
              .put(Uri.parse('$baseUrl$path'),
                  headers: _headers, body: jsonEncode(body))
              .timeout(_timeout),
          path);
  Future<void> delete(String path) async {
    final response = await _client
        .delete(Uri.parse('$baseUrl$path'), headers: _headers)
        .timeout(_timeout);
    if (response.statusCode == 401 && _shouldCloseSession(path)) {
      onUnauthorized?.call();
    }
    if (response.statusCode >= 400) {
      throw ApiException(_message(response), response.statusCode);
    }
  }

  dynamic _decode(http.Response response, String path) {
    if (response.statusCode == 401 && _shouldCloseSession(path)) {
      onUnauthorized?.call();
    }
    if (response.statusCode >= 400) {
      throw ApiException(_message(response), response.statusCode);
    }
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }

  String _message(http.Response response) {
    String? detail;
    try {
      final decoded = jsonDecode(response.body);
      final rawDetail = decoded is Map ? decoded['detail'] : null;
      detail = rawDetail is String ? rawDetail.trim() : null;
    } catch (_) {
      detail = null;
    }
    final containsTechnicalDetail = detail != null &&
        RegExp(
          r'\b(http|postgresql|fastapi|sql|endpoint|exception|uuid|backend)\b',
          caseSensitive: false,
        ).hasMatch(detail);
    if (detail != null && detail.isNotEmpty && !containsTechnicalDetail) {
      return detail;
    }
    switch (response.statusCode) {
      case 401:
        return 'Votre session a expiré. Veuillez vous reconnecter.';
      case 403:
        return 'Cette action n’est pas disponible pour votre compte.';
      case 404:
        return 'L’élément demandé est introuvable.';
      case 409:
        return 'Cette action entre en conflit avec une information existante.';
      case 422:
        return 'Vérifiez les informations saisies.';
      default:
        return 'Le service est momentanément indisponible. Réessayez.';
    }
  }
}

class ApiException implements Exception {
  ApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;
  @override
  String toString() => message;
}
