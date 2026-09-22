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
import 'package:edupro_flutter_web/data/models/evaluation_model.dart';
import 'package:edupro_flutter_web/data/models/grade_model.dart';
import 'package:edupro_flutter_web/data/models/user_model.dart';

import 'package:edupro_flutter_web/core/constants/establishment_types.dart';
import 'support/legacy_store_test_harness.dart';

void main() {
  setUp(() async {
    // Ensure SharedPreferences is mocked fresh for each test
    SharedPreferences.setMockInitialValues({});
  });

  test('Draft is modifiable by assigned teacher', () async {
    final store = await createLegacyStore();

    // Create establishment and academic year
    final school = EstablishmentModel(
        id: 'SCH1',
        name: 'School 1',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final year = AcademicYearModel(
        id: 'AY1',
        name: '2026',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCH1');
    store.addAcademicYear(year);

    // Create class, subject, student, teacher and affectation
    final cls = ClassModel(
        id: 'C1', name: 'Classe 1', schoolId: 'SCH1', academicYearId: 'AY1');
    store.addClass(cls);
    final subj = SubjectModel(
        id: 'S1',
        name: 'Maths',
        coefficient: 1,
        schoolId: 'SCH1',
        classes: ['Classe 1']);
    store.addSubject(subj);
    final student = StudentModel(
        id: 'ST1',
        firstName: 'Jean',
        lastName: 'Dupont',
        className: 'Classe 1',
        schoolId: 'SCH1',
        academicYearId: 'AY1');
    store.addStudent(student);

    // Create teacher and user with the SAME id so affectations map to the logged user
    final teacher = TeacherModel(
        id: 'U_T1', firstName: 'Alice', lastName: 'Teacher', schoolId: 'SCH1');
    store.addTeacher(teacher);

    final userTeacher = UserModel(
        id: 'U_T1',
        name: 'Alice Teacher',
        email: 'alice@sch1.test',
        role: UserRole.teacher,
        schoolId: 'SCH1');
    store.addUser(userTeacher);

    final aff = AffectationModel(
        id: 'A1',
        teacherId: 'U_T1',
        teacherName: 'Alice Teacher',
        subjectId: 'S1',
        classId: 'C1',
        schoolId: 'SCH1',
        academicYearId: 'AY1');
    store.addAffectation(aff);

    // Create a draft evaluation
    final ev = EvaluationModel(
        id: 'EV1',
        title: 'Devoir 1',
        type: 'devoir',
        number: 1,
        academicYearId: 'AY1',
        classId: 'C1',
        subjectId: 'S1',
        createdBy: 'U_T1',
        createdAt: DateTime.now().toIso8601String(),
        schoolId: 'SCH1');
    final evId = store.addEvaluation(ev);
    expect(evId, isNotEmpty);

    // Teacher login and add grade
    final loginOk = await store.login('alice@sch1.test', 'pw');
    expect(loginOk, isTrue);

    final gradeModel = GradeModel(
        id: '',
        studentId: 'ST1',
        subjectId: 'S1',
        eval: 'D1',
        grade: 12.0,
        coef: 1,
        evaluationId: evId);
    final gradeId = store.addGrade(gradeModel);
    expect(gradeId, isNotEmpty);
  });

  test(
      'Submitted and validated are not modifiable by teacher; request and approval flow',
      () async {
    final store = await createLegacyStore();

    SharedPreferences.setMockInitialValues({});

    final school = EstablishmentModel(
        id: 'SCH2',
        name: 'School 2',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final year = AcademicYearModel(
        id: 'AY2',
        name: '2026',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCH2');
    store.addAcademicYear(year);

    final cls = ClassModel(
        id: 'C2', name: 'Classe 2', schoolId: 'SCH2', academicYearId: 'AY2');
    store.addClass(cls);
    final subj = SubjectModel(
        id: 'S2',
        name: 'Physique',
        coefficient: 1,
        schoolId: 'SCH2',
        classes: ['Classe 2']);
    store.addSubject(subj);
    final student = StudentModel(
        id: 'ST2',
        firstName: 'Paul',
        lastName: 'Student',
        className: 'Classe 2',
        schoolId: 'SCH2',
        academicYearId: 'AY2');
    store.addStudent(student);

    // teacher and user share same id
    final teacher = TeacherModel(
        id: 'U_T2', firstName: 'Bob', lastName: 'Teacher', schoolId: 'SCH2');
    store.addTeacher(teacher);
    final userTeacher = UserModel(
        id: 'U_T2',
        name: 'Bob Teacher',
        email: 'bob@sch2.test',
        role: UserRole.teacher,
        schoolId: 'SCH2');
    store.addUser(userTeacher);
    final aff = AffectationModel(
        id: 'A2',
        teacherId: 'U_T2',
        teacherName: 'Bob Teacher',
        subjectId: 'S2',
        classId: 'C2',
        schoolId: 'SCH2',
        academicYearId: 'AY2');
    store.addAffectation(aff);

    final ev = EvaluationModel(
        id: 'EV2',
        title: 'Exam 1',
        type: 'exam',
        number: 1,
        academicYearId: 'AY2',
        classId: 'C2',
        subjectId: 'S2',
        createdBy: 'U_T2',
        createdAt: DateTime.now().toIso8601String(),
        schoolId: 'SCH2');
    final evId = store.addEvaluation(ev);
    expect(evId, isNotEmpty);

    // Teacher adds grade in draft
    await store.login('bob@sch2.test', 'pw');
    final gradeModel = GradeModel(
        id: '',
        studentId: 'ST2',
        subjectId: 'S2',
        eval: 'E1',
        grade: 10.0,
        coef: 1,
        evaluationId: evId);
    final gId = store.addGrade(gradeModel);
    expect(gId, isNotEmpty);

    // Teacher submits evaluation
    expect(store.submitEvaluation(evId), isTrue);

    // Teacher cannot update grade when submitted
    final updated = GradeModel(
        id: gId,
        studentId: 'ST2',
        subjectId: 'S2',
        eval: 'E1',
        grade: 11.0,
        coef: 1,
        evaluationId: evId);
    final updateRes = store.updateGrade(gId, updated);
    expect(updateRes, isFalse);

    // School admin validates the evaluation (create admin user for SCH2)
    final admin = UserModel(
        id: 'U_AD2',
        name: 'Admin 2',
        email: 'admin2@sch2.test',
        role: UserRole.admin,
        schoolId: 'SCH2');
    store.addUser(admin);
    await store.login('admin2@sch2.test', 'pw');
    expect(store.validateEvaluation(evId), isTrue);

    // Teacher cannot modify directly when validated
    await store.login('bob@sch2.test', 'pw');
    final updateRes2 = store.updateGrade(gId, updated);
    expect(updateRes2, isFalse);

    // Teacher requests modification
    final reqId = store.requestGradeModification(
        gradeId: gId, newValue: 11.0, reason: 'Correction');
    expect(reqId, isNotEmpty);

    // School admin approves
    await store.login('admin2@sch2.test', 'pw');
    expect(store.approveGradeModification(reqId), isTrue);

    // After approval teacher can apply the modification (must match requested value)
    await store.login('bob@sch2.test', 'pw');
    final updatedAllowed = GradeModel(
        id: gId,
        studentId: 'ST2',
        subjectId: 'S2',
        eval: 'E1',
        grade: 11.0,
        coef: 1,
        evaluationId: evId);
    final applyRes = store.updateGrade(gId, updatedAllowed);
    expect(applyRes, isTrue);

    // After applying, evaluation should be back to submitted and teacher cannot modify further
    final evAfter = store.getEvaluationById(evId);
    expect(evAfter?.status, equals('submitted'));
    final tryAgain = store.updateGrade(
        gId,
        GradeModel(
            id: gId,
            studentId: 'ST2',
            subjectId: 'S2',
            eval: 'E1',
            grade: 12.0,
            coef: 1,
            evaluationId: evId));
    expect(tryAgain, isFalse);

    // Admin re-validates and locks the evaluation
    await store.login('admin2@sch2.test', 'pw');
    expect(store.validateEvaluation(evId), isTrue);
    expect(store.lockEvaluation(evId), isTrue);

    // Teacher cannot modify when locked
    await store.login('bob@sch2.test', 'pw');
    final lockedTry = store.updateGrade(
        gId,
        GradeModel(
            id: gId,
            studentId: 'ST2',
            subjectId: 'S2',
            eval: 'E1',
            grade: 13.0,
            coef: 1,
            evaluationId: evId));
    expect(lockedTry, isFalse);
  });

  test('Administration can enter grades when no teacher accounts exist',
      () async {
    final store = await createLegacyStore();

    final school = EstablishmentModel(
        id: 'SCH3',
        name: 'School 3',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final year = AcademicYearModel(
        id: 'AY3',
        name: '2026',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCH3');
    store.addAcademicYear(year);

    final cls = ClassModel(
        id: 'C3', name: 'Classe 3', schoolId: 'SCH3', academicYearId: 'AY3');
    store.addClass(cls);
    final subj = SubjectModel(
        id: 'S3',
        name: 'Histoire',
        coefficient: 1,
        schoolId: 'SCH3',
        classes: ['Classe 3']);
    store.addSubject(subj);
    final student = StudentModel(
        id: 'ST3',
        firstName: 'Lina',
        lastName: 'Student',
        className: 'Classe 3',
        schoolId: 'SCH3',
        academicYearId: 'AY3');
    store.addStudent(student);

    // No teacher account added for SCH3
    final adminUser = UserModel(
        id: 'U_AD3',
        name: 'Admin 3',
        email: 'admin3@sch3.test',
        role: UserRole.admin,
        schoolId: 'SCH3');
    store.addUser(adminUser);

    final ev = EvaluationModel(
        id: 'EV3',
        title: 'Test',
        type: 'devoir',
        number: 1,
        academicYearId: 'AY3',
        classId: 'C3',
        subjectId: 'S3',
        createdBy: 'U_AD3',
        createdAt: DateTime.now().toIso8601String(),
        schoolId: 'SCH3');
    final evId = store.addEvaluation(ev);

    await store.login('admin3@sch3.test', 'pw');
    final gradeModel = GradeModel(
        id: '',
        studentId: 'ST3',
        subjectId: 'S3',
        eval: 'T1',
        grade: 14.0,
        coef: 1,
        evaluationId: evId);
    final gId = store.addGrade(gradeModel);
    expect(gId, isNotEmpty);
  });

  test('Request refused and multi-tenant isolation', () async {
    final store = await createLegacyStore();

    // Setup school A
    final schoolA = EstablishmentModel(
        id: 'SCHA',
        name: 'School A',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(schoolA);
    final ayA = AcademicYearModel(
        id: 'AYA',
        name: '2026',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCHA');
    store.addAcademicYear(ayA);
    final clsA = ClassModel(
        id: 'CA1', name: 'Classe A1', schoolId: 'SCHA', academicYearId: 'AYA');
    store.addClass(clsA);
    final subjA = SubjectModel(
        id: 'SA1',
        name: 'Geo',
        coefficient: 1,
        schoolId: 'SCHA',
        classes: ['Classe A1']);
    store.addSubject(subjA);
    final studentA = StudentModel(
        id: 'STA1',
        firstName: 'StuA',
        lastName: 'A',
        className: 'Classe A1',
        schoolId: 'SCHA',
        academicYearId: 'AYA');
    store.addStudent(studentA);
    final teacherA = TeacherModel(
        id: 'U_TA1', firstName: 'TA', lastName: 'One', schoolId: 'SCHA');
    store.addTeacher(teacherA);
    final userTeacherA = UserModel(
        id: 'U_TA1',
        name: 'TA One',
        email: 'ta1@sa.test',
        role: UserRole.teacher,
        schoolId: 'SCHA');
    store.addUser(userTeacherA);
    final affA = AffectationModel(
        id: 'AFF_A1',
        teacherId: 'U_TA1',
        teacherName: 'TA One',
        subjectId: 'SA1',
        classId: 'CA1',
        schoolId: 'SCHA',
        academicYearId: 'AYA');
    store.addAffectation(affA);
    final evA = EvaluationModel(
        id: 'EVA1',
        title: 'EvalA',
        type: 'devoir',
        number: 1,
        academicYearId: 'AYA',
        classId: 'CA1',
        subjectId: 'SA1',
        createdBy: 'U_TA1',
        createdAt: DateTime.now().toIso8601String(),
        schoolId: 'SCHA');
    final evIdA = store.addEvaluation(evA);
    await store.login('ta1@sa.test', 'pw');
    final gA = GradeModel(
        id: '',
        studentId: 'STA1',
        subjectId: 'SA1',
        eval: 'EA',
        grade: 9.0,
        coef: 1,
        evaluationId: evIdA);
    final gIdA = store.addGrade(gA);
    expect(gIdA, isNotEmpty);

    // Validate and lock so teacher must request
    final adminA = UserModel(
        id: 'U_AA1',
        name: 'Admin A',
        email: 'adminA@sa.test',
        role: UserRole.admin,
        schoolId: 'SCHA');
    store.addUser(adminA);
    await store.login('adminA@sa.test', 'pw');
    expect(store.validateEvaluation(evIdA), isTrue);
    expect(store.lockEvaluation(evIdA), isTrue);

    // Teacher from A requests modification
    await store.login('ta1@sa.test', 'pw');
    final reqIdA = store.requestGradeModification(
        gradeId: gIdA, newValue: 10.0, reason: 'Appeal');
    expect(reqIdA, isNotEmpty);

    // Admin from A refuses request
    await store.login('adminA@sa.test', 'pw');
    expect(store.refuseGradeModification(reqIdA, 'Not justified'), isTrue);

    // Teacher cannot apply change after refusal
    await store.login('ta1@sa.test', 'pw');
    final applyAfterRefusal = store.updateGrade(
        gIdA,
        GradeModel(
            id: gIdA,
            studentId: 'STA1',
            subjectId: 'SA1',
            eval: 'EA',
            grade: 10.0,
            coef: 1,
            evaluationId: evIdA));
    expect(applyAfterRefusal, isFalse);

    // Multi-tenant isolation: teacher from another school cannot modify
    final schoolB = EstablishmentModel(
        id: 'SCHB',
        name: 'School B',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(schoolB);
    final ayB = AcademicYearModel(
        id: 'AYB',
        name: '2026',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'SCHB');
    store.addAcademicYear(ayB);
    final teacherB = TeacherModel(
        id: 'U_TB1', firstName: 'TB', lastName: 'One', schoolId: 'SCHB');
    store.addTeacher(teacherB);
    final userTeacherB = UserModel(
        id: 'U_TB1',
        name: 'TB One',
        email: 'tb1@sb.test',
        role: UserRole.teacher,
        schoolId: 'SCHB');
    store.addUser(userTeacherB);
    await store.login('tb1@sb.test', 'pw');
    final crossAttempt = store.updateGrade(
        gIdA,
        GradeModel(
            id: gIdA,
            studentId: 'STA1',
            subjectId: 'SA1',
            eval: 'EA',
            grade: 11.0,
            coef: 1,
            evaluationId: evIdA));
    expect(crossAttempt, isFalse);
  });
}
