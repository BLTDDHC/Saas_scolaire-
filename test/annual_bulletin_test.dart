import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/data/services/result_service.dart';
import 'package:edupro_flutter_web/data/models/establishment_model.dart';
import 'package:edupro_flutter_web/data/models/academic_year_model.dart';
import 'package:edupro_flutter_web/data/models/class_model.dart';
import 'package:edupro_flutter_web/data/models/subject_model.dart';
import 'package:edupro_flutter_web/data/models/student_model.dart';
import 'package:edupro_flutter_web/data/models/user_model.dart';
import 'package:edupro_flutter_web/data/models/evaluation_model.dart';
import 'package:edupro_flutter_web/data/models/grade_model.dart';
import 'package:edupro_flutter_web/data/models/teacher_model.dart';
import 'package:edupro_flutter_web/data/models/affectation_model.dart';
import 'package:edupro_flutter_web/core/constants/establishment_types.dart';
import 'support/legacy_store_test_harness.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('TEST 1: Student with T1,T2,T3 -> annual averages and ranking',
      () async {
    final store = await createLegacyStore();

    final school = EstablishmentModel(
        id: 'SCH_AN',
        name: 'Annual School',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final year = AcademicYearModel(
        id: 'AYAN',
        name: '2026-2027',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCH_AN');
    store.addAcademicYear(year);

    final cls = ClassModel(
        id: 'C_AN',
        name: 'Classe AN',
        schoolId: 'SCH_AN',
        academicYearId: 'AYAN');
    store.addClass(cls);

    final subj1 = SubjectModel(
        id: 'MATH',
        name: 'Maths',
        coefficient: 4,
        schoolId: 'SCH_AN',
        classes: ['Classe AN']);
    final subj2 = SubjectModel(
        id: 'FRA',
        name: 'Français',
        coefficient: 3,
        schoolId: 'SCH_AN',
        classes: ['Classe AN']);
    final subj3 = SubjectModel(
        id: 'ENG',
        name: 'Anglais',
        coefficient: 2,
        schoolId: 'SCH_AN',
        classes: ['Classe AN']);
    store.addSubject(subj1);
    store.addSubject(subj2);
    store.addSubject(subj3);

    final st1 = StudentModel(
        id: 'S1',
        firstName: 'Anne',
        lastName: 'A',
        className: 'Classe AN',
        classId: 'C_AN',
        schoolId: 'SCH_AN',
        academicYearId: 'AYAN');
    final st2 = StudentModel(
        id: 'S2',
        firstName: 'Ben',
        lastName: 'B',
        className: 'Classe AN',
        classId: 'C_AN',
        schoolId: 'SCH_AN',
        academicYearId: 'AYAN');
    store.addStudent(st1);
    store.addStudent(st2);

    // admin to validate evaluations
    final admin = UserModel(
        id: 'ADMIN_AN',
        name: 'Admin',
        email: 'admin@an.test',
        role: UserRole.admin,
        schoolId: 'SCH_AN');
    store.addUser(admin);

    // For each subject and period create one devoir and one composition per student.
    // Maths: S1 -> 14,15,16 composition same; S2 -> 12,13,14
    // We'll create for each period a devoir (homework) and a composition; to simplify we add one eval of each type.

    // T1
    final evM_T1 = EvaluationModel(
        id: 'EMT1',
        title: 'Math_T1_D',
        type: 'devoir',
        number: 1,
        academicYearId: 'AYAN',
        classId: 'C_AN',
        subjectId: 'MATH',
        createdBy: 'ADMIN_AN',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SCH_AN');
    final evM_T1_id = store.addEvaluation(evM_T1);
    final evM_T1_comp = EvaluationModel(
        id: 'EMC1',
        title: 'Math_T1_C',
        type: 'composition',
        number: 1,
        academicYearId: 'AYAN',
        classId: 'C_AN',
        subjectId: 'MATH',
        createdBy: 'ADMIN_AN',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SCH_AN');
    final evM_T1_comp_id = store.addEvaluation(evM_T1_comp);

    // add grades
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S1',
        subjectId: 'MATH',
        eval: 'D',
        grade: 14.0,
        coef: 1,
        evaluationId: evM_T1_id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S1',
        subjectId: 'MATH',
        eval: 'C',
        grade: 14.0,
        coef: 1,
        evaluationId: evM_T1_comp_id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S2',
        subjectId: 'MATH',
        eval: 'D',
        grade: 12.0,
        coef: 1,
        evaluationId: evM_T1_id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S2',
        subjectId: 'MATH',
        eval: 'C',
        grade: 12.0,
        coef: 1,
        evaluationId: evM_T1_comp_id));

    // T2
    final evM_T2 = EvaluationModel(
        id: 'EMT2',
        title: 'Math_T2_D',
        type: 'devoir',
        number: 1,
        academicYearId: 'AYAN',
        classId: 'C_AN',
        subjectId: 'MATH',
        createdBy: 'ADMIN_AN',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T2',
        schoolId: 'SCH_AN');
    final evM_T2_id = store.addEvaluation(evM_T2);
    final evM_T2_comp = EvaluationModel(
        id: 'EMC2',
        title: 'Math_T2_C',
        type: 'composition',
        number: 1,
        academicYearId: 'AYAN',
        classId: 'C_AN',
        subjectId: 'MATH',
        createdBy: 'ADMIN_AN',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T2',
        schoolId: 'SCH_AN');
    final evM_T2_comp_id = store.addEvaluation(evM_T2_comp);
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S1',
        subjectId: 'MATH',
        eval: 'D',
        grade: 15.0,
        coef: 1,
        evaluationId: evM_T2_id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S1',
        subjectId: 'MATH',
        eval: 'C',
        grade: 15.0,
        coef: 1,
        evaluationId: evM_T2_comp_id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S2',
        subjectId: 'MATH',
        eval: 'D',
        grade: 13.0,
        coef: 1,
        evaluationId: evM_T2_id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S2',
        subjectId: 'MATH',
        eval: 'C',
        grade: 13.0,
        coef: 1,
        evaluationId: evM_T2_comp_id));

    // T3
    final evM_T3 = EvaluationModel(
        id: 'EMT3',
        title: 'Math_T3_D',
        type: 'devoir',
        number: 1,
        academicYearId: 'AYAN',
        classId: 'C_AN',
        subjectId: 'MATH',
        createdBy: 'ADMIN_AN',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T3',
        schoolId: 'SCH_AN');
    final evM_T3_id = store.addEvaluation(evM_T3);
    final evM_T3_comp = EvaluationModel(
        id: 'EMC3',
        title: 'Math_T3_C',
        type: 'composition',
        number: 1,
        academicYearId: 'AYAN',
        classId: 'C_AN',
        subjectId: 'MATH',
        createdBy: 'ADMIN_AN',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T3',
        schoolId: 'SCH_AN');
    final evM_T3_comp_id = store.addEvaluation(evM_T3_comp);
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S1',
        subjectId: 'MATH',
        eval: 'D',
        grade: 16.0,
        coef: 1,
        evaluationId: evM_T3_id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S1',
        subjectId: 'MATH',
        eval: 'C',
        grade: 16.0,
        coef: 1,
        evaluationId: evM_T3_comp_id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S2',
        subjectId: 'MATH',
        eval: 'D',
        grade: 14.0,
        coef: 1,
        evaluationId: evM_T3_id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S2',
        subjectId: 'MATH',
        eval: 'C',
        grade: 14.0,
        coef: 1,
        evaluationId: evM_T3_comp_id));

    // Validate all evaluations
    store.addUser(admin);
    await store.login('admin@an.test', 'pw');
    for (final e
        in store.getEvaluations().where((e) => e.academicYearId == 'AYAN')) {
      store.validateEvaluation(e.id);
      store.lockEvaluation(e.id);
    }

    // Now compute annual bulletin
    final rs = ResultService(store);
    final bulletinS1 = rs.generateAnnualBulletin('C_AN', 'S1');
    final bulletinS2 = rs.generateAnnualBulletin('C_AN', 'S2');

    // Subject maths annual for S1: (14+15+16)/3 = 15.00
    final mathsRow = (bulletinS1['subjects'] as List)
        .firstWhere((r) => r['subjectId'] == 'MATH');
    expect(mathsRow['moyenneAnnuel'], equals(15.00));

    // General average should be calculable (we only added maths in this test, so general == maths)
    expect((bulletinS1['generalAverage'] as double?) != null, isTrue);

    // Ranking: S1 should be ranked above S2
    final rankS1 = (bulletinS1['ranking'] as Map)['rank'];
    final rankS2 = (bulletinS2['ranking'] as Map)['rank'];
    expect(rankS1 is int, isTrue);
    expect(rankS2 is int, isTrue);
    expect(rankS1 < rankS2, isTrue);
  });

  test('TEST 2: Equality of averages yields tied ranks', () async {
    final store = await createLegacyStore();

    final school = EstablishmentModel(
        id: 'SCEQ',
        name: 'Eq School',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final year = AcademicYearModel(
        id: 'AYEQ',
        name: '2026',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCEQ');
    store.addAcademicYear(year);
    final cls = ClassModel(
        id: 'CEQ', name: 'Classe EQ', schoolId: 'SCEQ', academicYearId: 'AYEQ');
    store.addClass(cls);
    final subj = SubjectModel(
        id: 'S_EQ',
        name: 'Subject',
        coefficient: 1,
        schoolId: 'SCEQ',
        classes: ['Classe EQ']);
    store.addSubject(subj);

    final s1 = StudentModel(
        id: 'A',
        firstName: 'A',
        lastName: 'A',
        className: 'Classe EQ',
        classId: 'CEQ',
        schoolId: 'SCEQ',
        academicYearId: 'AYEQ');
    final s2 = StudentModel(
        id: 'B',
        firstName: 'B',
        lastName: 'B',
        className: 'Classe EQ',
        classId: 'CEQ',
        schoolId: 'SCEQ',
        academicYearId: 'AYEQ');
    store.addStudent(s1);
    store.addStudent(s2);

    final admin = UserModel(
        id: 'AD_EQ',
        name: 'Ad',
        email: 'ad@eq.test',
        role: UserRole.admin,
        schoolId: 'SCEQ');
    store.addUser(admin);

    // create validated identical scores for both students across T1/T2/T3
    for (final p in ['T1', 'T2', 'T3']) {
      final evD = EvaluationModel(
          id: 'ED${p}',
          title: 'D_${p}',
          type: 'devoir',
          number: 1,
          academicYearId: 'AYEQ',
          classId: 'CEQ',
          subjectId: 'S_EQ',
          createdBy: 'AD_EQ',
          createdAt: DateTime.now().toIso8601String(),
          periodId: p,
          schoolId: 'SCEQ');
      final evC = EvaluationModel(
          id: 'EC${p}',
          title: 'C_${p}',
          type: 'composition',
          number: 1,
          academicYearId: 'AYEQ',
          classId: 'CEQ',
          subjectId: 'S_EQ',
          createdBy: 'AD_EQ',
          createdAt: DateTime.now().toIso8601String(),
          periodId: p,
          schoolId: 'SCEQ');
      store.addEvaluation(evD);
      store.addEvaluation(evC);
      store.addGrade(GradeModel(
          id: '',
          studentId: 'A',
          subjectId: 'S_EQ',
          eval: 'D',
          grade: 15.0,
          coef: 1,
          evaluationId: evD.id));
      store.addGrade(GradeModel(
          id: '',
          studentId: 'A',
          subjectId: 'S_EQ',
          eval: 'C',
          grade: 15.0,
          coef: 1,
          evaluationId: evC.id));
      store.addGrade(GradeModel(
          id: '',
          studentId: 'B',
          subjectId: 'S_EQ',
          eval: 'D',
          grade: 15.0,
          coef: 1,
          evaluationId: evD.id));
      store.addGrade(GradeModel(
          id: '',
          studentId: 'B',
          subjectId: 'S_EQ',
          eval: 'C',
          grade: 15.0,
          coef: 1,
          evaluationId: evC.id));
    }

    await store.login('ad@eq.test', legacyTestPassword);
    for (final e
        in store.getEvaluations().where((e) => e.academicYearId == 'AYEQ')) {
      store.validateEvaluation(e.id);
      store.lockEvaluation(e.id);
    }

    final rs = ResultService(store);
    final bA = rs.generateAnnualBulletin('CEQ', 'A');
    final bB = rs.generateAnnualBulletin('CEQ', 'B');

    final rA = (bA['ranking'] as Map)['rank'];
    final rB = (bB['ranking'] as Map)['rank'];
    expect(rA, equals(1));
    expect(rB, equals(1));
  });

  test('TEST 3: Missing T3 -> Non calculable', () async {
    final store = await createLegacyStore();

    final school = EstablishmentModel(
        id: 'SCHM',
        name: 'Miss School',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final year = AcademicYearModel(
        id: 'AYM',
        name: 'AYM',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCHM');
    store.addAcademicYear(year);
    final c = ClassModel(
        id: 'CM', name: 'Classe M', schoolId: 'SCHM', academicYearId: 'AYM');
    store.addClass(c);
    final subj = SubjectModel(
        id: 'SM',
        name: 'SubjectM',
        coefficient: 1,
        schoolId: 'SCHM',
        classes: ['Classe M']);
    store.addSubject(subj);
    final s = StudentModel(
        id: 'SX',
        firstName: 'X',
        lastName: 'X',
        className: 'Classe M',
        classId: 'CM',
        schoolId: 'SCHM',
        academicYearId: 'AYM');
    store.addStudent(s);
    final admin = UserModel(
        id: 'ADM_M',
        name: 'AdmM',
        email: 'adm@mm.test',
        role: UserRole.admin,
        schoolId: 'SCHM');
    store.addUser(admin);
    await store.login('adm@mm.test', 'pw');

    // Create only T1 and T2 evaluations and validate
    for (final p in ['T1', 'T2']) {
      final evD = EvaluationModel(
          id: 'EDM${p}',
          title: 'D_${p}',
          type: 'devoir',
          number: 1,
          academicYearId: 'AYM',
          classId: 'CM',
          subjectId: 'SM',
          createdBy: 'ADM_M',
          createdAt: DateTime.now().toIso8601String(),
          periodId: p,
          schoolId: 'SCHM');
      final evC = EvaluationModel(
          id: 'ECM${p}',
          title: 'C_${p}',
          type: 'composition',
          number: 1,
          academicYearId: 'AYM',
          classId: 'CM',
          subjectId: 'SM',
          createdBy: 'ADM_M',
          createdAt: DateTime.now().toIso8601String(),
          periodId: p,
          schoolId: 'SCHM');
      store.addEvaluation(evD);
      store.addEvaluation(evC);
      store.addGrade(GradeModel(
          id: '',
          studentId: 'SX',
          subjectId: 'SM',
          eval: 'D',
          grade: 12.0,
          coef: 1,
          evaluationId: evD.id));
      store.addGrade(GradeModel(
          id: '',
          studentId: 'SX',
          subjectId: 'SM',
          eval: 'C',
          grade: 12.0,
          coef: 1,
          evaluationId: evC.id));
    }

    for (final e
        in store.getEvaluations().where((e) => e.academicYearId == 'AYM')) {
      store.validateEvaluation(e.id);
      store.lockEvaluation(e.id);
    }

    final rs = ResultService(store);
    final b = rs.generateAnnualBulletin('CM', 'SX');
    expect((b['generalAverage'] as double?) == null, isTrue);
  });

  test('TEST 4: Arrival at T2 is not treated as zero (Non calculable)',
      () async {
    final store = await createLegacyStore();

    final school = EstablishmentModel(
        id: 'SCHA2',
        name: 'Arr School',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final year = AcademicYearModel(
        id: 'AYA2',
        name: 'AYA2',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCHA2');
    store.addAcademicYear(year);
    final c = ClassModel(
        id: 'CA2',
        name: 'Classe A2',
        schoolId: 'SCHA2',
        academicYearId: 'AYA2');
    store.addClass(c);
    final subj = SubjectModel(
        id: 'SUBA2',
        name: 'SubA2',
        coefficient: 1,
        schoolId: 'SCHA2',
        classes: ['Classe A2']);
    store.addSubject(subj);

    // student arrives at T2 -> we only add T2 and T3
    final s = StudentModel(
        id: 'ARR1',
        firstName: 'Arr',
        lastName: 'One',
        className: 'Classe A2',
        classId: 'CA2',
        schoolId: 'SCHA2',
        academicYearId: 'AYA2');
    store.addStudent(s);

    final admin = UserModel(
        id: 'AD_A2',
        name: 'Ad',
        email: 'ad2@a2.test',
        role: UserRole.admin,
        schoolId: 'SCHA2');
    store.addUser(admin);
    await store.login('ad2@a2.test', 'pw');

    // only T2 and T3
    for (final p in ['T2', 'T3']) {
      final evD = EvaluationModel(
          id: 'E${p}A2',
          title: 'D_${p}',
          type: 'devoir',
          number: 1,
          academicYearId: 'AYA2',
          classId: 'CA2',
          subjectId: 'SUBA2',
          createdBy: 'AD_A2',
          createdAt: DateTime.now().toIso8601String(),
          periodId: p,
          schoolId: 'SCHA2');
      final evC = EvaluationModel(
          id: 'EC${p}A2',
          title: 'C_${p}',
          type: 'composition',
          number: 1,
          academicYearId: 'AYA2',
          classId: 'CA2',
          subjectId: 'SUBA2',
          createdBy: 'AD_A2',
          createdAt: DateTime.now().toIso8601String(),
          periodId: p,
          schoolId: 'SCHA2');
      store.addEvaluation(evD);
      store.addEvaluation(evC);
      store.addGrade(GradeModel(
          id: '',
          studentId: 'ARR1',
          subjectId: 'SUBA2',
          eval: 'D',
          grade: 13.0,
          coef: 1,
          evaluationId: evD.id));
      store.addGrade(GradeModel(
          id: '',
          studentId: 'ARR1',
          subjectId: 'SUBA2',
          eval: 'C',
          grade: 13.0,
          coef: 1,
          evaluationId: evC.id));
    }

    for (final e
        in store.getEvaluations().where((e) => e.academicYearId == 'AYA2')) {
      store.validateEvaluation(e.id);
      store.lockEvaluation(e.id);
    }

    final rs = ResultService(store);
    final b = rs.generateAnnualBulletin('CA2', 'ARR1');
    expect((b['generalAverage'] as double?) == null, isTrue);
  });

  test(
      'TEST 6 & 7: Ranking across two classes and isolation between establishments',
      () async {
    final store = await createLegacyStore();

    // School A
    final sa = EstablishmentModel(
        id: 'SCHA6',
        name: 'SchA6',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(sa);
    final aya = AcademicYearModel(
        id: 'A6',
        name: 'A6',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCHA6');
    store.addAcademicYear(aya);
    final c1 = ClassModel(
        id: 'CL1', name: 'C1', schoolId: 'SCHA6', academicYearId: 'A6');
    final c2 = ClassModel(
        id: 'CL2', name: 'C2', schoolId: 'SCHA6', academicYearId: 'A6');
    store.addClass(c1);
    store.addClass(c2);
    final subj = SubjectModel(
        id: 'SSX',
        name: 'SubX',
        coefficient: 1,
        schoolId: 'SCHA6',
        classes: ['C1', 'C2']);
    store.addSubject(subj);

    final saAdmin = UserModel(
        id: 'AD6',
        name: 'Ad6',
        email: 'ad6@a6.test',
        role: UserRole.admin,
        schoolId: 'SCHA6');
    store.addUser(saAdmin);

    final sA1 = StudentModel(
        id: 'A1',
        firstName: 'A1',
        lastName: 'A',
        className: 'C1',
        classId: 'CL1',
        schoolId: 'SCHA6',
        academicYearId: 'A6');
    final sA2 = StudentModel(
        id: 'A2',
        firstName: 'A2',
        lastName: 'A',
        className: 'C2',
        classId: 'CL2',
        schoolId: 'SCHA6',
        academicYearId: 'A6');
    store.addStudent(sA1);
    store.addStudent(sA2);

    // add identical validated full-year results so class rankings compare within class
    for (final p in ['T1', 'T2', 'T3']) {
      final evD = EvaluationModel(
          id: 'EV${p}X',
          title: 'D_${p}',
          type: 'devoir',
          number: 1,
          academicYearId: 'A6',
          classId: 'CL1',
          subjectId: 'SSX',
          createdBy: 'AD6',
          createdAt: DateTime.now().toIso8601String(),
          periodId: p,
          schoolId: 'SCHA6');
      final evC = EvaluationModel(
          id: 'EVC${p}X',
          title: 'C_${p}',
          type: 'composition',
          number: 1,
          academicYearId: 'A6',
          classId: 'CL1',
          subjectId: 'SSX',
          createdBy: 'AD6',
          createdAt: DateTime.now().toIso8601String(),
          periodId: p,
          schoolId: 'SCHA6');
      store.addEvaluation(evD);
      store.addEvaluation(evC);
      // for class1 student
      store.addGrade(GradeModel(
          id: '',
          studentId: 'A1',
          subjectId: 'SSX',
          eval: 'D',
          grade: 16.0,
          coef: 1,
          evaluationId: evD.id));
      store.addGrade(GradeModel(
          id: '',
          studentId: 'A1',
          subjectId: 'SSX',
          eval: 'C',
          grade: 16.0,
          coef: 1,
          evaluationId: evC.id));
      // for class2 student - create corresponding evaluations with classId CL2
      final evD2 = EvaluationModel(
          id: 'EV${p}X2',
          title: 'D2_${p}',
          type: 'devoir',
          number: 1,
          academicYearId: 'A6',
          classId: 'CL2',
          subjectId: 'SSX',
          createdBy: 'AD6',
          createdAt: DateTime.now().toIso8601String(),
          periodId: p,
          schoolId: 'SCHA6');
      final evC2 = EvaluationModel(
          id: 'EVC${p}X2',
          title: 'C2_${p}',
          type: 'composition',
          number: 1,
          academicYearId: 'A6',
          classId: 'CL2',
          subjectId: 'SSX',
          createdBy: 'AD6',
          createdAt: DateTime.now().toIso8601String(),
          periodId: p,
          schoolId: 'SCHA6');
      store.addEvaluation(evD2);
      store.addEvaluation(evC2);
      store.addGrade(GradeModel(
          id: '',
          studentId: 'A2',
          subjectId: 'SSX',
          eval: 'D',
          grade: 12.0,
          coef: 1,
          evaluationId: evD2.id));
      store.addGrade(GradeModel(
          id: '',
          studentId: 'A2',
          subjectId: 'SSX',
          eval: 'C',
          grade: 12.0,
          coef: 1,
          evaluationId: evC2.id));
    }

    await store.login('ad6@a6.test', legacyTestPassword);
    for (final e
        in store.getEvaluations().where((e) => e.academicYearId == 'A6')) {
      expect(store.validateEvaluation(e.id), isTrue);
      store.lockEvaluation(e.id);
    }
    expect(store.getGrades().where((grade) => grade.studentId == 'A2'),
        hasLength(6));
    expect(
      store.getEvaluations().where((evaluation) =>
          evaluation.classId == 'CL2' &&
          (evaluation.status == 'validated' || evaluation.status == 'locked')),
      hasLength(6),
    );

    final rs = ResultService(store);
    final b1 = rs.generateAnnualBulletin('CL1', 'A1');
    final b2 = rs.generateAnnualBulletin('CL2', 'A2');

    expect((b1['generalAverage'] as double?) != null, isTrue);
    expect((b2['generalAverage'] as double?) != null, isTrue);

    // Rankings should be computed within class context
    expect((b1['ranking'] as Map)['rank'], equals(1));
    expect((b2['ranking'] as Map)['rank'], equals(1));

    // Now ensure school B student does not affect A's ranking
    final sb = EstablishmentModel(
        id: 'SCHB6',
        name: 'SchB6',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(sb);
    final yb = AcademicYearModel(
        id: 'AB6',
        name: 'AB6',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCHB6');
    store.addAcademicYear(yb);
    final cb = ClassModel(
        id: 'CB', name: 'CB', schoolId: 'SCHB6', academicYearId: 'AB6');
    store.addClass(cb);
    final subjB = SubjectModel(
        id: 'SBX',
        name: 'SubB',
        coefficient: 1,
        schoolId: 'SCHB6',
        classes: ['CB']);
    store.addSubject(subjB);
    final sB = StudentModel(
        id: 'B1',
        firstName: 'B1',
        lastName: 'B1',
        className: 'CB',
        classId: 'CB',
        schoolId: 'SCHB6',
        academicYearId: 'AB6');
    store.addStudent(sB);
    final adminB = UserModel(
        id: 'ADB6',
        name: 'AdB',
        email: 'adb6@b6.test',
        role: UserRole.admin,
        schoolId: 'SCHB6');
    store.addUser(adminB);
    await store.login('adb6@b6.test', 'pw');
    final evb = EvaluationModel(
        id: 'EVBB',
        title: 'EB',
        type: 'devoir',
        number: 1,
        academicYearId: 'AB6',
        classId: 'CB',
        subjectId: 'SBX',
        createdBy: 'ADB6',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SCHB6');
    store.addEvaluation(evb);
    store.addGrade(GradeModel(
        id: '',
        studentId: 'B1',
        subjectId: 'SBX',
        eval: 'D',
        grade: 20.0,
        coef: 1,
        evaluationId: evb.id));
    store.validateEvaluation(evb.id);
    store.lockEvaluation(evb.id);

    final bA1 = rs.generateAnnualBulletin('CL1', 'A1');
    // ensure B1 not considered in A1's effectif
    expect((bA1['ranking'] as Map)['effectif'], isNotNull);
  });

  test('TEST 9: Unvalidated evaluations are ignored in annual bulletin',
      () async {
    final store = await createLegacyStore();

    final school = EstablishmentModel(
        id: 'SCHU',
        name: 'Unv School',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final year = AcademicYearModel(
        id: 'AYU',
        name: 'AYU',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCHU');
    store.addAcademicYear(year);
    final c = ClassModel(
        id: 'CU', name: 'Classe U', schoolId: 'SCHU', academicYearId: 'AYU');
    store.addClass(c);
    final subj = SubjectModel(
        id: 'SU',
        name: 'SubU',
        coefficient: 1,
        schoolId: 'SCHU',
        classes: ['Classe U']);
    store.addSubject(subj);
    final s = StudentModel(
        id: 'UX',
        firstName: 'U',
        lastName: 'X',
        className: 'Classe U',
        classId: 'CU',
        schoolId: 'SCHU',
        academicYearId: 'AYU');
    store.addStudent(s);

    final admin = UserModel(
        id: 'ADU',
        name: 'ADU',
        email: 'adu@u.test',
        role: UserRole.admin,
        schoolId: 'SCHU');
    store.addUser(admin);
    await store.login('adu@u.test', 'pw');

    // create a draft evaluation (not validated)
    final evD = EvaluationModel(
        id: 'EDU1',
        title: 'D_U1',
        type: 'devoir',
        number: 1,
        academicYearId: 'AYU',
        classId: 'CU',
        subjectId: 'SU',
        createdBy: 'ADU',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SCHU');
    store.addEvaluation(evD);
    store.addGrade(GradeModel(
        id: '',
        studentId: 'UX',
        subjectId: 'SU',
        eval: 'D',
        grade: 18.0,
        coef: 1,
        evaluationId: evD.id));

    final rs = ResultService(store);
    final b = rs.generateAnnualBulletin('CU', 'UX');
    // since evaluation not validated, annual general should be non calculable
    expect((b['generalAverage'] as double?) == null, isTrue);
  });

  test('TEST 5: Student changing class preserves historical results', () async {
    final store = await createLegacyStore();

    final school = EstablishmentModel(
        id: 'SCHCH',
        name: 'Change School',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final year = AcademicYearModel(
        id: 'AYCH',
        name: 'AYCH',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCHCH');
    store.addAcademicYear(year);
    final c1 = ClassModel(
        id: 'CLCH1', name: 'C1', schoolId: 'SCHCH', academicYearId: 'AYCH');
    final c2 = ClassModel(
        id: 'CLCH2', name: 'C2', schoolId: 'SCHCH', academicYearId: 'AYCH');
    store.addClass(c1);
    store.addClass(c2);
    final subj = SubjectModel(
        id: 'SCHSUB',
        name: 'SubjectCH',
        coefficient: 1,
        schoolId: 'SCHCH',
        classes: ['C1', 'C2']);
    store.addSubject(subj);

    final s = StudentModel(
        id: 'STCH',
        firstName: 'Ch',
        lastName: 'One',
        className: 'C1',
        classId: 'CLCH1',
        schoolId: 'SCHCH',
        academicYearId: 'AYCH');
    store.addStudent(s);

    final admin = UserModel(
        id: 'ADCH',
        name: 'AdCh',
        email: 'adch@ch.test',
        role: UserRole.admin,
        schoolId: 'SCHCH');
    store.addUser(admin);

    // T1 in class C1
    final e1 = EvaluationModel(
        id: 'ECH1',
        title: 'D_T1',
        type: 'devoir',
        number: 1,
        academicYearId: 'AYCH',
        classId: 'CLCH1',
        subjectId: 'SCHSUB',
        createdBy: 'ADCH',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SCHCH');
    final c1Eval = EvaluationModel(
        id: 'CCH1',
        title: 'C_T1',
        type: 'composition',
        number: 1,
        academicYearId: 'AYCH',
        classId: 'CLCH1',
        subjectId: 'SCHSUB',
        createdBy: 'ADCH',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SCHCH');
    store.addEvaluation(e1);
    store.addEvaluation(c1Eval);
    store.addGrade(GradeModel(
        id: '',
        studentId: 'STCH',
        subjectId: 'SCHSUB',
        eval: 'D',
        grade: 12.0,
        coef: 1,
        evaluationId: e1.id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'STCH',
        subjectId: 'SCHSUB',
        eval: 'C',
        grade: 12.0,
        coef: 1,
        evaluationId: c1Eval.id));

    // Move student to class C2
    store.updateStudent(s.copyWith(classId: 'CLCH2', className: 'C2'));

    // T2 in class C2
    final e2 = EvaluationModel(
        id: 'ECH2',
        title: 'D_T2',
        type: 'devoir',
        number: 1,
        academicYearId: 'AYCH',
        classId: 'CLCH2',
        subjectId: 'SCHSUB',
        createdBy: 'ADCH',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T2',
        schoolId: 'SCHCH');
    final c2Eval = EvaluationModel(
        id: 'CCH2',
        title: 'C_T2',
        type: 'composition',
        number: 1,
        academicYearId: 'AYCH',
        classId: 'CLCH2',
        subjectId: 'SCHSUB',
        createdBy: 'ADCH',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T2',
        schoolId: 'SCHCH');
    store.addEvaluation(e2);
    store.addEvaluation(c2Eval);
    store.addGrade(GradeModel(
        id: '',
        studentId: 'STCH',
        subjectId: 'SCHSUB',
        eval: 'D',
        grade: 14.0,
        coef: 1,
        evaluationId: e2.id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'STCH',
        subjectId: 'SCHSUB',
        eval: 'C',
        grade: 14.0,
        coef: 1,
        evaluationId: c2Eval.id));

    // T3 in class C2
    final e3 = EvaluationModel(
        id: 'ECH3',
        title: 'D_T3',
        type: 'devoir',
        number: 1,
        academicYearId: 'AYCH',
        classId: 'CLCH2',
        subjectId: 'SCHSUB',
        createdBy: 'ADCH',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T3',
        schoolId: 'SCHCH');
    final c3Eval = EvaluationModel(
        id: 'CCH3',
        title: 'C_T3',
        type: 'composition',
        number: 1,
        academicYearId: 'AYCH',
        classId: 'CLCH2',
        subjectId: 'SCHSUB',
        createdBy: 'ADCH',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T3',
        schoolId: 'SCHCH');
    store.addEvaluation(e3);
    store.addEvaluation(c3Eval);
    store.addGrade(GradeModel(
        id: '',
        studentId: 'STCH',
        subjectId: 'SCHSUB',
        eval: 'D',
        grade: 13.0,
        coef: 1,
        evaluationId: e3.id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'STCH',
        subjectId: 'SCHSUB',
        eval: 'C',
        grade: 13.0,
        coef: 1,
        evaluationId: c3Eval.id));

    // validate and lock all
    await store.login('adch@ch.test', legacyTestPassword);
    for (final e
        in store.getEvaluations().where((e) => e.academicYearId == 'AYCH')) {
      store.validateEvaluation(e.id);
      store.lockEvaluation(e.id);
    }

    final rs = ResultService(store);
    final b = rs.generateAnnualBulletin('CLCH2', 'STCH');
    final subjRow =
        (b['subjects'] as List).firstWhere((r) => r['subjectId'] == 'SCHSUB');
    final per = subjRow['periodAverages'] as List;
    // T1 should be present even though student was in C1 at the time
    expect(per[0], equals(12.0));
    expect(per[1], equals(14.0));
    expect(per[2], equals(13.0));
  });

  test('TEST 8: Modification after approval updates annual computations',
      () async {
    final store = await createLegacyStore();

    final school = EstablishmentModel(
        id: 'SCHA8',
        name: 'Mod School',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final year = AcademicYearModel(
        id: 'AYA8',
        name: 'AYA8',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCHA8');
    store.addAcademicYear(year);
    final c = ClassModel(
        id: 'CL8', name: 'CL8', schoolId: 'SCHA8', academicYearId: 'AYA8');
    store.addClass(c);
    final subj = SubjectModel(
        id: 'SUB8',
        name: 'Sub8',
        coefficient: 1,
        schoolId: 'SCHA8',
        classes: ['CL8']);
    store.addSubject(subj);
    final s = StudentModel(
        id: 'ST8',
        firstName: 'Mod',
        lastName: 'Eight',
        className: 'CL8',
        classId: 'CL8',
        schoolId: 'SCHA8',
        academicYearId: 'AYA8');
    store.addStudent(s);

    // admin and teacher
    final admin = UserModel(
        id: 'AD8',
        name: 'AD8',
        email: 'ad8@a8.test',
        role: UserRole.admin,
        schoolId: 'SCHA8');
    store.addUser(admin);
    final teacher = UserModel(
        id: 'T8',
        name: 'T8',
        email: 't8@a8.test',
        role: UserRole.teacher,
        schoolId: 'SCHA8');
    store.addUser(teacher);
    // create affectation so teacher can request
    store.addTeacher(TeacherModel(
        id: 'T8', firstName: 'T', lastName: 'Eight', schoolId: 'SCHA8'));
    store.addAffectation(AffectationModel(
        id: 'AFF8',
        teacherId: 'T8',
        teacherName: 'T8',
        subjectId: 'SUB8',
        classId: 'CL8',
        schoolId: 'SCHA8',
        academicYearId: 'AYA8'));

    // T1/T2/T3 evaluations and grades
    final e1 = EvaluationModel(
        id: 'EV8_1',
        title: 'D1',
        type: 'devoir',
        number: 1,
        academicYearId: 'AYA8',
        classId: 'CL8',
        subjectId: 'SUB8',
        createdBy: 'AD8',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SCHA8');
    final e2 = EvaluationModel(
        id: 'EV8_2',
        title: 'D2',
        type: 'devoir',
        number: 1,
        academicYearId: 'AYA8',
        classId: 'CL8',
        subjectId: 'SUB8',
        createdBy: 'AD8',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T2',
        schoolId: 'SCHA8');
    final e3 = EvaluationModel(
        id: 'EV8_3',
        title: 'D3',
        type: 'devoir',
        number: 1,
        academicYearId: 'AYA8',
        classId: 'CL8',
        subjectId: 'SUB8',
        createdBy: 'AD8',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T3',
        schoolId: 'SCHA8');
    final compositions = [
      EvaluationModel(
          id: 'CV8_1',
          title: 'C1',
          type: 'composition',
          number: 1,
          academicYearId: 'AYA8',
          classId: 'CL8',
          subjectId: 'SUB8',
          createdBy: 'AD8',
          createdAt: DateTime.now().toIso8601String(),
          periodId: 'T1',
          schoolId: 'SCHA8'),
      EvaluationModel(
          id: 'CV8_2',
          title: 'C2',
          type: 'composition',
          number: 1,
          academicYearId: 'AYA8',
          classId: 'CL8',
          subjectId: 'SUB8',
          createdBy: 'AD8',
          createdAt: DateTime.now().toIso8601String(),
          periodId: 'T2',
          schoolId: 'SCHA8'),
      EvaluationModel(
          id: 'CV8_3',
          title: 'C3',
          type: 'composition',
          number: 1,
          academicYearId: 'AYA8',
          classId: 'CL8',
          subjectId: 'SUB8',
          createdBy: 'AD8',
          createdAt: DateTime.now().toIso8601String(),
          periodId: 'T3',
          schoolId: 'SCHA8'),
    ];
    store.addEvaluation(e1);
    store.addEvaluation(e2);
    store.addEvaluation(e3);
    for (final composition in compositions) {
      store.addEvaluation(composition);
      store.addGrade(GradeModel(
          id: '',
          studentId: 'ST8',
          subjectId: 'SUB8',
          eval: 'C',
          grade: 14.0,
          coef: 1,
          evaluationId: composition.id));
    }
    // add grades; keep id for T2 to modify
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST8',
        subjectId: 'SUB8',
        eval: 'D',
        grade: 14.0,
        coef: 1,
        evaluationId: e1.id));
    final g2 = store.addGrade(GradeModel(
        id: '',
        studentId: 'ST8',
        subjectId: 'SUB8',
        eval: 'D',
        grade: 14.0,
        coef: 1,
        evaluationId: e2.id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST8',
        subjectId: 'SUB8',
        eval: 'D',
        grade: 14.0,
        coef: 1,
        evaluationId: e3.id));

    // validate & lock
    await store.login('ad8@a8.test', 'pw');
    for (final e
        in store.getEvaluations().where((e) => e.academicYearId == 'AYA8')) {
      store.validateEvaluation(e.id);
      store.lockEvaluation(e.id);
    }

    final rs = ResultService(store);
    final before = rs.generateAnnualBulletin('CL8', 'ST8');
    final beforeAvg = before['generalAverage'] as double?;

    // Teacher requests modification for T2
    await store.login('t8@a8.test', 'pw');
    final reqId = store.requestGradeModification(
        gradeId: g2, newValue: 16.0, reason: 'Correction');
    expect(reqId, isNotEmpty);

    // Admin approves
    await store.login('ad8@a8.test', 'pw');
    expect(store.approveGradeModification(reqId), isTrue);

    // Teacher applies modification
    await store.login('t8@a8.test', 'pw');
    final ok = store.updateGrade(
        g2,
        GradeModel(
            id: g2,
            studentId: 'ST8',
            subjectId: 'SUB8',
            eval: 'D',
            grade: 16.0,
            coef: 1,
            evaluationId: e2.id));
    expect(ok, isTrue);

    // After modification, revalidate and lock
    await store.login('ad8@a8.test', 'pw');
    expect(store.validateEvaluation(e2.id), isTrue);
    store.lockEvaluation(e2.id);
    expect(store.validateEvaluation(compositions[1].id), isTrue);
    store.lockEvaluation(compositions[1].id);

    final after = rs.generateAnnualBulletin('CL8', 'ST8');
    final afterAvg = after['generalAverage'] as double?;
    expect(store.getGrades().where((grade) => grade.studentId == 'ST8'),
        hasLength(6));
    expect(
      store.getEvaluations().where((evaluation) =>
          evaluation.academicYearId == 'AYA8' &&
          (evaluation.status == 'validated' || evaluation.status == 'locked')),
      hasLength(6),
    );
    expect(afterAvg != null, isTrue);
    expect(afterAvg, isNot(equals(beforeAvg)));
  });

  test(
      'TEST 10: Bulletin locked prevents silent modifications; requests still work',
      () async {
    final store = await createLegacyStore();

    final school = EstablishmentModel(
        id: 'SCH10',
        name: 'Lock School',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final year = AcademicYearModel(
        id: 'AY10',
        name: 'AY10',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCH10');
    store.addAcademicYear(year);
    final c = ClassModel(
        id: 'CL10', name: 'CL10', schoolId: 'SCH10', academicYearId: 'AY10');
    store.addClass(c);
    final subj = SubjectModel(
        id: 'SUB10',
        name: 'Sub10',
        coefficient: 1,
        schoolId: 'SCH10',
        classes: ['CL10']);
    store.addSubject(subj);
    final s = StudentModel(
        id: 'ST10',
        firstName: 'Lock',
        lastName: 'Ten',
        className: 'CL10',
        classId: 'CL10',
        schoolId: 'SCH10',
        academicYearId: 'AY10');
    store.addStudent(s);

    final admin = UserModel(
        id: 'AD10',
        name: 'AD10',
        email: 'ad10@a10.test',
        role: UserRole.admin,
        schoolId: 'SCH10');
    store.addUser(admin);
    final teacher = UserModel(
        id: 'T10',
        name: 'T10',
        email: 't10@a10.test',
        role: UserRole.teacher,
        schoolId: 'SCH10');
    store.addUser(teacher);
    store.addTeacher(TeacherModel(
        id: 'T10', firstName: 'T', lastName: 'Ten', schoolId: 'SCH10'));
    store.addAffectation(AffectationModel(
        id: 'AFF10',
        teacherId: 'T10',
        teacherName: 'T10',
        subjectId: 'SUB10',
        classId: 'CL10',
        schoolId: 'SCH10',
        academicYearId: 'AY10'));

    final e1 = EvaluationModel(
        id: 'EV10_1',
        title: 'D1',
        type: 'devoir',
        number: 1,
        academicYearId: 'AY10',
        classId: 'CL10',
        subjectId: 'SUB10',
        createdBy: 'AD10',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SCH10');
    store.addEvaluation(e1);
    final g1 = store.addGrade(GradeModel(
        id: '',
        studentId: 'ST10',
        subjectId: 'SUB10',
        eval: 'D',
        grade: 12.0,
        coef: 1,
        evaluationId: e1.id));
    await store.login('ad10@a10.test', 'pw');
    store.validateEvaluation(e1.id);
    store.lockEvaluation(e1.id);

    // Lock the annual bulletin
    store.lockAnnualBulletin('ST10', 'AY10');

    // Admin tries to modify grade directly -> should be refused
    final attempt = store.updateGrade(
        g1,
        GradeModel(
            id: g1,
            studentId: 'ST10',
            subjectId: 'SUB10',
            eval: 'D',
            grade: 15.0,
            coef: 1,
            evaluationId: e1.id));
    expect(attempt, isFalse);

    // Teacher requests modification
    await store.login('t10@a10.test', 'pw');
    final reqId = store.requestGradeModification(
        gradeId: g1, newValue: 15.0, reason: 'Appeal');
    expect(reqId, isNotEmpty);

    // Admin approves
    await store.login('ad10@a10.test', 'pw');
    expect(store.approveGradeModification(reqId), isTrue);

    // Teacher applies modification
    await store.login('t10@a10.test', 'pw');
    final ok = store.updateGrade(
        g1,
        GradeModel(
            id: g1,
            studentId: 'ST10',
            subjectId: 'SUB10',
            eval: 'D',
            grade: 15.0,
            coef: 1,
            evaluationId: e1.id));
    expect(ok, isTrue);
  });
}
