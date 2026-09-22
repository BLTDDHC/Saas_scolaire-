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

import 'package:edupro_flutter_web/core/constants/establishment_types.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test(
      'TRIMESTER BULLETIN: header, devoirs vs composition, MC, subject avg, general avg and rank',
      () async {
    final store = StoreService();
    await store.init();

    final school = EstablishmentModel(
        id: 'SCH_T',
        name: 'Trim School',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final year = AcademicYearModel(
        id: 'AYT',
        name: '2026-2027',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCH_T');
    store.addAcademicYear(year);

    final cls = ClassModel(
        id: 'C_T', name: 'Classe T', schoolId: 'SCH_T', academicYearId: 'AYT');
    store.addClass(cls);

    final subj = SubjectModel(
        id: 'MATH',
        name: 'Maths',
        coefficient: 4,
        schoolId: 'SCH_T',
        classes: ['Classe T']);
    store.addSubject(subj);

    final stu1 = StudentModel(
        id: 'ST1',
        firstName: 'Jean',
        lastName: 'K',
        className: 'Classe T',
        classId: 'C_T',
        schoolId: 'SCH_T',
        academicYearId: 'AYT');
    final stu2 = StudentModel(
        id: 'ST2',
        firstName: 'Paul',
        lastName: 'L',
        className: 'Classe T',
        classId: 'C_T',
        schoolId: 'SCH_T',
        academicYearId: 'AYT');
    store.addStudent(stu1);
    store.addStudent(stu2);

    final admin = UserModel(
        id: 'ADMIN_T',
        name: 'AdminT',
        email: 'adminT@test',
        role: UserRole.admin,
        schoolId: 'SCH_T');
    store.addUser(admin);
    store.login('adminT@test', 'pw');

    // Create 2 devoirs and 1 composition for period T1
    final evD1 = EvaluationModel(
        id: 'ED1',
        title: 'D1',
        type: 'devoir',
        number: 1,
        academicYearId: 'AYT',
        classId: 'C_T',
        subjectId: 'MATH',
        createdBy: 'ADMIN_T',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SCH_T');
    final evD2 = EvaluationModel(
        id: 'ED2',
        title: 'D2',
        type: 'devoir',
        number: 2,
        academicYearId: 'AYT',
        classId: 'C_T',
        subjectId: 'MATH',
        createdBy: 'ADMIN_T',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SCH_T');
    final evC = EvaluationModel(
        id: 'EC',
        title: 'C',
        type: 'composition',
        number: 1,
        academicYearId: 'AYT',
        classId: 'C_T',
        subjectId: 'MATH',
        createdBy: 'ADMIN_T',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SCH_T');
    store.addEvaluation(evD1);
    store.addEvaluation(evD2);
    store.addEvaluation(evC);

    // Add grades: ST1 has D1=12, D2 missing, C=15; ST2 has D1=10, D2=14, C=13
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST1',
        subjectId: 'MATH',
        eval: 'D1',
        grade: 12.0,
        coef: 1,
        evaluationId: evD1.id));
    // D2 missing for ST1 -> not added
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST1',
        subjectId: 'MATH',
        eval: 'C',
        grade: 15.0,
        coef: 1,
        evaluationId: evC.id));

    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST2',
        subjectId: 'MATH',
        eval: 'D1',
        grade: 10.0,
        coef: 1,
        evaluationId: evD1.id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST2',
        subjectId: 'MATH',
        eval: 'D2',
        grade: 14.0,
        coef: 1,
        evaluationId: evD2.id));
    store.addGrade(GradeModel(
        id: '',
        studentId: 'ST2',
        subjectId: 'MATH',
        eval: 'C',
        grade: 13.0,
        coef: 1,
        evaluationId: evC.id));

    // Validate and lock evaluations (official bulletin uses validated/locked)
    for (final e
        in store.getEvaluations().where((e) => e.academicYearId == 'AYT')) {
      store.validateEvaluation(e.id);
      store.lockEvaluation(e.id);
    }

    final rs = ResultService(store);
    final bulletin = rs.generateTrimesterBulletin('C_T', 'ST1', 'T1');

    // Header checks
    expect(bulletin['academicYearId'], equals('AYT'));
    expect(bulletin['periodId'], equals('T1'));
    expect((bulletin['student'] as Map)['id'], equals('ST1'));
    expect((bulletin['class'] as Map)['id'], equals('C_T'));

    final subjects = bulletin['subjects'] as List;
    final mathRow = subjects.firstWhere((r) => r['subjectId'] == 'MATH');

    // Devoirs: should show D1=12, D2=null (missing)
    final devoirs = mathRow['devoirs'] as List;
    expect(devoirs.length, 2);
    expect(devoirs[0], equals(12.0));
    expect(devoirs[1], equals(null));

    // Composition separate
    expect(mathRow['composition'], equals(15.0));

    // MC should be average of existing devoirs for ST1 -> only D1 (12) considered => 12
    expect(mathRow['mc'], equals(12.0));

    // Subject average for ST1 requires MC and composition -> (12+15)/2 = 13.5 -> rounded to 13.5
    expect(mathRow['subjectAverage'], equals(13.5));

    // Coefficient comes from subject
    expect(mathRow['coefficient'], equals(4));

    // General average: only maths subject, so should equal subjectAverage
    expect((bulletin['generalAverage'] as double?) != null, isTrue);
    expect((bulletin['generalAverage'] as double?), equals(13.5));

    // Ranking: ST1 vs ST2: compute ST2 subject average: devoir avg (10+14)/2=12 -> MC=12; composition=13 -> subj avg=(12+13)/2=12.5
    // General averages: ST1=13.5, ST2=12.5 => ST1 rank 1
    final rankMap = bulletin['ranking'] as Map;
    expect(rankMap['rank'], equals(1));
    expect(rankMap['effectif'], equals(2));
  });

  test('TRIMESTER BULLETIN: absence is preserved and not converted to 0',
      () async {
    final store = StoreService();
    await store.init();

    final school = EstablishmentModel(
        id: 'SCH_ABS',
        name: 'Abs School',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final year = AcademicYearModel(
        id: 'AYA',
        name: 'AYA',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCH_ABS');
    store.addAcademicYear(year);
    final cls = ClassModel(
        id: 'C_ABS',
        name: 'Classe Abs',
        schoolId: 'SCH_ABS',
        academicYearId: 'AYA');
    store.addClass(cls);
    final subj = SubjectModel(
        id: 'HIST',
        name: 'Histoire',
        coefficient: 2,
        schoolId: 'SCH_ABS',
        classes: ['Classe Abs']);
    store.addSubject(subj);
    final s = StudentModel(
        id: 'SABS',
        firstName: 'Abs',
        lastName: 'One',
        className: 'Classe Abs',
        classId: 'C_ABS',
        schoolId: 'SCH_ABS',
        academicYearId: 'AYA');
    store.addStudent(s);

    final admin = UserModel(
        id: 'ADMIN_ABS',
        name: 'Admin',
        email: 'adminabs@test',
        role: UserRole.admin,
        schoolId: 'SCH_ABS');
    store.addUser(admin);
    store.login('adminabs@test', 'pw');

    final evD = EvaluationModel(
        id: 'EAD',
        title: 'D1',
        type: 'devoir',
        number: 1,
        academicYearId: 'AYA',
        classId: 'C_ABS',
        subjectId: 'HIST',
        createdBy: 'ADMIN_ABS',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        schoolId: 'SCH_ABS');
    store.addEvaluation(evD);

    // Add grade marked as absent
    store.addGrade(GradeModel(
        id: '',
        studentId: 'SABS',
        subjectId: 'HIST',
        eval: 'D1',
        grade: null,
        coef: 1,
        evaluationId: evD.id,
        presence: 'absent'));

    for (final e
        in store.getEvaluations().where((e) => e.academicYearId == 'AYA')) {
      store.validateEvaluation(e.id);
      store.lockEvaluation(e.id);
    }

    final rs = ResultService(store);
    final b = rs.generateTrimesterBulletin('C_ABS', 'SABS', 'T1');
    final row =
        (b['subjects'] as List).firstWhere((r) => r['subjectId'] == 'HIST');
    final devoirs = row['devoirs'] as List;
    expect(devoirs[0], isNull);

    // MC should be null because no present devoirs
    expect(row['mc'], isNull);

    // SubjectAverage should be null since MC missing
    expect(row['subjectAverage'], isNull);
  });
}
