import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Stockage local via SharedPreferences — reproduction du localStorage préfixé `edupro_`
class LocalStorageSource {
  static const String prefix = 'edupro_';
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Sauvegarder un objet/tableau JSON
  Future<bool> set(String key, dynamic value) async {
    await init();
    try {
      final jsonString = jsonEncode(value);
      return await _prefs!.setString('$prefix$key', jsonString);
    } catch (e) {
      return false;
    }
  }

  /// Récupérer une valeur décodée
  dynamic get(String key) {
    if (_prefs == null) return null;
    try {
      final jsonString = _prefs!.getString('$prefix$key');
      if (jsonString == null || jsonString.isEmpty) return null;
      return jsonDecode(jsonString);
    } catch (e) {
      return null;
    }
  }

  /// Supprimer une clé
  Future<bool> remove(String key) async {
    await init();
    return await _prefs!.remove('$prefix$key');
  }

  /// Réinitialiser toutes les données préfixées `edupro_`
  Future<void> clearAll() async {
    await init();
    final keys = _prefs!.getKeys();
    for (final key in keys) {
      if (key.startsWith(prefix)) {
        await _prefs!.remove(key);
      }
    }
  }

  /// Vérifie si le store est initialisé
  bool isInitialized() {
    return get('initialized') == true;
  }
}
