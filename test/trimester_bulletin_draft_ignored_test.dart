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

  test('Draft evaluations are ignored by trimester bulletin', () async {
    final store = StoreService();
    await store.init();

    final school = EstablishmentModel(
        id: 'SCHD',
        name: 'Draft School',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final year = AcademicYearModel(
        id: 'AYD',
        name: '2026',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCHD');
    store.addAcademicYear(year);
    final cls = ClassModel(
        id: 'CLD', name: 'Classe D', schoolId: 'SCHD', academicYearId: 'AYD');
    store.addClass(cls);
    final subj = SubjectModel(
        id: 'SUBD',
        name: 'Sub D',
        coefficient: 1,
        schoolId: 'SCHD',
        classes: ['Classe D']);
    store.addSubject(subj);
    final stu = StudentModel(
        id: 'STUD',
        firstName: 'Draft',
        lastName: 'One',
        className: 'Classe D',
        classId: 'CLD',
        schoolId: 'SCHD',
        academicYearId: 'AYD');
    store.addStudent(stu);

    final admin = UserModel(
        id: 'ADM_D',
        name: 'Adm',
        email: 'adm_d@test',
        role: UserRole.admin,
        schoolId: 'SCHD');
    store.addUser(admin);
    store.login('adm_d@test', 'pw');

    // Add a draft evaluation and a grade
    final evDraft = EvaluationModel(
        id: 'EDRAFT',
        title: 'DRAFT',
        type: 'devoir',
        number: 1,
        academicYearId: 'AYD',
        classId: 'CLD',
        subjectId: 'SUBD',
        createdBy: 'ADM_D',
        createdAt: DateTime.now().toIso8601String(),
        periodId: 'T1',
        status: 'draft',
        schoolId: 'SCHD');
    store.addEvaluation(evDraft);
    store.addGrade(GradeModel(
        id: '',
        studentId: 'STUD',
        subjectId: 'SUBD',
        eval: 'DRAFT',
        grade: 12.0,
        coef: 1,
        evaluationId: evDraft.id));

    final rs = ResultService(store);
    final b = rs.generateTrimesterBulletin('CLD', 'STUD', 'T1');

    final subjects = b['subjects'] as List;
    final row = subjects.firstWhere((r) => r['subjectId'] == 'SUBD');
    final devoirs = row['devoirs'] as List;

    // Because the only evaluation is draft, the bulletin should not include it -> devoirs list empty
    expect(devoirs.length, equals(0));
    expect(row['mc'], isNull);
    expect(row['composition'], isNull);
    expect(row['subjectAverage'], isNull);
  });
}
