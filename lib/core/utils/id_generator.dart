/// Générateur d'IDs compatible avec le format JS existant
class IdGenerator {
  IdGenerator._();

  static int _counter = 0;

  /// Génère un ID unique avec un préfixe
  /// Ex: IdGenerator.generate('EL') → 'EL042'
  static String generate(String prefix, {int existingCount = 0}) {
    _counter++;
    final num = existingCount + _counter;
    return '$prefix${num.toString().padLeft(3, '0')}';
  }

  /// Génère un ID utilisateur
  /// Ex: 'user_12345'
  static String userId() {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    return 'user_${ts.substring(ts.length - 5)}';
  }

  /// Génère un ID d'établissement
  /// Ex: 'school_001'
  static String schoolId(int nextNum) {
    return 'school_${nextNum.toString().padLeft(3, '0')}';
  }

  /// Génère un numéro de reçu professionnel
  /// Ex: 'REC-20260808-0001'
  static String receiptNumber(int existingCount) {
    final now = DateTime.now();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final counter = (existingCount + 1).toString().padLeft(4, '0');
    return 'REC-$y$m$d-$counter';
  }

  /// Génère un matricule élève
  /// Ex: 'EL-2026-042'
  static String matricule(int existingCount) {
    final year = DateTime.now().year;
    return 'EL-$year-${(existingCount + 1).toString().padLeft(3, '0')}';
  }
}
