import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/data/services/result_service.dart';
import 'package:edupro_flutter_web/data/models/establishment_model.dart';
import 'package:edupro_flutter_web/data/models/academic_year_model.dart';
import 'package:edupro_flutter_web/data/models/class_model.dart';
import 'package:edupro_flutter_web/data/models/subject_model.dart';
import 'package:edupro_flutter_web/data/models/student_model.dart';
import 'package:edupro_flutter_web/data/models/teacher_model.dart';
import 'package:edupro_flutter_web/data/models/affectation_model.dart';
import 'package:edupro_flutter_web/data/models/evaluation_period_config_model.dart';
import 'package:edupro_flutter_web/data/models/grade_model.dart';
import 'package:edupro_flutter_web/data/models/user_model.dart';
import 'package:edupro_flutter_web/core/constants/establishment_types.dart';
import 'support/legacy_store_test_harness.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test(
      'Cycle complet de gestion des évaluations avec configuration établissement et fiches grisées',
      () async {
    final store = await createLegacyStore();

    // 1. Mise en place de l'établissement et de l'année scolaire
    final school = EstablishmentModel(
      id: 'SCH_01',
      name: 'Complexe Scolaire Excellence',
      type: 'Collège',
      institutionType: InstitutionType.school,
    );
    store.addEstablishment(school);

    final academicYear = AcademicYearModel(
      id: 'AY_2026',
      name: '2026-2027',
      start: '2026-09-01',
      end: '2027-06-30',
      schoolId: 'SCH_01',
      status: 'active',
    );
    store.addAcademicYear(academicYear);
    store.setSelectedAcademicYearId('AY_2026');

    // 2. Classe et Matière
    final class6A = ClassModel(
      id: 'CLS_6A',
      name: '6e A',
      schoolId: 'SCH_01',
      academicYearId: 'AY_2026',
    );
    store.addClass(class6A);

    final subjectMaths = SubjectModel(
      id: 'SUBJ_MATH',
      name: 'Mathématiques',
      coefficient: 3,
      schoolId: 'SCH_01',
      classes: ['6e A'],
    );
    store.addSubject(subjectMaths);

    // 3. Élèves
    final jean = StudentModel(
      id: 'ST_JEAN',
      firstName: 'Jean',
      lastName: 'Dupont',
      classId: 'CLS_6A',
      className: '6e A',
      matricule: 'MAT_001',
      schoolId: 'SCH_01',
      academicYearId: 'AY_2026',
    );
    final paul = StudentModel(
      id: 'ST_PAUL',
      firstName: 'Paul',
      lastName: 'Koffi',
      classId: 'CLS_6A',
      className: '6e A',
      matricule: 'MAT_002',
      schoolId: 'SCH_01',
      academicYearId: 'AY_2026',
    );
    store.addStudent(jean);
    store.addStudent(paul);

    // 4. Utilisateurs Enseignant et Administrateur
    final teacher = TeacherModel(
      id: 'USR_TEACHER',
      firstName: 'Michel',
      lastName: 'Enseignant',
      schoolId: 'SCH_01',
    );
    store.addTeacher(teacher);

    final teacherUser = UserModel(
      id: 'USR_TEACHER',
      name: 'Michel Enseignant',
      email: 'prof@ecole.test',
      role: UserRole.teacher,
      schoolId: 'SCH_01',
    );
    store.addUser(teacherUser);

    final adminUser = UserModel(
      id: 'USR_ADMIN',
      name: 'Directeur Études',
      email: 'admin@ecole.test',
      role: UserRole.admin,
      schoolId: 'SCH_01',
    );
    store.addUser(adminUser);

    // Affectation de l'enseignant
    final aff = AffectationModel(
      id: 'AFF_01',
      teacherId: 'USR_TEACHER',
      teacherName: 'Michel Enseignant',
      subjectId: 'SUBJ_MATH',
      classId: 'CLS_6A',
      schoolId: 'SCH_01',
      academicYearId: 'AY_2026',
    );
    store.addAffectation(aff);

    // =========================================================================
    // 1. CONFIGURATION DU NOMBRE D'ÉVALUATIONS PAR L'ÉTABLISSEMENT
    // =========================================================================
    // Trimestre 1 : 2 devoirs + 1 composition
    store.savePeriodConfig(EvaluationPeriodConfigModel(
      id: 'CFG_T1',
      schoolId: 'SCH_01',
      academicYearId: 'AY_2026',
      periodId: 'T1',
      periodName: 'Trimestre 1',
      homeworkCount: 2,
      hasComposition: true,
      status: 'active',
    ));

    // Trimestre 3 : 3 devoirs + 1 composition
    store.savePeriodConfig(EvaluationPeriodConfigModel(
      id: 'CFG_T3',
      schoolId: 'SCH_01',
      academicYearId: 'AY_2026',
      periodId: 'T3',
      periodName: 'Trimestre 3',
      homeworkCount: 3,
      hasComposition: true,
    ));

    // Vérifier que la génération automatique prépare les évaluations pour T1
    store.ensureEvaluationsGenerated(
      classId: 'CLS_6A',
      subjectId: 'SUBJ_MATH',
      periodId: 'T1',
      academicYearId: 'AY_2026',
    );

    final evalsT1 = store.getEvaluationsForContext(
      classId: 'CLS_6A',
      subjectId: 'SUBJ_MATH',
      periodId: 'T1',
      academicYearId: 'AY_2026',
    );

    expect(evalsT1.length, equals(3)); // Devoir 1, Devoir 2, Composition
    expect(evalsT1[0].title, equals('Devoir 1'));
    expect(evalsT1[0].type, equals('devoir'));
    expect(evalsT1[0].number, equals(1));
    expect(evalsT1[1].title, equals('Devoir 2'));
    expect(evalsT1[1].type, equals('devoir'));
    expect(evalsT1[1].number, equals(2));
    expect(evalsT1[2].title, equals('Composition'));
    expect(evalsT1[2].type, equals('composition'));

    // =========================================================================
    // 2. ENSEIGNANT : SAISIE EN COURS, ENREGISTREMENT ET CLÔTURE
    // =========================================================================
    await store.login('prof@ecole.test', 'password');

    final d1 = evalsT1[0];
    expect(d1.status, equals('draft')); // En cours

    // Enseignant saisit et enregistre les notes (reste En cours)
    final gJeanD1Id = store.addGrade(GradeModel(
      id: '',
      studentId: 'ST_JEAN',
      subjectId: 'SUBJ_MATH',
      eval: d1.title,
      grade: 15.0,
      evaluationId: d1.id,
      presence: 'present',
      enteredBy: 'USR_TEACHER',
      academicYearId: 'AY_2026',
    ));
    expect(gJeanD1Id, isNotEmpty);

    final gPaulD1Id = store.addGrade(GradeModel(
      id: '',
      studentId: 'ST_PAUL',
      subjectId: 'SUBJ_MATH',
      eval: d1.title,
      grade: 12.0,
      evaluationId: d1.id,
      presence: 'present',
      enteredBy: 'USR_TEACHER',
      academicYearId: 'AY_2026',
    ));
    expect(gPaulD1Id, isNotEmpty);

    // Clôture de l'évaluation par l'enseignant (EN COURS -> CLÔTURÉE / SOUMISE)
    final closeD1Ok = store.submitEvaluation(d1.id);
    expect(closeD1Ok, isTrue);

    final closedD1 = store.getEvaluationById(d1.id);
    expect(closedD1?.status, equals('submitted'));

    // =========================================================================
    // 3. APRÈS CLÔTURE : FICHE GRISE (Aucune modification directe possible)
    // =========================================================================
    final unauthorizedGradeUpdate = store.updateGrade(
        gJeanD1Id,
        GradeModel(
          id: gJeanD1Id,
          studentId: 'ST_JEAN',
          subjectId: 'SUBJ_MATH',
          eval: d1.title,
          grade: 18.0,
          evaluationId: d1.id,
          presence: 'present',
          enteredBy: 'USR_TEACHER',
        ));
    expect(unauthorizedGradeUpdate, isFalse); // Refusé car clôturé

    // =========================================================================
    // 4. INDÉPENDANCE STRICTE DES ÉVALUATIONS (Devoir 2 est vierge)
    // =========================================================================
    final d2 = store.getEvaluationById(evalsT1[1].id)!;
    expect(d2.status, equals('draft')); // Devoir 2 est prêt et en cours

    // Les notes de D1 ne sont pas copiées sur D2
    expect(store.getGradeByStudentAndEvaluation('ST_JEAN', d2.id), isNull);
    expect(store.getGradeByStudentAndEvaluation('ST_PAUL', d2.id), isNull);

    // Saisie sur D2
    store.addGrade(GradeModel(
      id: '',
      studentId: 'ST_JEAN',
      subjectId: 'SUBJ_MATH',
      eval: d2.title,
      grade: 17.0,
      evaluationId: d2.id,
      presence: 'present',
      enteredBy: 'USR_TEACHER',
      academicYearId: 'AY_2026',
    ));
    store.submitEvaluation(d2.id); // Clôture D2

    // =========================================================================
    // 5. ADMINISTRATION : REJET AVEC MOTIF OBLIGATOIRE ET CORRECTION ENSEIGNANT
    // =========================================================================
    await store.login('admin@ecole.test', 'password');

    // Admin rejette D1 avec motif
    final rejectD1Ok = store.rejectEvaluation(
        d1.id, 'Vérifier la note de Jean (barème sur 20)');
    expect(rejectD1Ok, isTrue);

    final rejectedD1 = store.getEvaluationById(d1.id);
    expect(rejectedD1?.status, equals('rejected')); // À corriger
    expect(rejectedD1?.rejectionReason,
        equals('Vérifier la note de Jean (barème sur 20)'));

    // Enseignant se reconnecte : l'évaluation est dans "À corriger" et modifiable
    await store.login('prof@ecole.test', 'password');
    final correctionOk = store.updateGrade(
        gJeanD1Id,
        GradeModel(
          id: gJeanD1Id,
          studentId: 'ST_JEAN',
          subjectId: 'SUBJ_MATH',
          eval: d1.title,
          grade: 16.0,
          evaluationId: d1.id,
          presence: 'present',
          enteredBy: 'USR_TEACHER',
          academicYearId: 'AY_2026',
        ));
    expect(correctionOk, isTrue);
    expect(store.getGradeByStudentAndEvaluation('ST_JEAN', d1.id)?.grade,
        equals(16.0));

    // Enseignant clôture à nouveau D1
    store.submitEvaluation(d1.id);
    expect(store.getEvaluationById(d1.id)?.status, equals('submitted'));

    // =========================================================================
    // 6. ADMINISTRATION : VALIDATION ADMINISTRATIVE DÉFINITIVE
    // =========================================================================
    await store.login('admin@ecole.test', 'password');

    // Admin valide D1 et D2
    store.validateEvaluation(d1.id);
    store.validateEvaluation(d2.id);
    expect(store.getEvaluationById(d1.id)?.status, equals('validated'));
    expect(store.getEvaluationById(d2.id)?.status, equals('validated'));

    // Saisie et validation de la Composition
    final compo = store.getEvaluationById(evalsT1[2].id)!;
    await store.login('prof@ecole.test', 'password');
    store.addGrade(GradeModel(
      id: '',
      studentId: 'ST_JEAN',
      subjectId: 'SUBJ_MATH',
      eval: compo.title,
      grade: 14.0,
      evaluationId: compo.id,
      presence: 'present',
      enteredBy: 'USR_TEACHER',
      academicYearId: 'AY_2026',
    ));
    store.submitEvaluation(compo.id);

    await store.login('admin@ecole.test', 'password');
    store.validateEvaluation(compo.id);
    expect(store.getEvaluationById(compo.id)?.status, equals('validated'));

    // =========================================================================
    // 7. VÉRIFICATION DU CALCUL AVEC LE MOTEUR EXISTANT (ResultService)
    // =========================================================================
    // Jean en Maths T1 :
    // - Devoir 1 = 16.0
    // - Devoir 2 = 17.0
    // -> Moyenne devoirs = (16.0 + 17.0) / 2 = 16.5
    // - Composition = 14.0
    // -> Moyenne matière = (16.5 + 14.0) / 2 = 15.25
    final resultService = ResultService(store);
    final subjectResult = resultService.calculateSubjectResultOfficial(
        'ST_JEAN', 'CLS_6A', 'SUBJ_MATH', 'T1');

    expect(subjectResult.isCalculable, isTrue);
    expect(subjectResult.homeworkAverage, equals(16.5));
    expect(subjectResult.compositionGrade, equals(14.0));
    expect(subjectResult.subjectAverage, equals(15.25));
    expect(subjectResult.coefficient, equals(3.0));
  });
}
