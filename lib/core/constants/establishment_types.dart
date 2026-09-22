/// Types d'établissements supportés par EduPro
enum InstitutionType {
  school,      // École Primaire
  college,     // Collège
  highSchool,  // Lycée
  university,  // Université
  institute;   // Institut Supérieur

  /// Label affiché à l'utilisateur
  String get label {
    switch (this) {
      case InstitutionType.school:     return 'École Primaire';
      case InstitutionType.college:    return 'Collège';
      case InstitutionType.highSchool: return 'Lycée';
      case InstitutionType.university: return 'Université';
      case InstitutionType.institute:  return 'Institut';
    }
  }

  /// Valeur stockée en base (compatible avec le JS existant)
  String get value {
    switch (this) {
      case InstitutionType.school:     return 'school';
      case InstitutionType.college:    return 'college';
      case InstitutionType.highSchool: return 'high_school';
      case InstitutionType.university: return 'university';
      case InstitutionType.institute:  return 'institute';
    }
  }

  /// Est-ce un établissement d'enseignement supérieur ?
  bool get isHigherEducation =>
      this == InstitutionType.university || this == InstitutionType.institute;

  /// Est-ce un établissement scolaire (primaire / collège / lycée) ?
  bool get isSchool => !isHigherEducation;

  /// Préfixe pour la génération d'IDs
  String get idPrefix {
    switch (this) {
      case InstitutionType.school:     return 'P';
      case InstitutionType.college:    return 'C';
      case InstitutionType.highSchool: return 'L';
      case InstitutionType.university: return 'U';
      case InstitutionType.institute:  return 'I';
    }
  }

  /// Nom du niveau scolaire associé
  String get levelName {
    switch (this) {
      case InstitutionType.school:     return 'Primaire';
      case InstitutionType.college:    return 'Collège';
      case InstitutionType.highSchool: return 'Lycée';
      case InstitutionType.university: return 'Universitaire';
      case InstitutionType.institute:  return 'Supérieur';
    }
  }

  /// Depuis un label texte (compatible JS)
  static InstitutionType fromTypeLabel(String? typeLabel) {
    if (typeLabel == null || typeLabel.isEmpty) return InstitutionType.school;
    final label = typeLabel.toLowerCase();
    if (label.contains('université') || label.contains('universite')) return InstitutionType.university;
    if (label.contains('institut')) return InstitutionType.institute;
    if (label.contains('lycée') || label.contains('lycee')) return InstitutionType.highSchool;
    if (label.contains('collège') || label.contains('college')) return InstitutionType.college;
    if (label.contains('école') || label.contains('ecole') || label.contains('primaire')) return InstitutionType.school;
    return InstitutionType.school;
  }
  
  /// Depuis une valeur stockée
  static InstitutionType fromValue(String? value) {
    if (value == null) return InstitutionType.school;
    switch (value) {
      case 'school': return InstitutionType.school;
      case 'college': return InstitutionType.college;
      case 'high_school': return InstitutionType.highSchool;
      case 'university': return InstitutionType.university;
      case 'institute': return InstitutionType.institute;
      default: return fromTypeLabel(value);
    }
  }
}

/// Rôles utilisateur EduPro
enum UserRole {
  superadmin,
  admin,
  teacher,
  student,
  parent;

  String get label {
    switch (this) {
      case UserRole.superadmin: return 'Super Administrateur';
      case UserRole.admin:      return 'Administrateur';
      case UserRole.teacher:    return 'Enseignant';
      case UserRole.student:    return 'Élève';
      case UserRole.parent:     return 'Parent';
    }
  }

  String get value {
    switch (this) {
      case UserRole.superadmin: return 'superadmin';
      case UserRole.admin:      return 'admin';
      case UserRole.teacher:    return 'teacher';
      case UserRole.student:    return 'student';
      case UserRole.parent:     return 'parent';
    }
  }

  String get icon {
    switch (this) {
      case UserRole.superadmin: return '🛡️';
      case UserRole.admin:      return '🏫';
      case UserRole.teacher:    return '👨‍🏫';
      case UserRole.student:    return '🎓';
      case UserRole.parent:     return '👨‍👩‍👧';
    }
  }

  static UserRole fromValue(String? value) {
    if (value == null) return UserRole.student;
    switch (value) {
      case 'superadmin': return UserRole.superadmin;
      case 'admin':      return UserRole.admin;
      case 'teacher':    return UserRole.teacher;
      case 'student':    return UserRole.student;
      case 'parent':     return UserRole.parent;
      default:           return UserRole.student;
    }
  }
}

/// Plans d'abonnement
enum SubscriptionPlan {
  free,
  basic,
  pro,
  enterprise;

  String get label {
    switch (this) {
      case SubscriptionPlan.free:       return 'Free';
      case SubscriptionPlan.basic:      return 'Basic';
      case SubscriptionPlan.pro:        return 'Pro';
      case SubscriptionPlan.enterprise: return 'Enterprise';
    }
  }

  String get value {
    switch (this) {
      case SubscriptionPlan.free:       return 'free';
      case SubscriptionPlan.basic:      return 'basic';
      case SubscriptionPlan.pro:        return 'pro';
      case SubscriptionPlan.enterprise: return 'enterprise';
    }
  }

  String get price {
    switch (this) {
      case SubscriptionPlan.free:       return '0 FCFA';
      case SubscriptionPlan.basic:      return '24 900 FCFA';
      case SubscriptionPlan.pro:        return '49 900 FCFA';
      case SubscriptionPlan.enterprise: return '99 900 FCFA';
    }
  }

  static SubscriptionPlan fromValue(String? value) {
    if (value == null) return SubscriptionPlan.free;
    switch (value.toLowerCase()) {
      case 'free':       return SubscriptionPlan.free;
      case 'basic':      return SubscriptionPlan.basic;
      case 'pro':        return SubscriptionPlan.pro;
      case 'enterprise': return SubscriptionPlan.enterprise;
      default:           return SubscriptionPlan.free;
    }
  }
}

/// Statut d'un compte utilisateur
enum AccountStatus {
  active,
  invitationPending,
  suspended;

  String get label {
    switch (this) {
      case AccountStatus.active:            return 'Actif';
      case AccountStatus.invitationPending: return 'Invitation en attente';
      case AccountStatus.suspended:         return 'Suspendu';
    }
  }

  String get value {
    switch (this) {
      case AccountStatus.active:            return 'active';
      case AccountStatus.invitationPending: return 'invitation_pending';
      case AccountStatus.suspended:         return 'suspended';
    }
  }

  static AccountStatus fromValue(String? value) {
    switch (value) {
      case 'active':             return AccountStatus.active;
      case 'invitation_pending': return AccountStatus.invitationPending;
      case 'suspended':          return AccountStatus.suspended;
      default:                   return AccountStatus.active;
    }
  }
}
