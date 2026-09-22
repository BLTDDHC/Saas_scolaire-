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
import 'package:edupro_flutter_web/data/models/evaluation_model.dart';
import 'package:edupro_flutter_web/data/models/grade_model.dart';
import 'package:edupro_flutter_web/data/models/user_model.dart';
import 'package:edupro_flutter_web/core/constants/establishment_types.dart';
import 'support/legacy_store_test_harness.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('Validation complète des 7 scénarios de refonte des évaluations',
      () async {
    final store = await createLegacyStore();

    // 1. Initialisation de l'école et de l'année scolaire
    final school = EstablishmentModel(
      id: 'SCH_TEST',
      name: 'Collège & Lycée Démo',
      type: 'Collège',
      institutionType: InstitutionType.school,
    );
    store.addEstablishment(school);

    final academicYear = AcademicYearModel(
      id: 'AY_2026',
      name: '2026-2027',
      start: '2026-09-01',
      end: '2027-06-30',
      schoolId: 'SCH_TEST',
      status: 'active',
    );
    store.addAcademicYear(academicYear);
    store.setSelectedAcademicYearId('AY_2026');

    // 2. Classe 6e A
    final class6A = ClassModel(
      id: 'C_6A',
      name: '6e A',
      schoolId: 'SCH_TEST',
      academicYearId: 'AY_2026',
    );
    store.addClass(class6A);

    // 3. Matière Mathématiques
    final subjectMaths = SubjectModel(
      id: 'SUBJ_MATHS',
      name: 'Mathématiques',
      coefficient: 2,
      schoolId: 'SCH_TEST',
      classes: ['6e A'],
    );
    store.addSubject(subjectMaths);

    // 4. Élèves de 6e A
    final jean = StudentModel(
      id: 'ST_JEAN',
      firstName: 'Jean',
      lastName: 'Dupont',
      classId: 'C_6A',
      className: '6e A',
      matricule: 'MAT001',
      schoolId: 'SCH_TEST',
      academicYearId: 'AY_2026',
    );
    final paul = StudentModel(
      id: 'ST_PAUL',
      firstName: 'Paul',
      lastName: 'Kouassi',
      classId: 'C_6A',
      className: '6e A',
      matricule: 'MAT002',
      schoolId: 'SCH_TEST',
      academicYearId: 'AY_2026',
    );
    final marie = StudentModel(
      id: 'ST_MARIE',
      firstName: 'Marie',
      lastName: 'Curie',
      classId: 'C_6A',
      className: '6e A',
      matricule: 'MAT003',
      schoolId: 'SCH_TEST',
      academicYearId: 'AY_2026',
    );
    final david = StudentModel(
      id: 'ST_DAVID',
      firstName: 'David',
      lastName: 'Koné',
      classId: 'C_6A',
      className: '6e A',
      matricule: 'MAT004',
      schoolId: 'SCH_TEST',
      academicYearId: 'AY_2026',
    );
    store.addStudent(jean);
    store.addStudent(paul);
    store.addStudent(marie);
    store.addStudent(david);

    // 5. Enseignant et Administrateur
    final teacher = TeacherModel(
      id: 'T_MATHS',
      firstName: 'Alain',
      lastName: 'Prof',
      schoolId: 'SCH_TEST',
    );
    store.addTeacher(teacher);

    final teacherUser = UserModel(
      id: 'T_MATHS',
      name: 'Alain Prof',
      email: 'teacher@demo.test',
      role: UserRole.teacher,
      schoolId: 'SCH_TEST',
    );
    store.addUser(teacherUser);

    final adminUser = UserModel(
      id: 'ADM_01',
      name: 'Directrice Études',
      email: 'admin@demo.test',
      role: UserRole.admin,
      schoolId: 'SCH_TEST',
    );
    store.addUser(adminUser);

    // Affectation de l'enseignant
    final aff = AffectationModel(
      id: 'AFF_01',
      teacherId: 'T_MATHS',
      teacherName: 'Alain Prof',
      subjectId: 'SUBJ_MATHS',
      classId: 'C_6A',
      schoolId: 'SCH_TEST',
      academicYearId: 'AY_2026',
    );
    store.addAffectation(aff);

    // =========================================================================
    // SCÉNARIO 1 : Créer Devoir 1, saisir des notes en Brouillon, quitter, revenir
    // =========================================================================
    await store.login('teacher@demo.test', 'password');
    expect(store.currentUser?.role, equals(UserRole.teacher));

    final devoir1 = EvaluationModel(
      id: 'EV_D1',
      title: 'Devoir 1',
      type: 'devoir',
      number: 1,
      academicYearId: 'AY_2026',
      periodId: 'T1',
      classId: 'C_6A',
      subjectId: 'SUBJ_MATHS',
      status: 'draft',
      maxScore: 20.0,
      createdBy: 'T_MATHS',
      createdAt: DateTime.now().toIso8601String(),
      schoolId: 'SCH_TEST',
    );
    final d1Id = store.addEvaluation(devoir1);
    expect(d1Id, equals('EV_D1'));

    // Saisie des notes pour Jean (15) et Paul (12), Marie (absente)
    store.addGrade(GradeModel(
      id: 'G_D1_JEAN',
      studentId: 'ST_JEAN',
      subjectId: 'SUBJ_MATHS',
      eval: 'Devoir 1',
      grade: 15.0,
      evaluationId: 'EV_D1',
      presence: 'present',
      enteredBy: 'T_MATHS',
      academicYearId: 'AY_2026',
    ));
    store.addGrade(GradeModel(
      id: 'G_D1_PAUL',
      studentId: 'ST_PAUL',
      subjectId: 'SUBJ_MATHS',
      eval: 'Devoir 1',
      grade: 12.0,
      evaluationId: 'EV_D1',
      presence: 'present',
      enteredBy: 'T_MATHS',
      academicYearId: 'AY_2026',
    ));
    store.addGrade(GradeModel(
      id: 'G_D1_MARIE',
      studentId: 'ST_MARIE',
      subjectId: 'SUBJ_MATHS',
      eval: 'Devoir 1',
      grade: null,
      evaluationId: 'EV_D1',
      presence: 'absent',
      enteredBy: 'T_MATHS',
      academicYearId: 'AY_2026',
    ));

    // Simulation : Quitter l'application et Revenir
    final retrievedD1 = store.getEvaluationById('EV_D1');
    expect(retrievedD1?.status, equals('draft'));

    final gradeJeanD1 =
        store.getGradeByStudentAndEvaluation('ST_JEAN', 'EV_D1');
    expect(gradeJeanD1?.grade, equals(15.0));
    expect(gradeJeanD1?.presence, equals('present'));

    final gradeMarieD1 =
        store.getGradeByStudentAndEvaluation('ST_MARIE', 'EV_D1');
    expect(gradeMarieD1?.grade, isNull);
    expect(gradeMarieD1?.presence, equals('absent'));

    // =========================================================================
    // SCÉNARIO 2 : Soumission du Devoir 1 (BROUILLON -> SOUMISE)
    // =========================================================================
    final submitOk = store.submitEvaluation('EV_D1');
    expect(submitOk, isTrue);

    final submittedD1 = store.getEvaluationById('EV_D1');
    expect(submittedD1?.status, equals('submitted'));

    // Vérifier que l'enseignant ne peut plus modifier directement
    final unauthorizedAdd = store.addGrade(GradeModel(
      id: 'G_D1_DAVID',
      studentId: 'ST_DAVID',
      subjectId: 'SUBJ_MATHS',
      eval: 'Devoir 1',
      grade: 10.0,
      evaluationId: 'EV_D1',
      presence: 'present',
    ));
    expect(unauthorizedAdd, isEmpty);

    // =========================================================================
    // SCÉNARIO 3 : Passage au Devoir 2 (Indépendance absolue des notes)
    // =========================================================================
    final devoir2 = EvaluationModel(
      id: 'EV_D2',
      title: 'Devoir 2',
      type: 'devoir',
      number: 2,
      academicYearId: 'AY_2026',
      periodId: 'T1',
      classId: 'C_6A',
      subjectId: 'SUBJ_MATHS',
      status: 'draft',
      maxScore: 20.0,
      createdBy: 'T_MATHS',
      createdAt: DateTime.now().toIso8601String(),
      schoolId: 'SCH_TEST',
    );
    store.addEvaluation(devoir2);

    // Même classe : les 4 élèves existent
    final classStudents =
        store.getStudents().where((s) => s.classId == 'C_6A').toList();
    expect(classStudents.length, equals(4));

    // Les notes du Devoir 1 ne sont PAS copiées sur le Devoir 2
    final gradeJeanD2 =
        store.getGradeByStudentAndEvaluation('ST_JEAN', 'EV_D2');
    expect(gradeJeanD2, isNull);

    // Saisie propre du Devoir 2
    store.addGrade(GradeModel(
      id: 'G_D2_JEAN',
      studentId: 'ST_JEAN',
      subjectId: 'SUBJ_MATHS',
      eval: 'Devoir 2',
      grade: 17.0,
      evaluationId: 'EV_D2',
      presence: 'present',
      enteredBy: 'T_MATHS',
      academicYearId: 'AY_2026',
    ));

    // Jean a bien 15 sur D1 et 17 sur D2
    expect(store.getGradeByStudentAndEvaluation('ST_JEAN', 'EV_D1')?.grade,
        equals(15.0));
    expect(store.getGradeByStudentAndEvaluation('ST_JEAN', 'EV_D2')?.grade,
        equals(17.0));

    // =========================================================================
    // SCÉNARIO 4 : Rejet du Devoir 1 par l'Administration avec motif
    // =========================================================================
    await store.login('admin@demo.test', 'password');
    expect(store.currentUser?.role, equals(UserRole.admin));

    final rejectOk = store.rejectEvaluation(
        'EV_D1', 'Vérifier la note de Paul (copie double comptée)');
    expect(rejectOk, isTrue);

    final rejectedD1 = store.getEvaluationById('EV_D1');
    expect(rejectedD1?.status, equals('rejected'));
    expect(rejectedD1?.rejectionReason,
        equals('Vérifier la note de Paul (copie double comptée)'));

    // L'enseignant se reconnecte et corrige la note de Paul (de 12.0 à 14.0)
    await store.login('teacher@demo.test', 'password');
    final gradePaulD1 =
        store.getGradeByStudentAndEvaluation('ST_PAUL', 'EV_D1');
    expect(gradePaulD1, isNotNull);

    final updatePaulOk = store.updateGrade(
        'G_D1_PAUL',
        GradeModel(
          id: 'G_D1_PAUL',
          studentId: 'ST_PAUL',
          subjectId: 'SUBJ_MATHS',
          eval: 'Devoir 1',
          grade: 14.0,
          evaluationId: 'EV_D1',
          presence: 'present',
          enteredBy: 'T_MATHS',
          academicYearId: 'AY_2026',
        ));
    expect(updatePaulOk, isTrue);
    expect(store.getGradeByStudentAndEvaluation('ST_PAUL', 'EV_D1')?.grade,
        equals(14.0));

    // Resoumission par l'enseignant
    store.submitEvaluation('EV_D1');
    expect(store.getEvaluationById('EV_D1')?.status, equals('submitted'));

    // =========================================================================
    // SCÉNARIO 5 : Validation du Devoir 1 par l'Administration (Verrouillage)
    // =========================================================================
    await store.login('admin@demo.test', 'password');
    final validateOk = store.validateEvaluation('EV_D1');
    expect(validateOk, isTrue);

    final validatedD1 = store.getEvaluationById('EV_D1');
    expect(validatedD1?.status, equals('validated'));

    // Validation du Devoir 2 également
    store.submitEvaluation('EV_D2');
    store.validateEvaluation('EV_D2');
    expect(store.getEvaluationById('EV_D2')?.status, equals('validated'));

    // =========================================================================
    // SCÉNARIO 6 : Création et validation d'une Composition indépendante
    // =========================================================================
    await store.login('teacher@demo.test', 'password');
    final composition = EvaluationModel(
      id: 'EV_COMP_T1',
      title: 'Composition',
      type: 'composition',
      number: null,
      academicYearId: 'AY_2026',
      periodId: 'T1',
      classId: 'C_6A',
      subjectId: 'SUBJ_MATHS',
      status: 'draft',
      maxScore: 20.0,
      createdBy: 'T_MATHS',
      createdAt: DateTime.now().toIso8601String(),
      schoolId: 'SCH_TEST',
    );
    store.addEvaluation(composition);

    // Saisie de la composition pour Jean (16.0)
    store.addGrade(GradeModel(
      id: 'G_COMP_JEAN',
      studentId: 'ST_JEAN',
      subjectId: 'SUBJ_MATHS',
      eval: 'Composition',
      grade: 16.0,
      evaluationId: 'EV_COMP_T1',
      presence: 'present',
      enteredBy: 'T_MATHS',
      academicYearId: 'AY_2026',
    ));

    store.submitEvaluation('EV_COMP_T1');

    await store.login('admin@demo.test', 'password');
    store.validateEvaluation('EV_COMP_T1');
    expect(store.getEvaluationById('EV_COMP_T1')?.status, equals('validated'));

    // =========================================================================
    // SCÉNARIO 7 : Vérification avec le Moteur de Calcul EXISTANT (ResultService)
    // =========================================================================
    // Pour Jean en Maths au T1 :
    // - Devoir 1 : 15.0
    // - Devoir 2 : 17.0
    // -> Moyenne Devoirs (MC) = (15 + 17) / 2 = 16.0
    // - Composition (Compo) = 16.0
    // -> Moyenne Matière = (16.0 + 16.0) / 2 = 16.0
    final resultService = ResultService(store);
    final subjectResultJean = resultService.calculateSubjectResultOfficial(
        'ST_JEAN', 'C_6A', 'SUBJ_MATHS', 'T1');

    expect(subjectResultJean.isCalculable, isTrue);
    expect(subjectResultJean.homeworkAverage, equals(16.0));
    expect(subjectResultJean.compositionGrade, equals(16.0));
    expect(subjectResultJean.subjectAverage, equals(16.0));
    expect(subjectResultJean.coefficient, equals(2.0));
  });
}
