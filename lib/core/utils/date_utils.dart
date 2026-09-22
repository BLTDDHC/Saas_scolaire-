import 'package:intl/intl.dart' show DateFormat;

/// Utilitaires de date — formatage FR comme dans le prototype JS
class AppDateUtils {
  AppDateUtils._();

  /// Format utilisateur uniforme : '05-09-2026'.
  static String formatNumeric(String? dateStr, {String fallback = '—'}) {
    final date = parse(dateStr);
    return date == null ? fallback : DateFormat('dd-MM-yyyy').format(date);
  }

  static String formatDate(DateTime? date, {String fallback = '—'}) {
    return date == null ? fallback : DateFormat('dd-MM-yyyy').format(date);
  }

  static DateTime? parse(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty || dateStr == '—') {
      return null;
    }
    final value = dateStr.trim();
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso;
    for (final pattern in const ['dd-MM-yyyy', 'dd/MM/yyyy']) {
      try {
        return DateFormat(pattern).parseStrict(value);
      } catch (_) {
        // Essaie le prochain format utilisateur connu.
      }
    }
    return null;
  }

  /// Parse uniquement une saisie utilisateur au format JJ-MM-AAAA.
  static DateTime? parseUserInputStrict(String? value) {
    final input = value?.trim() ?? '';
    if (!RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(input)) return null;
    try {
      final parsed = DateFormat('dd-MM-yyyy').parseStrict(input);
      return DateFormat('dd-MM-yyyy').format(parsed) == input ? parsed : null;
    } catch (_) {
      return null;
    }
  }

  /// Alias historique conservé, avec le format utilisateur officiel.
  static String formatShort(String? dateStr) {
    return formatNumeric(dateStr);
  }

  /// Alias historique conservé, avec le format utilisateur officiel.
  static String formatLong(String? dateStr) {
    return formatNumeric(dateStr);
  }

  /// Format ISO : '2026-01-15'
  static String toIso(DateTime date) {
    return date.toIso8601String().split('T')[0];
  }

  /// Date du jour en ISO
  static String todayIso() => toIso(DateTime.now());

  /// Dans un an en ISO (pour les abonnements)
  static String oneYearFromNow() {
    final future = DateTime.now().add(const Duration(days: 365));
    return toIso(future);
  }

  /// Année scolaire courante : '2026-2027'
  static String currentAcademicYearName() {
    final now = DateTime.now();
    final startYear = now.month >= 9 ? now.year : now.year - 1;
    return '$startYear-${startYear + 1}';
  }
}
