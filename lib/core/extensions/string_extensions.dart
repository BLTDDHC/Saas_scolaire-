/// Extensions utilitaires sur String
extension StringExtensions on String {
  /// Génère les initiales à partir d'un nom
  /// 'Ibrahim Koné' → 'IK'
  String get initials {
    if (isEmpty) return '';
    final words = trim().split(RegExp(r'\s+'));
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return substring(0, length >= 2 ? 2 : 1).toUpperCase();
  }

  /// Capitalize la première lettre
  String get capitalize {
    if (isEmpty) return '';
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  /// Vérifie si la chaîne contient un des mots-clés (insensible à la casse)
  bool containsAny(List<String> keywords) {
    final lower = toLowerCase();
    return keywords.any((kw) => lower.contains(kw.toLowerCase()));
  }
}

/// Extensions sur String? pour les valeurs nullables
extension NullableStringExtensions on String? {
  /// Retourne la valeur ou un fallback
  String orDefault([String fallback = '—']) => this == null || this!.isEmpty ? fallback : this!;

  /// Vérifie si la valeur est vide ou null
  bool get isNullOrEmpty => this == null || this!.isEmpty;

  /// Vérifie si la valeur n'est pas vide
  bool get isNotNullOrEmpty => !isNullOrEmpty;
}
