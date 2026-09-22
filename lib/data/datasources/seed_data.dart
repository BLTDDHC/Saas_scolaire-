import '../models/user_model.dart';
import '../models/establishment_model.dart';
import '../models/academic_year_model.dart';
import '../models/student_model.dart';
import '../models/other_models.dart';
import '../models/education/school_level_model.dart';
import '../models/education/series_model.dart';
import '../../core/constants/establishment_types.dart';

/// Données seed réalistes — Migration intégrale de data.js
class SeedData {
  SeedData._();

  /// Utilisateurs initiaux pour simulation de connexion
  static List<UserModel> get users => [
        UserModel(
          id: 'SA001',
          name: 'Ibrahim Koné',
          email: 'admin@edupro.com',
          role: UserRole.superadmin,
          roleName: 'Super Administrateur',
          initials: 'IK',
          schoolId: null,
          status: AccountStatus.active,
          passwordSet: true,
        ),
        UserModel(
          id: 'AD001',
          name: 'Aminata Diallo',
          email: 'aminata@lycee-excellence.edu',
          role: UserRole.admin,
          roleName: 'Administrateur',
          initials: 'AD',
          schoolId: 'ET001',
          establishment: "Lycée d'Excellence",
          status: AccountStatus.active,
          passwordSet: true,
        ),
        UserModel(
          id: 'EN001',
          name: 'Moussa Konaté',
          email: 'konate@lycee-excellence.edu',
          role: UserRole.teacher,
          roleName: 'Enseignant',
          initials: 'MK',
          schoolId: 'ET001',
          subject: 'Mathématiques',
          status: AccountStatus.active,
          passwordSet: true,
        ),
        UserModel(
          id: 'EL001',
          name: 'Amadou Diallo',
          email: 'amadou.diallo@eleve.edu',
          role: UserRole.student,
          roleName: 'Élève',
          initials: 'AD',
          schoolId: 'ET001',
          className: '2nde A',
          status: AccountStatus.active,
          passwordSet: true,
        ),
        UserModel(
          id: 'PA001',
          name: 'Fatoumata Diallo',
          email: 'fatoumata@email.com',
          role: UserRole.parent,
          roleName: 'Parent',
          initials: 'FD',
          schoolId: 'ET001',
          childrenIds: ['EL001', 'EL015'],
          status: AccountStatus.active,
          passwordSet: true,
        ),
        UserModel(
          id: 'AD013',
          name: 'Marie Koffi',
          email: 'admin.primaire@demo.cg',
          role: UserRole.admin,
          roleName: 'Administrateur',
          initials: 'MK',
          schoolId: 'ET013',
          establishment: 'École Primaire Les Pionniers',
          status: AccountStatus.active,
          passwordSet: true,
        ),
        UserModel(
          id: 'AD014',
          name: 'Paul Kouassi',
          email: 'admin.college@demo.cg',
          role: UserRole.admin,
          roleName: 'Administrateur',
          initials: 'PK',
          schoolId: 'ET014',
          establishment: 'Collège La Réussite',
          status: AccountStatus.active,
          passwordSet: true,
        ),
        UserModel(
          id: 'AD015',
          name: 'Awa Traoré',
          email: 'admin.lycee@demo.cg',
          role: UserRole.admin,
          roleName: 'Administrateur',
          initials: 'AT',
          schoolId: 'ET015',
          establishment: 'Lycée Moderne',
          status: AccountStatus.active,
          passwordSet: true,
        ),
      ];

  /// Établissements partenaires démo
  static List<EstablishmentModel> get establishments => [
        EstablishmentModel(
          id: 'ET013',
          name: 'École Primaire Les Pionniers',
          type: 'École Primaire',
          institutionType: InstitutionType.school,
          admin: 'Marie Koffi',
          students: 10,
          plan: 'free',
          status: 'active',
          date: '2026-07-01',
          city: 'Brazzaville',
        ),
        EstablishmentModel(
          id: 'ET014',
          name: 'Collège La Réussite',
          type: 'Collège',
          institutionType: InstitutionType.college,
          admin: 'Paul Kouassi',
          students: 15,
          plan: 'basic',
          status: 'active',
          date: '2026-07-01',
          city: 'Brazzaville',
        ),
        EstablishmentModel(
          id: 'ET015',
          name: 'Lycée Moderne de Brazzaville',
          type: 'Lycée',
          institutionType: InstitutionType.highSchool,
          admin: 'Awa Traoré',
          students: 15,
          plan: 'pro',
          status: 'active',
          date: '2026-07-01',
          city: 'Brazzaville',
        ),
      ];

  /// Abonnements (Super Admin)
  static List<SubscriptionModel> get subscriptions => [
        SubscriptionModel(
            client: "Lycée d'Excellence",
            plan: 'Pro',
            price: '49 900 FCFA',
            startDate: '2025-01-15',
            endDate: '2026-01-15',
            status: 'active'),
        SubscriptionModel(
            client: 'Collège Sainte-Marie',
            plan: 'Basic',
            price: '24 900 FCFA',
            startDate: '2025-03-22',
            endDate: '2026-03-22',
            status: 'active'),
        SubscriptionModel(
            client: 'Institut Moderne',
            plan: 'Enterprise',
            price: '99 900 FCFA',
            startDate: '2024-09-01',
            endDate: '2025-09-01',
            status: 'active'),
        SubscriptionModel(
            client: 'École Primaire du Plateau',
            plan: 'Free',
            price: '0 FCFA',
            startDate: '2025-06-10',
            endDate: '—',
            status: 'active'),
      ];

  /// Années académiques initiales
  static List<AcademicYearModel> get academicYears => [
        AcademicYearModel(
            id: 'AYP2627',
            name: '2026-2027',
            start: '2026-09-01',
            end: '2027-07-31',
            establishment: 'École Primaire Les Pionniers',
            schoolId: 'ET013',
            status: 'active',
            isActive: true),
        AcademicYearModel(
            id: 'AYC2627',
            name: '2026-2027',
            start: '2026-09-01',
            end: '2027-07-31',
            establishment: 'Collège La Réussite',
            schoolId: 'ET014',
            status: 'active',
            isActive: true),
        AcademicYearModel(
            id: 'AYL2627',
            name: '2026-2027',
            start: '2026-09-01',
            end: '2027-07-31',
            establishment: 'Lycée Moderne de Brazzaville',
            schoolId: 'ET015',
            status: 'active',
            isActive: true),
      ];

  /// Niveaux scolaires (primaire / collège / lycée) — structure réutilisable
  static List get schoolLevels => [
        // Primaire (schoolId left empty for defaults)
        SchoolLevelModel(
            id: 'SL_P_CP1', name: 'CP1', cycle: 'Primaire', schoolId: ''),
        SchoolLevelModel(
            id: 'SL_P_CP2', name: 'CP2', cycle: 'Primaire', schoolId: ''),
        SchoolLevelModel(
            id: 'SL_P_CE1', name: 'CE1', cycle: 'Primaire', schoolId: ''),
        SchoolLevelModel(
            id: 'SL_P_CE2', name: 'CE2', cycle: 'Primaire', schoolId: ''),
        SchoolLevelModel(
            id: 'SL_P_CM1', name: 'CM1', cycle: 'Primaire', schoolId: ''),
        SchoolLevelModel(
            id: 'SL_P_CM2', name: 'CM2', cycle: 'Primaire', schoolId: ''),
        // Collège
        SchoolLevelModel(
            id: 'SL_C_6E', name: '6e', cycle: 'Collège', schoolId: ''),
        SchoolLevelModel(
            id: 'SL_C_5E', name: '5e', cycle: 'Collège', schoolId: ''),
        SchoolLevelModel(
            id: 'SL_C_4E', name: '4e', cycle: 'Collège', schoolId: ''),
        SchoolLevelModel(
            id: 'SL_C_3E', name: '3e', cycle: 'Collège', schoolId: ''),
        // Lycée
        SchoolLevelModel(
            id: 'SL_L_2NDE', name: 'Seconde', cycle: 'Lycée', schoolId: ''),
        SchoolLevelModel(
            id: 'SL_L_1ERE', name: 'Première', cycle: 'Lycée', schoolId: ''),
        SchoolLevelModel(
            id: 'SL_L_TER', name: 'Terminale', cycle: 'Lycée', schoolId: ''),
      ];

  /// Series defaults (Lycée)
  static List get series => [
        SeriesModel(id: 'SR_A', name: 'A', schoolId: ''),
        SeriesModel(id: 'SR_B', name: 'B', schoolId: ''),
        SeriesModel(id: 'SR_C', name: 'C', schoolId: ''),
      ];

  /// Élèves initiaux (échantillon représentatif)
  static List<StudentModel> get students => [
        StudentModel(
            id: 'ELP001',
            firstName: 'Jean',
            lastName: 'Mbala',
            className: 'CP1',
            level: 'Primaire',
            matricule: 'P-2026-001',
            email: 'jean.mbala@pionniers.demo',
            phone: '+24206010101',
            sex: 'M',
            birthDate: '2017-04-12',
            address: 'Brazzaville',
            parent: 'Claire Mbala',
            parentPhone: '+24206020202',
            schoolId: 'ET013',
            academicYearId: 'AYP2627'),
        StudentModel(
            id: 'ELP002',
            firstName: 'Marie',
            lastName: 'Ngoma',
            className: 'CP1',
            level: 'Primaire',
            matricule: 'P-2026-002',
            email: 'marie.ngoma@pionniers.demo',
            phone: '+24206030303',
            sex: 'F',
            birthDate: '2017-08-22',
            address: 'Brazzaville',
            parent: 'Paul Ngoma',
            parentPhone: '+24206040404',
            schoolId: 'ET013',
            academicYearId: 'AYP2627'),
        StudentModel(
            id: 'ELC001',
            firstName: 'Sylla',
            lastName: 'Oumar',
            className: '6e A',
            level: 'Collège',
            matricule: 'C-2026-001',
            email: 'oumar.sylla@lareussite.demo',
            phone: '+24207010101',
            sex: 'M',
            birthDate: '2012-02-10',
            address: 'Brazzaville',
            parent: 'Aissata Sylla',
            parentPhone: '+24207020202',
            schoolId: 'ET014',
            academicYearId: 'AYC2627'),
        StudentModel(
            id: 'ELL001',
            firstName: 'Koffi',
            lastName: 'Amenan',
            className: '2nde A',
            level: 'Lycée',
            matricule: 'L-2026-001',
            email: 'koffi.amenan@lycee.demo',
            phone: '+24208010101',
            sex: 'F',
            birthDate: '2008-01-15',
            address: 'Brazzaville',
            parent: 'Yao Koffi',
            parentPhone: '+24208020202',
            schoolId: 'ET015',
            academicYearId: 'AYL2627'),
      ];
}

