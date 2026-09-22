import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/data/services/result_service.dart';
import 'package:edupro_flutter_web/data/models/establishment_model.dart';
import 'package:edupro_flutter_web/data/models/academic_year_model.dart';
import 'package:edupro_flutter_web/data/models/class_model.dart';
import 'package:edupro_flutter_web/data/models/subject_model.dart';
import 'package:edupro_flutter_web/data/models/student_model.dart';
import 'package:edupro_flutter_web/data/models/evaluation_model.dart';
import 'package:edupro_flutter_web/data/models/grade_model.dart';
import 'package:edupro_flutter_web/core/constants/establishment_types.dart';
import 'package:edupro_flutter_web/data/models/user_model.dart';
import 'support/legacy_store_test_harness.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('MC single devoir', () async {
    final store = StoreService();
    await store.init();
    final school = EstablishmentModel(
        id: 'SC1',
        name: 'S1',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final y = AcademicYearModel(
        id: 'Y1',
        name: 'Y1',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SC1');
    store.addAcademicYear(y);
    final c = ClassModel(
        id: 'CL1', name: 'C1', schoolId: 'SC1', academicYearId: 'Y1');
    store.addClass(c);
    final subj = SubjectModel(
        id: 'SJ1',
        name: 'Sub1',
        coefficient: 1,
        schoolId: 'SC1',
        classes: ['C1']);
    store.addSubject(subj);
    final s = StudentModel(
        id: 'ST1',
        firstName: 'A',
        lastName: 'A',
        className: 'C1',
        classId: 'CL1',
        schoolId: 'SC1',
        academicYearId: 'Y1');
    store.addStudent(s);

    final ev = EvaluationModel(
        id: 'EV1',
        title: 'D1',
        type: 'devoir',
        number: 1,
        academicYearId: 'Y1',
        classId: 'CL1',
        subjectId: 'SJ1',
        createdBy: 'ADM',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SC1');
    store.addEvaluation(ev);
    // add grade
    final g = GradeModel(
        id: '',
        studentId: 'ST1',
        subjectId: 'SJ1',
        eval: 'D1',
        grade: 12.0,
        coef: 1,
        evaluationId: ev.id);
    store.addGrade(g);

    final mc = ResultService.calculateHomeworkAverageFromGrades(
        store.getGrades(),
        store.getEvaluations(),
        'ST1',
        'CL1',
        'SJ1',
        'T1',
        'Y1');
    expect(mc, equals(12.0));
  });

  test('MC two devoirs', () async {
    final store = StoreService();
    await store.init();
    final school = EstablishmentModel(
        id: 'SC2',
        name: 'S2',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final y = AcademicYearModel(
        id: 'Y2',
        name: 'Y2',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SC2');
    store.addAcademicYear(y);
    final c = ClassModel(
        id: 'CL2', name: 'C2', schoolId: 'SC2', academicYearId: 'Y2');
    store.addClass(c);
    final subj = SubjectModel(
        id: 'SJ2',
        name: 'Sub2',
        coefficient: 1,
        schoolId: 'SC2',
        classes: ['C2']);
    store.addSubject(subj);
    final s = StudentModel(
        id: 'ST2',
        firstName: 'B',
        lastName: 'B',
        className: 'C2',
        classId: 'CL2',
        schoolId: 'SC2',
        academicYearId: 'Y2');
    store.addStudent(s);

    final e1 = EvaluationModel(
        id: 'E1',
        title: 'D1',
        type: 'devoir',
        number: 1,
        academicYearId: 'Y2',
        classId: 'CL2',
        subjectId: 'SJ2',
        createdBy: 'ADM',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SC2');
    final e2 = EvaluationModel(
        id: 'E2',
        title: 'D2',
        type: 'devoir',
        number: 2,
        academicYearId: 'Y2',
        classId: 'CL2',
        subjectId: 'SJ2',
        createdBy: 'ADM',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SC2');
    store.addEvaluation(e1);
    store.addEvaluation(e2);
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST2',
        subjectId: 'SJ2',
        eval: 'D1',
        grade: 12.0,
        coef: 1,
        evaluationId: e1.id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST2',
        subjectId: 'SJ2',
        eval: 'D2',
        grade: 14.0,
        coef: 1,
        evaluationId: e2.id));

    final mc = ResultService.calculateHomeworkAverageFromGrades(
        store.getGrades(),
        store.getEvaluations(),
        'ST2',
        'CL2',
        'SJ2',
        'T1',
        'Y2');
    expect(mc, equals(13.0));
  });

  test('MC ignores non-saisie and preserves zero', () async {
    final store = StoreService();
    await store.init();
    final school = EstablishmentModel(
        id: 'SC3',
        name: 'S3',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final y = AcademicYearModel(
        id: 'Y3',
        name: 'Y3',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SC3');
    store.addAcademicYear(y);
    final c = ClassModel(
        id: 'CL3', name: 'C3', schoolId: 'SC3', academicYearId: 'Y3');
    store.addClass(c);
    final subj = SubjectModel(
        id: 'SJ3',
        name: 'Sub3',
        coefficient: 1,
        schoolId: 'SC3',
        classes: ['C3']);
    store.addSubject(subj);
    final s = StudentModel(
        id: 'ST3',
        firstName: 'C',
        lastName: 'C',
        className: 'C3',
        classId: 'CL3',
        schoolId: 'SC3',
        academicYearId: 'Y3');
    store.addStudent(s);

    final e1 = EvaluationModel(
        id: 'E31',
        title: 'D1',
        type: 'devoir',
        number: 1,
        academicYearId: 'Y3',
        classId: 'CL3',
        subjectId: 'SJ3',
        createdBy: 'ADM',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SC3');
    final e2 = EvaluationModel(
        id: 'E32',
        title: 'D2',
        type: 'devoir',
        number: 2,
        academicYearId: 'Y3',
        classId: 'CL3',
        subjectId: 'SJ3',
        createdBy: 'ADM',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SC3');
    final e3 = EvaluationModel(
        id: 'E33',
        title: 'D3',
        type: 'devoir',
        number: 3,
        academicYearId: 'Y3',
        classId: 'CL3',
        subjectId: 'SJ3',
        createdBy: 'ADM',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SC3');
    store.addEvaluation(e1);
    store.addEvaluation(e2);
    store.addEvaluation(e3);
    // e2 not saisie => no grade added for that evaluation
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST3',
        subjectId: 'SJ3',
        eval: 'D1',
        grade: 14.0,
        coef: 1,
        evaluationId: e1.id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST3',
        subjectId: 'SJ3',
        eval: 'D3',
        grade: 16.0,
        coef: 1,
        evaluationId: e3.id));
    // Another grade with zero to test zero preserved
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST3',
        subjectId: 'SJ3',
        eval: 'D2',
        grade: 0.0,
        coef: 1,
        evaluationId: e2.id));

    final mc = ResultService.calculateHomeworkAverageFromGrades(
        store.getGrades(),
        store.getEvaluations(),
        'ST3',
        'CL3',
        'SJ3',
        'T1',
        'Y3');
    // considered grades: 14,16,0 -> average = (14+16+0)/3 = 10.0
    expect(mc, equals(10.0));
  });

  test('Composition absent -> subject non calculable; present -> calculable',
      () async {
    final store = StoreService();
    await store.init();
    final school = EstablishmentModel(
        id: 'SC4',
        name: 'S4',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final y = AcademicYearModel(
        id: 'Y4',
        name: 'Y4',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SC4');
    store.addAcademicYear(y);
    final c = ClassModel(
        id: 'CL4', name: 'C4', schoolId: 'SC4', academicYearId: 'Y4');
    store.addClass(c);
    final subj = SubjectModel(
        id: 'SJ4',
        name: 'Sub4',
        coefficient: 1,
        schoolId: 'SC4',
        classes: ['C4']);
    store.addSubject(subj);
    final s = StudentModel(
        id: 'ST4',
        firstName: 'D',
        lastName: 'D',
        className: 'C4',
        classId: 'CL4',
        schoolId: 'SC4',
        academicYearId: 'Y4');
    store.addStudent(s);

    // devoirs
    final d1 = EvaluationModel(
        id: 'ED1',
        title: 'D1',
        type: 'devoir',
        number: 1,
        academicYearId: 'Y4',
        classId: 'CL4',
        subjectId: 'SJ4',
        createdBy: 'ADM',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SC4');
    store.addEvaluation(d1);
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST4',
        subjectId: 'SJ4',
        eval: 'D1',
        grade: 14.0,
        coef: 1,
        evaluationId: d1.id));

    // No composition yet
    final rs = ResultService(store);
    final subjRes = rs.calculateSubjectResult('ST4', 'CL4', 'SJ4', 'T1');
    expect(subjRes.subjectAverage, isNull);
    expect(subjRes.isCalculable, isFalse);

    // Add composition
    final comp = EvaluationModel(
        id: 'EC1',
        title: 'C1',
        type: 'composition',
        number: 1,
        academicYearId: 'Y4',
        classId: 'CL4',
        subjectId: 'SJ4',
        createdBy: 'ADM',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SC4');
    store.addEvaluation(comp);
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST4',
        subjectId: 'SJ4',
        eval: 'C1',
        grade: 16.0,
        coef: 1,
        evaluationId: comp.id));

    final subjRes2 = rs.calculateSubjectResult('ST4', 'CL4', 'SJ4', 'T1');
    // MC=14, comp=16 -> (14+16)/2 = 15.0
    expect(subjRes2.subjectAverage, equals(15.0));
    expect(subjRes2.isCalculable, isTrue);
  });

  test('Weighted general average and points with coefficients', () async {
    final store = StoreService();
    await store.init();
    final school = EstablishmentModel(
        id: 'SC5',
        name: 'S5',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final y = AcademicYearModel(
        id: 'Y5',
        name: 'Y5',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SC5');
    store.addAcademicYear(y);
    final c = ClassModel(
        id: 'CL5', name: 'C5', schoolId: 'SC5', academicYearId: 'Y5');
    store.addClass(c);
    final math = SubjectModel(
        id: 'M',
        name: 'Math',
        coefficient: 4,
        schoolId: 'SC5',
        classes: ['C5']);
    final fr = SubjectModel(
        id: 'F', name: 'Fr', coefficient: 3, schoolId: 'SC5', classes: ['C5']);
    final hist = SubjectModel(
        id: 'H',
        name: 'Hist',
        coefficient: 2,
        schoolId: 'SC5',
        classes: ['C5']);
    store.addSubject(math);
    store.addSubject(fr);
    store.addSubject(hist);
    final st = StudentModel(
        id: 'S5',
        firstName: 'E',
        lastName: 'E',
        className: 'C5',
        classId: 'CL5',
        schoolId: 'SC5',
        academicYearId: 'Y5');
    store.addStudent(st);

    // For each subject add MC+composition so subject averages calculable
    // Math avg 13.67
    // create evaluations and grades quickly: use composition matching MC for simplicity
    for (final subj in [math, fr, hist]) {
      final d = EvaluationModel(
          id: 'D_${subj.id}',
          title: 'D',
          type: 'devoir',
          number: 1,
          academicYearId: 'Y5',
          classId: 'CL5',
          subjectId: subj.id,
          createdBy: 'ADM',
          createdAt: DateTime.now().toIso8601String(),
          periodId: 'T1',
          schoolId: 'SC5');
      final cEval = EvaluationModel(
          id: 'C_${subj.id}',
          title: 'C',
          type: 'composition',
          number: 1,
          academicYearId: 'Y5',
          classId: 'CL5',
          subjectId: subj.id,
          createdBy: 'ADM',
          createdAt: DateTime.now().toIso8601String(),
          periodId: 'T1',
          schoolId: 'SC5');
      store.addEvaluation(d);
      store.addEvaluation(cEval);
    }

    // Add grades: Math 13.67 -> approximate by MC=13.67, comp=13.67 -> subj avg 13.67
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S5',
        subjectId: 'M',
        eval: 'D',
        grade: 13.67,
        coef: 1,
        evaluationId: 'D_M'));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S5',
        subjectId: 'M',
        eval: 'C',
        grade: 13.67,
        coef: 1,
        evaluationId: 'C_M'));
    // Fr -> 15
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S5',
        subjectId: 'F',
        eval: 'D',
        grade: 15.0,
        coef: 1,
        evaluationId: 'D_F'));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S5',
        subjectId: 'F',
        eval: 'C',
        grade: 15.0,
        coef: 1,
        evaluationId: 'C_F'));
    // Hist -> 12
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S5',
        subjectId: 'H',
        eval: 'D',
        grade: 12.0,
        coef: 1,
        evaluationId: 'D_H'));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'S5',
        subjectId: 'H',
        eval: 'C',
        grade: 12.0,
        coef: 1,
        evaluationId: 'C_H'));

    // validate & lock all evaluations
    for (final e
        in store.getEvaluations().where((e) => e.academicYearId == 'Y5')) {
      store.validateEvaluation(e.id);
      store.lockEvaluation(e.id);
    }

    final rs = ResultService(store);
    final gen = rs.calculateGeneralAverageOfficial('S5', 'CL5', 'T1');
    // compute expected: (13.67*4 + 15*3 + 12*2) / (4+3+2) = numerator /9
    final expected = ((13.67 * 4) + (15.0 * 3) + (12.0 * 2)) / 9.0;
    expect((gen.generalAverage ?? 0).toStringAsFixed(2),
        equals(expected.toStringAsFixed(2)));
  });

  test('Ranking with ties and isolation between establishments', () async {
    final store = await createLegacyStore();
    store.addUser(UserModel(
      id: 'RANKING_SUPERADMIN',
      name: 'Ranking Superadmin',
      email: 'ranking.superadmin@test.local',
      role: UserRole.superadmin,
    ));
    await store.login('ranking.superadmin@test.local', legacyTestPassword);
    final schoolA = EstablishmentModel(
        id: 'SA',
        name: 'SA',
        type: 'École',
        institutionType: InstitutionType.school);
    final schoolB = EstablishmentModel(
        id: 'SB',
        name: 'SB',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(schoolA);
    store.addEstablishment(schoolB);
    final ya = AcademicYearModel(
        id: 'YA',
        name: 'YA',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SA');
    final yb = AcademicYearModel(
        id: 'YB',
        name: 'YB',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SB');
    store.addAcademicYear(ya);
    store.addAcademicYear(yb);

    final ca =
        ClassModel(id: 'CA', name: 'CA', schoolId: 'SA', academicYearId: 'YA');
    final cb =
        ClassModel(id: 'CB', name: 'CB', schoolId: 'SB', academicYearId: 'YB');
    store.addClass(ca);
    store.addClass(cb);

    final subjA = SubjectModel(
        id: 'SAJ', name: 'S', coefficient: 1, schoolId: 'SA', classes: ['CA']);
    final subjB = SubjectModel(
        id: 'SBJ', name: 'S', coefficient: 1, schoolId: 'SB', classes: ['CB']);
    store.addSubject(subjA);
    store.addSubject(subjB);

    final s1 = StudentModel(
        id: 'ST_A1',
        firstName: 'A1',
        lastName: 'A',
        className: 'CA',
        classId: 'CA',
        schoolId: 'SA',
        academicYearId: 'YA');
    final s2 = StudentModel(
        id: 'ST_A2',
        firstName: 'A2',
        lastName: 'A',
        className: 'CA',
        classId: 'CA',
        schoolId: 'SA',
        academicYearId: 'YA');
    store.addStudent(s1);
    store.addStudent(s2);
    final s3 = StudentModel(
        id: 'ST_B1',
        firstName: 'B1',
        lastName: 'B',
        className: 'CB',
        classId: 'CB',
        schoolId: 'SB',
        academicYearId: 'YB');
    store.addStudent(s3);

    // create and validate evaluations for each
    final eA = EvaluationModel(
        id: 'E_A',
        title: 'D',
        type: 'devoir',
        number: 1,
        academicYearId: 'YA',
        classId: 'CA',
        subjectId: 'SAJ',
        createdBy: 'ADM',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SA');
    final cA = EvaluationModel(
        id: 'C_A',
        title: 'C',
        type: 'composition',
        number: 1,
        academicYearId: 'YA',
        classId: 'CA',
        subjectId: 'SAJ',
        createdBy: 'ADM',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SA');
    store.addEvaluation(eA);
    store.addEvaluation(cA);
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_A1',
        subjectId: 'SAJ',
        eval: 'D',
        grade: 15.0,
        coef: 1,
        evaluationId: eA.id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_A1',
        subjectId: 'SAJ',
        eval: 'C',
        grade: 15.0,
        coef: 1,
        evaluationId: cA.id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_A2',
        subjectId: 'SAJ',
        eval: 'D',
        grade: 15.0,
        coef: 1,
        evaluationId: eA.id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_A2',
        subjectId: 'SAJ',
        eval: 'C',
        grade: 15.0,
        coef: 1,
        evaluationId: cA.id));

    // school B
    final eB = EvaluationModel(
        id: 'E_B',
        title: 'D',
        type: 'devoir',
        number: 1,
        academicYearId: 'YB',
        classId: 'CB',
        subjectId: 'SBJ',
        createdBy: 'ADM',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SB');
    final cB = EvaluationModel(
        id: 'C_B',
        title: 'C',
        type: 'composition',
        number: 1,
        academicYearId: 'YB',
        classId: 'CB',
        subjectId: 'SBJ',
        createdBy: 'ADM',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SB');
    store.addEvaluation(eB);
    store.addEvaluation(cB);
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_B1',
        subjectId: 'SBJ',
        eval: 'D',
        grade: 20.0,
        coef: 1,
        evaluationId: eB.id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST_B1',
        subjectId: 'SBJ',
        eval: 'C',
        grade: 20.0,
        coef: 1,
        evaluationId: cB.id));

    // validate all
    for (final e in store.getEvaluations()) {
      store.validateEvaluation(e.id);
      store.lockEvaluation(e.id);
    }

    final rs = ResultService(store);
    final rankingA = rs.computeClassRanking('CA', 'T1');
    final rListA = rankingA['ranking'] as List<RankingEntry>;
    final entryA1 = rListA.firstWhere((r) => r.studentId == 'ST_A1');
    final entryA2 = rListA.firstWhere((r) => r.studentId == 'ST_A2');
    expect(entryA1.rank, equals(1));
    expect(entryA2.rank, equals(1)); // tie

    final rankingB = rs.computeClassRanking('CB', 'T1');
    final rListB = rankingB['ranking'] as List<RankingEntry>;
    final entryB1 = rListB.firstWhere((r) => r.studentId == 'ST_B1');
    expect(entryB1.rank, equals(1));
  });

  test('Non-validated evaluations are ignored by official calculations',
      () async {
    final store = StoreService();
    await store.init();
    final school = EstablishmentModel(
        id: 'SC6',
        name: 'S6',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final y = AcademicYearModel(
        id: 'Y6',
        name: 'Y6',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SC6');
    store.addAcademicYear(y);
    final c = ClassModel(
        id: 'CL6', name: 'C6', schoolId: 'SC6', academicYearId: 'Y6');
    store.addClass(c);
    final subj = SubjectModel(
        id: 'SJ6',
        name: 'Sub6',
        coefficient: 1,
        schoolId: 'SC6',
        classes: ['C6']);
    store.addSubject(subj);
    final s = StudentModel(
        id: 'ST6',
        firstName: 'F',
        lastName: 'F',
        className: 'C6',
        classId: 'CL6',
        schoolId: 'SC6',
        academicYearId: 'Y6');
    store.addStudent(s);

    final evDraft = EvaluationModel(
        id: 'EDRAFT',
        title: 'D',
        type: 'devoir',
        number: 1,
        academicYearId: 'Y6',
        classId: 'CL6',
        subjectId: 'SJ6',
        createdBy: 'ADM',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SC6',
        status: 'draft');
    final evVal = EvaluationModel(
        id: 'EVAL',
        title: 'D2',
        type: 'devoir',
        number: 2,
        academicYearId: 'Y6',
        classId: 'CL6',
        subjectId: 'SJ6',
        createdBy: 'ADM',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SC6',
        status: 'validated');
    store.addEvaluation(evDraft);
    store.addEvaluation(evVal);
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST6',
        subjectId: 'SJ6',
        eval: 'D',
        grade: 20.0,
        coef: 1,
        evaluationId: evDraft.id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST6',
        subjectId: 'SJ6',
        eval: 'D2',
        grade: 10.0,
        coef: 1,
        evaluationId: evVal.id));

    final rs = ResultService(store);
    final official =
        rs.calculateSubjectResultOfficial('ST6', 'CL6', 'SJ6', 'T1');
    // Only validated eval counts => MC = 10.0 (only one considered if it's devid among devoirs)
    expect(official.homeworkAverage, equals(10.0));
  });

  test('Absent not converted to zero', () async {
    final store = StoreService();
    await store.init();
    final school = EstablishmentModel(
        id: 'SC7',
        name: 'S7',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final y = AcademicYearModel(
        id: 'Y7',
        name: 'Y7',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SC7');
    store.addAcademicYear(y);
    final c = ClassModel(
        id: 'CL7', name: 'C7', schoolId: 'SC7', academicYearId: 'Y7');
    store.addClass(c);
    final subj = SubjectModel(
        id: 'SJ7',
        name: 'Sub7',
        coefficient: 1,
        schoolId: 'SC7',
        classes: ['C7']);
    store.addSubject(subj);
    final s = StudentModel(
        id: 'ST7',
        firstName: 'G',
        lastName: 'G',
        className: 'C7',
        classId: 'CL7',
        schoolId: 'SC7',
        academicYearId: 'Y7');
    store.addStudent(s);

    final e1 = EvaluationModel(
        id: 'E71',
        title: 'D1',
        type: 'devoir',
        number: 1,
        academicYearId: 'Y7',
        classId: 'CL7',
        subjectId: 'SJ7',
        createdBy: 'ADM',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SC7');
    final e2 = EvaluationModel(
        id: 'E72',
        title: 'D2',
        type: 'devoir',
        number: 2,
        academicYearId: 'Y7',
        classId: 'CL7',
        subjectId: 'SJ7',
        createdBy: 'ADM',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SC7');
    store.addEvaluation(e1);
    store.addEvaluation(e2);
    // student absent on e1: model with presence but grade null
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST7',
        subjectId: 'SJ7',
        eval: 'D1',
        grade: null,
        presence: 'absent',
        coef: 1,
        evaluationId: e1.id));
    // present on e2 with grade 14
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST7',
        subjectId: 'SJ7',
        eval: 'D2',
        grade: 14.0,
        coef: 1,
        evaluationId: e2.id));

    final mc = ResultService.calculateHomeworkAverageFromGrades(
        store.getGrades(),
        store.getEvaluations(),
        'ST7',
        'CL7',
        'SJ7',
        'T1',
        'Y7');
    // only grade 14 considered -> MC 14
    expect(mc, equals(14.0));
  });
}
