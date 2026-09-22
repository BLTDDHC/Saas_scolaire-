import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/data/models/establishment_model.dart';
import 'package:edupro_flutter_web/data/models/academic_year_model.dart';
import 'package:edupro_flutter_web/data/models/class_model.dart';
import 'package:edupro_flutter_web/data/models/subject_model.dart';
import 'package:edupro_flutter_web/data/models/student_model.dart';
import 'package:edupro_flutter_web/data/models/teacher_model.dart';
import 'package:edupro_flutter_web/data/models/affectation_model.dart';
import 'package:edupro_flutter_web/data/models/evaluation_period_config_model.dart';
import 'package:edupro_flutter_web/data/models/evaluation_model.dart';
import 'package:edupro_flutter_web/data/models/grade_model.dart';
import 'package:edupro_flutter_web/data/models/user_model.dart';
import 'package:edupro_flutter_web/core/constants/establishment_types.dart';
import 'support/legacy_store_test_harness.dart';

void main() {
  late StoreService store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await createLegacyStore();

    // Configuration de base : Établissement
    final school = EstablishmentModel(
      id: 'SCH_01',
      name: 'Complexe Scolaire Excellence',
      type: 'Collège',
      institutionType: InstitutionType.school,
    );
    store.addEstablishment(school);

    // Année scolaire 2026-2027
    final year = AcademicYearModel(
      id: 'AY_2026',
      name: '2026-2027',
      start: '2026-09-01',
      end: '2027-06-30',
      schoolId: 'SCH_01',
      status: 'active',
    );
    store.addAcademicYear(year);
    store.setSelectedAcademicYearId('AY_2026');

    // Classes 6e A et 6e B
    final class6A = ClassModel(
        id: 'CLS_6A',
        name: '6e A',
        schoolId: 'SCH_01',
        academicYearId: 'AY_2026');
    final class6B = ClassModel(
        id: 'CLS_6B',
        name: '6e B',
        schoolId: 'SCH_01',
        academicYearId: 'AY_2026');
    store.addClass(class6A);
    store.addClass(class6B);

    // Matières : Maths et Français
    final subjMath = SubjectModel(
        id: 'SUBJ_MATH',
        name: 'Mathématiques',
        coefficient: 3,
        schoolId: 'SCH_01');
    final subjFr = SubjectModel(
        id: 'SUBJ_FR', name: 'Français', coefficient: 3, schoolId: 'SCH_01');
    store.addSubject(subjMath);
    store.addSubject(subjFr);

    // Élèves
    final student1 = StudentModel(
        id: 'ST_01',
        firstName: 'Jean',
        lastName: 'Dupont',
        classId: 'CLS_6A',
        schoolId: 'SCH_01',
        academicYearId: 'AY_2026');
    final student2 = StudentModel(
        id: 'ST_02',
        firstName: 'Paul',
        lastName: 'Koffi',
        classId: 'CLS_6B',
        schoolId: 'SCH_01',
        academicYearId: 'AY_2026');
    store.addStudent(student1);
    store.addStudent(student2);

    // Utilisateurs
    final teacher = UserModel(
        id: 'USR_TEACHER',
        name: 'Professeur',
        email: 'teacher@ecole.test',
        role: UserRole.teacher,
        schoolId: 'SCH_01');
    final admin = UserModel(
        id: 'USR_ADMIN',
        name: 'Directeur',
        email: 'admin@ecole.test',
        role: UserRole.admin,
        schoolId: 'SCH_01');
    store.addUser(teacher);
    store.addUser(admin);

    final teacherModel = TeacherModel(
        id: 'USR_TEACHER',
        firstName: 'Professeur',
        lastName: 'Test',
        schoolId: 'SCH_01');
    store.addTeacher(teacherModel);

    // Affectations pour le prof
    store.addAffectation(AffectationModel(
        id: 'AFF_01',
        teacherId: 'USR_TEACHER',
        teacherName: 'Professeur',
        subjectId: 'SUBJ_MATH',
        classId: 'CLS_6A',
        schoolId: 'SCH_01',
        academicYearId: 'AY_2026'));
    store.addAffectation(AffectationModel(
        id: 'AFF_02',
        teacherId: 'USR_TEACHER',
        teacherName: 'Professeur',
        subjectId: 'SUBJ_FR',
        classId: 'CLS_6A',
        schoolId: 'SCH_01',
        academicYearId: 'AY_2026'));
    store.addAffectation(AffectationModel(
        id: 'AFF_03',
        teacherId: 'USR_TEACHER',
        teacherName: 'Professeur',
        subjectId: 'SUBJ_MATH',
        classId: 'CLS_6B',
        schoolId: 'SCH_01',
        academicYearId: 'AY_2026'));
  });

  // =========================================================================
  // TEST 1 : Configurer T1 + T2 + T3 à l'avance
  // =========================================================================
  test('TEST 1 : Configurer T1 + T2 + T3 à l\'avance', () {
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
    store.savePeriodConfig(EvaluationPeriodConfigModel(
      id: 'CFG_T2',
      schoolId: 'SCH_01',
      academicYearId: 'AY_2026',
      periodId: 'T2',
      periodName: 'Trimestre 2',
      homeworkCount: 2,
      hasComposition: true,
      status: 'locked',
    ));
    store.savePeriodConfig(EvaluationPeriodConfigModel(
      id: 'CFG_T3',
      schoolId: 'SCH_01',
      academicYearId: 'AY_2026',
      periodId: 'T3',
      periodName: 'Trimestre 3',
      homeworkCount: 3,
      hasComposition: true,
      status: 'locked',
    ));

    final configs = store.getEvaluationPeriodConfigs(
        academicYearId: 'AY_2026', schoolId: 'SCH_01');
    expect(configs.length, equals(3));
    expect(
        configs.any((c) => c.periodId == 'T1' && c.homeworkCount == 2), isTrue);
    expect(
        configs.any((c) => c.periodId == 'T2' && c.homeworkCount == 2), isTrue);
    expect(
        configs.any((c) => c.periodId == 'T3' && c.homeworkCount == 3), isTrue);
  });

  // =========================================================================
  // TEST 2 : Ouvrir T1 -> T1 = actif, T2 = verrouillé, T3 = verrouillé
  // =========================================================================
  test('TEST 2 : Ouvrir T1 -> T1 = actif, T2 = verrouillé, T3 = verrouillé',
      () {
    final t1Active = store.isPeriodActive('T1',
        schoolId: 'SCH_01', academicYearId: 'AY_2026');
    final t2Locked = store.isPeriodLocked('T2',
        schoolId: 'SCH_01', academicYearId: 'AY_2026');
    final t3Locked = store.isPeriodLocked('T3',
        schoolId: 'SCH_01', academicYearId: 'AY_2026');

    expect(t1Active, isTrue);
    expect(t2Locked, isTrue);
    expect(t3Locked, isTrue);
  });

  // =========================================================================
  // TEST 3 : Ouvrir D1 -> Vérifier que D2 est verrouillé
  // =========================================================================
  test('TEST 3 : Ouvrir D1 -> Vérifier que D2 est verrouillé', () {
    store.ensureEvaluationsGenerated(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026',
        schoolId: 'SCH_01');
    final evals = store.getEvaluationsForContext(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026');

    expect(evals.length, equals(3)); // D1, D2, Composition
    expect(evals[0].title, equals('Devoir 1'));
    expect(evals[0].status, equals('draft')); // Ouvert
    expect(evals[1].title, equals('Devoir 2'));
    expect(evals[1].status, equals('locked')); // Verrouillé
    expect(evals[2].title, equals('Composition'));
    expect(evals[2].status, equals('locked')); // Verrouillée
  });

  // =========================================================================
  // TEST 4 : Essayer d'ouvrir D2 avant clôture de D1 -> Doit échouer
  // =========================================================================
  test('TEST 4 : Essayer d\'ouvrir D2 avant clôture de D1 -> Doit échouer',
      () async {
    store.ensureEvaluationsGenerated(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026',
        schoolId: 'SCH_01');
    final evals = store.getEvaluationsForContext(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026');
    final d2 = evals[1];

    final canOpenD2 = store.canOpenEvaluation(d2.id);
    expect(canOpenD2, isFalse);

    final openResult = store.openEvaluation(d2.id);
    expect(openResult, isFalse);

    // Tentative de saisie sur D2 verrouillé
    await store.login('teacher@ecole.test', 'password');
    final gradeId = store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_01',
        subjectId: 'SUBJ_MATH',
        eval: 'Devoir 2',
        grade: 14.0,
        evaluationId: d2.id));
    expect(gradeId, isEmpty); // Rejeté
  });

  // =========================================================================
  // TEST 5 : Clôturer D1 -> Vérifier que D2 devient disponible / ouvert
  // =========================================================================
  test('TEST 5 : Clôturer D1 -> Vérifier que D2 devient disponible / ouvert',
      () async {
    store.ensureEvaluationsGenerated(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026',
        schoolId: 'SCH_01');
    final evals = store.getEvaluationsForContext(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026');
    final d1 = evals[0];

    await store.login('teacher@ecole.test', 'password');
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_01',
        subjectId: 'SUBJ_MATH',
        eval: 'Devoir 1',
        grade: 15.0,
        evaluationId: d1.id));

    // Clôture D1
    final submitOk = store.submitEvaluation(d1.id);
    expect(submitOk, isTrue);
    expect(store.getEvaluationById(d1.id)?.status, equals('submitted'));

    // D2 doit être passé en draft (ouvert)
    final d2 = store.getEvaluationById(evals[1].id);
    expect(d2?.status, equals('draft'));
  });

  // =========================================================================
  // TEST 6 : Essayer d'ouvrir Composition avant clôture D2 -> Doit échouer
  // =========================================================================
  test(
      'TEST 6 : Essayer d\'ouvrir Composition avant clôture D2 -> Doit échouer',
      () async {
    store.ensureEvaluationsGenerated(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026',
        schoolId: 'SCH_01');
    final evals = store.getEvaluationsForContext(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026');
    final d1 = evals[0];
    final compo = evals[2];

    // Clôture D1 uniquement (D2 est maintenant ouvert)
    store.submitEvaluation(d1.id);

    // Composition doit être impossible à ouvrir
    expect(store.canOpenEvaluation(compo.id), isFalse);
    expect(store.openEvaluation(compo.id), isFalse);

    // Tentative de saisie sur Composition
    await store.login('teacher@ecole.test', 'password');
    final gId = store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_01',
        subjectId: 'SUBJ_MATH',
        eval: 'Composition',
        grade: 16.0,
        evaluationId: compo.id));
    expect(gId, isEmpty);
  });

  // =========================================================================
  // TEST 7 : Clôturer D2 -> Vérifier que Composition devient disponible / ouverte
  // =========================================================================
  test(
      'TEST 7 : Clôturer D2 -> Vérifier que Composition devient disponible / ouverte',
      () async {
    store.ensureEvaluationsGenerated(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026',
        schoolId: 'SCH_01');
    final evals = store.getEvaluationsForContext(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026');
    final d1 = evals[0];
    final d2 = evals[1];
    final compo = evals[2];

    // Clôture D1 puis D2
    store.submitEvaluation(d1.id);
    store.submitEvaluation(d2.id);

    // Composition devient draft (ouverte)
    expect(store.getEvaluationById(compo.id)?.status, equals('draft'));

    // Saisie autorisée sur Composition
    await store.login('teacher@ecole.test', 'password');
    final gId = store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_01',
        subjectId: 'SUBJ_MATH',
        eval: 'Composition',
        grade: 16.0,
        evaluationId: compo.id));
    expect(gId, isNotEmpty);
  });

  // =========================================================================
  // TEST 8 : Terminer toutes les évaluations de T1 -> T1 = clôturé, T2 = disponible, T3 = verrouillé
  // =========================================================================
  test(
      'TEST 8 : Terminer toutes les évaluations de T1 -> T1 = clôturé, T2 = disponible, T3 = verrouillé',
      () {
    store.ensureEvaluationsGenerated(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026',
        schoolId: 'SCH_01');
    final evals = store.getEvaluationsForContext(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026');

    // Clôture de D1, D2, et Composition
    store.submitEvaluation(evals[0].id);
    store.submitEvaluation(evals[1].id);
    store.submitEvaluation(evals[2].id);

    // T1 est clôturé
    expect(
        store.isPeriodClosed('T1',
            schoolId: 'SCH_01', academicYearId: 'AY_2026'),
        isTrue);

    // T2 est éligible / peut être ouvert
    expect(
        store.canOpenPeriod('T2',
            schoolId: 'SCH_01', academicYearId: 'AY_2026'),
        isTrue);

    // T3 reste verrouillé et ne peut pas être ouvert tant que T2 n'est pas terminé
    expect(
        store.canOpenPeriod('T3',
            schoolId: 'SCH_01', academicYearId: 'AY_2026'),
        isFalse);
  });

  // =========================================================================
  // TEST 9 : Essayer d'ouvrir T3 alors que T2 est encore actif -> Doit échouer
  // =========================================================================
  test(
      'TEST 9 : Essayer d\'ouvrir T3 alors que T2 est encore actif -> Doit échouer',
      () {
    store.ensureEvaluationsGenerated(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026',
        schoolId: 'SCH_01');
    final evalsT1 = store.getEvaluationsForContext(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026');
    store.submitEvaluation(evalsT1[0].id);
    store.submitEvaluation(evalsT1[1].id);
    store.submitEvaluation(evalsT1[2].id);

    // Ouverture de T2
    final openT2 =
        store.openPeriod('T2', schoolId: 'SCH_01', academicYearId: 'AY_2026');
    expect(openT2, isTrue);
    expect(
        store.isPeriodActive('T2',
            schoolId: 'SCH_01', academicYearId: 'AY_2026'),
        isTrue);

    // Tentative d'ouverture de T3 alors que T2 est actif
    final canOpenT3 = store.canOpenPeriod('T3',
        schoolId: 'SCH_01', academicYearId: 'AY_2026');
    expect(canOpenT3, isFalse);

    final openT3 =
        store.openPeriod('T3', schoolId: 'SCH_01', academicYearId: 'AY_2026');
    expect(openT3, isFalse);
  });

  // =========================================================================
  // TEST 10 : Tester deux matières différentes -> Autorisées simultanément
  // =========================================================================
  test(
      'TEST 10 : Deux matières différentes peuvent avoir leur D1 ouvert simultanément',
      () async {
    store.ensureEvaluationsGenerated(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026',
        schoolId: 'SCH_01');
    store.ensureEvaluationsGenerated(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_FR',
        periodId: 'T1',
        academicYearId: 'AY_2026',
        schoolId: 'SCH_01');

    final evalsMath = store.getEvaluationsForContext(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026');
    final evalsFr = store.getEvaluationsForContext(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_FR',
        periodId: 'T1',
        academicYearId: 'AY_2026');

    // 6e A / Maths / T1 / D1 = draft (ouvert)
    expect(evalsMath[0].status, equals('draft'));

    // 6e A / Français / T1 / D1 = draft (ouvert)
    expect(evalsFr[0].status, equals('draft'));

    // Saisie sur les deux autorisée
    await store.login('teacher@ecole.test', 'password');
    final gMath = store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_01',
        subjectId: 'SUBJ_MATH',
        eval: 'Devoir 1',
        grade: 15.0,
        evaluationId: evalsMath[0].id));
    final gFr = store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_01',
        subjectId: 'SUBJ_FR',
        eval: 'Devoir 1',
        grade: 14.0,
        evaluationId: evalsFr[0].id));

    expect(gMath, isNotEmpty);
    expect(gFr, isNotEmpty);
  });

  // =========================================================================
  // TEST 11 : Tester deux classes différentes -> Autorisées simultanément
  // =========================================================================
  test(
      'TEST 11 : Deux classes différentes peuvent avoir leur D1 ouvert simultanément',
      () async {
    store.ensureEvaluationsGenerated(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026',
        schoolId: 'SCH_01');
    store.ensureEvaluationsGenerated(
        classId: 'CLS_6B',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026',
        schoolId: 'SCH_01');

    final evals6A = store.getEvaluationsForContext(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026');
    final evals6B = store.getEvaluationsForContext(
        classId: 'CLS_6B',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026');

    // 6e A / Maths / T1 / D1 = draft (ouvert)
    expect(evals6A[0].status, equals('draft'));

    // 6e B / Maths / T1 / D1 = draft (ouvert)
    expect(evals6B[0].status, equals('draft'));

    // Saisie sur les deux autorisée
    await store.login('teacher@ecole.test', 'password');
    final g6A = store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_01',
        subjectId: 'SUBJ_MATH',
        eval: 'Devoir 1',
        grade: 15.0,
        evaluationId: evals6A[0].id));
    final g6B = store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_02',
        subjectId: 'SUBJ_MATH',
        eval: 'Devoir 1',
        grade: 13.0,
        evaluationId: evals6B[0].id));

    expect(g6A, isNotEmpty);
    expect(g6B, isNotEmpty);
  });

  // =========================================================================
  // TEST 12 : Deux évaluations du même contexte -> Impossible d'être ouvertes en même temps
  // =========================================================================
  test(
      'TEST 12 : Deux évaluations du même contexte ne peuvent pas être ouvertes simultanément',
      () async {
    store.ensureEvaluationsGenerated(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026',
        schoolId: 'SCH_01');
    final evals = store.getEvaluationsForContext(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026');

    // D1 est draft (ouvert)
    expect(evals[0].status, equals('draft'));

    // Tentative d'ajouter manuellement un 2e devoir en draft dans le même contexte
    await store.login('teacher@ecole.test', 'password');
    final illegalD2 = EvaluationModel(
      id: 'EV_ILLEGAL_D2',
      title: 'Devoir 2 Forcé',
      type: 'devoir',
      number: 2,
      academicYearId: 'AY_2026',
      periodId: 'T1',
      classId: 'CLS_6A',
      subjectId: 'SUBJ_MATH',
      status: 'draft',
      createdBy: 'USR_TEACHER',
      createdAt: DateTime.now().toIso8601String(),
      schoolId: 'SCH_01',
    );
    final res = store.addEvaluation(illegalD2);
    expect(res, isEmpty); // Rejeté par le store
  });

  // =========================================================================
  // TEST 13 : Tester un rejet -> D1 rejeté -> D2 reste bloqué / verrouillé
  // =========================================================================
  test('TEST 13 : D1 rejeté -> D2 reste bloqué / verrouillé', () async {
    store.ensureEvaluationsGenerated(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026',
        schoolId: 'SCH_01');
    final evals = store.getEvaluationsForContext(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026');
    final d1 = evals[0];
    final d2 = evals[1];

    await store.login('teacher@ecole.test', 'password');
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_01',
        subjectId: 'SUBJ_MATH',
        eval: 'Devoir 1',
        grade: 15.0,
        evaluationId: d1.id));
    store.submitEvaluation(d1.id);

    // Admin rejette D1 avec motif obligatoire
    await store.login('admin@ecole.test', 'password');
    final rejectOk = store.rejectEvaluation(d1.id, 'Erreur de barème');
    expect(rejectOk, isTrue);
    expect(store.getEvaluationById(d1.id)?.status, equals('rejected'));

    // D2 doit être verrouillé
    expect(store.getEvaluationById(d2.id)?.status, equals('locked'));

    // Saisie sur D2 bloquée
    await store.login('teacher@ecole.test', 'password');
    final gradeOnD2 = store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_01',
        subjectId: 'SUBJ_MATH',
        eval: 'Devoir 2',
        grade: 12.0,
        evaluationId: d2.id));
    expect(gradeOnD2, isEmpty);
  });

  // =========================================================================
  // TEST 14 : Corriger D1 et le soumettre à nouveau -> D2 redevient disponible
  // =========================================================================
  test(
      'TEST 14 : Corriger D1 et le soumettre à nouveau -> D2 redevient disponible',
      () async {
    store.ensureEvaluationsGenerated(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026',
        schoolId: 'SCH_01');
    final evals = store.getEvaluationsForContext(
        classId: 'CLS_6A',
        subjectId: 'SUBJ_MATH',
        periodId: 'T1',
        academicYearId: 'AY_2026');
    final d1 = evals[0];
    final d2 = evals[1];

    await store.login('teacher@ecole.test', 'password');
    final gD1Id = store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_01',
        subjectId: 'SUBJ_MATH',
        eval: 'Devoir 1',
        grade: 15.0,
        evaluationId: d1.id));
    store.submitEvaluation(d1.id);

    await store.login('admin@ecole.test', 'password');
    store.rejectEvaluation(d1.id, 'Erreur de barème');

    // Professeur corrige D1
    await store.login('teacher@ecole.test', 'password');
    final updateOk = store.updateGrade(
        gD1Id,
        GradeModel(
            id: gD1Id,
            studentId: 'ST_01',
            subjectId: 'SUBJ_MATH',
            eval: 'Devoir 1',
            grade: 16.0,
            evaluationId: d1.id));
    expect(updateOk, isTrue);

    // Professeur reclôture D1
    final resubmitOk = store.submitEvaluation(d1.id);
    expect(resubmitOk, isTrue);
    expect(store.getEvaluationById(d1.id)?.status, equals('submitted'));

    // D2 redevient disponible (draft / ouvert)
    expect(store.getEvaluationById(d2.id)?.status, equals('draft'));

    // Saisie sur D2 maintenant autorisée
    final gradeOnD2 = store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_01',
        subjectId: 'SUBJ_MATH',
        eval: 'Devoir 2',
        grade: 17.0,
        evaluationId: d2.id));
    expect(gradeOnD2, isNotEmpty);
  });
}
