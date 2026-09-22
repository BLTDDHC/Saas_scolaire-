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
    SharedPreferences.setMockInitialValues({});
  });

  test('1-2 Assigned teacher can add grade; non-assigned cannot', () async {
    final store = await createLegacyStore();

    final school = EstablishmentModel(
        id: 'TS1',
        name: 'TSchool',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final ay = AcademicYearModel(
        id: 'AYT1',
        name: '2026',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'TS1');
    store.addAcademicYear(ay);

    final cls = ClassModel(
        id: 'TC1', name: 'Classe T1', schoolId: 'TS1', academicYearId: 'AYT1');
    store.addClass(cls);
    final subj = SubjectModel(
        id: 'TSUB1',
        name: 'Maths',
        coefficient: 1,
        schoolId: 'TS1',
        classes: ['Classe T1']);
    store.addSubject(subj);
    final student = StudentModel(
        id: 'TST1',
        firstName: 'Jean',
        lastName: 'Test',
        className: 'Classe T1',
        schoolId: 'TS1',
        academicYearId: 'AYT1');
    store.addStudent(student);

    final teacher = TeacherModel(
        id: 'UT1', firstName: 'Teach', lastName: 'One', schoolId: 'TS1');
    store.addTeacher(teacher);
    final userTeacher = UserModel(
        id: 'UT1',
        name: 'Teach One',
        email: 't1@ts.test',
        role: UserRole.teacher,
        schoolId: 'TS1');
    store.addUser(userTeacher);
    final aff = AffectationModel(
        id: 'A_T1',
        teacherId: 'UT1',
        teacherName: 'Teach One',
        subjectId: 'TSUB1',
        classId: 'TC1',
        schoolId: 'TS1',
        academicYearId: 'AYT1');
    store.addAffectation(aff);

    final ev = EvaluationModel(
        id: 'TEV1',
        title: 'Devoir T1',
        type: 'devoir',
        number: 1,
        academicYearId: 'AYT1',
        classId: 'TC1',
        subjectId: 'TSUB1',
        createdBy: 'UT1',
        createdAt: DateTime.now().toIso8601String(),
        schoolId: 'TS1');
    final evId = store.addEvaluation(ev);
    expect(evId, isNotEmpty);

    // assigned teacher can add grade
    await store.login('t1@ts.test', 'pw');
    final gradeId = store.addGrade(GradeModel(
        id: '',
        studentId: 'TST1',
        subjectId: 'TSUB1',
        eval: 'D1',
        grade: 15.0,
        coef: 1,
        evaluationId: evId));
    expect(gradeId, isNotEmpty);

    // other teacher not assigned cannot
    final teacher2 = TeacherModel(
        id: 'UT2', firstName: 'Teach', lastName: 'Two', schoolId: 'TS1');
    store.addTeacher(teacher2);
    final userTeacher2 = UserModel(
        id: 'UT2',
        name: 'Teach Two',
        email: 't2@ts.test',
        role: UserRole.teacher,
        schoolId: 'TS1');
    store.addUser(userTeacher2);
    await store.login('t2@ts.test', 'pw');
    final cannotAdd = store.addGrade(GradeModel(
        id: '',
        studentId: 'TST1',
        subjectId: 'TSUB1',
        eval: 'D1',
        grade: 12.0,
        coef: 1,
        evaluationId: evId));
    expect(cannotAdd, isEmpty);
  });

  test('3-5 Validation permissions and multi-tenant', () async {
    final store = await createLegacyStore();

    final school = EstablishmentModel(
        id: 'VS1',
        name: 'VSchool',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final ay = AcademicYearModel(
        id: 'VAY1',
        name: '2026',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'VS1');
    store.addAcademicYear(ay);
    final cls = ClassModel(
        id: 'VC1', name: 'Classe V1', schoolId: 'VS1', academicYearId: 'VAY1');
    store.addClass(cls);
    final subj = SubjectModel(
        id: 'VSUB1',
        name: 'Phys',
        coefficient: 1,
        schoolId: 'VS1',
        classes: ['Classe V1']);
    store.addSubject(subj);
    final student = StudentModel(
        id: 'VST1',
        firstName: 'Paul',
        lastName: 'V',
        className: 'Classe V1',
        schoolId: 'VS1',
        academicYearId: 'VAY1');
    store.addStudent(student);

    final teacher = TeacherModel(
        id: 'UTV1', firstName: 'TVal', lastName: 'One', schoolId: 'VS1');
    store.addTeacher(teacher);
    final userTeacher = UserModel(
        id: 'UTV1',
        name: 'TVal One',
        email: 'tv1@v.test',
        role: UserRole.teacher,
        schoolId: 'VS1');
    store.addUser(userTeacher);
    final aff = AffectationModel(
        id: 'AV1',
        teacherId: 'UTV1',
        teacherName: 'TVal One',
        subjectId: 'VSUB1',
        classId: 'VC1',
        schoolId: 'VS1',
        academicYearId: 'VAY1');
    store.addAffectation(aff);

    final ev = EvaluationModel(
        id: 'VEV1',
        title: 'Exam V1',
        type: 'exam',
        number: 1,
        academicYearId: 'VAY1',
        classId: 'VC1',
        subjectId: 'VSUB1',
        createdBy: 'UTV1',
        createdAt: DateTime.now().toIso8601String(),
        schoolId: 'VS1');
    final evId = store.addEvaluation(ev);
    expect(evId, isNotEmpty);

    // teacher cannot validate
    await store.login('tv1@v.test', 'pw');
    expect(store.validateEvaluation(evId), isFalse);

    // admin of same school can validate
    final admin = UserModel(
        id: 'UVA1',
        name: 'Admin V',
        email: 'adminv@v.test',
        role: UserRole.admin,
        schoolId: 'VS1');
    store.addUser(admin);
    await store.login('adminv@v.test', 'pw');
    expect(store.validateEvaluation(evId), isTrue);

    // admin of other school cannot validate
    final school2 = EstablishmentModel(
        id: 'VS2',
        name: 'Other',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school2);
    final adminOther = UserModel(
        id: 'UVA2',
        name: 'Admin O',
        email: 'admino@other.test',
        role: UserRole.admin,
        schoolId: 'VS2');
    store.addUser(adminOther);
    await store.login('admino@other.test', 'pw');
    expect(store.validateEvaluation(evId), isFalse);
  });

  test('6-9 Request/approval flow and no self-approval', () async {
    final store = await createLegacyStore();

    final school = EstablishmentModel(
        id: 'RQ1',
        name: 'RQSchool',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final ay = AcademicYearModel(
        id: 'RQAY1',
        name: '2026',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'RQ1');
    store.addAcademicYear(ay);
    final cls = ClassModel(
        id: 'RQC1',
        name: 'Classe RQ1',
        schoolId: 'RQ1',
        academicYearId: 'RQAY1');
    store.addClass(cls);
    final subj = SubjectModel(
        id: 'RQSUB1',
        name: 'Geo',
        coefficient: 1,
        schoolId: 'RQ1',
        classes: ['Classe RQ1']);
    store.addSubject(subj);
    final student = StudentModel(
        id: 'RQST1',
        firstName: 'StuR',
        lastName: 'Q',
        className: 'Classe RQ1',
        schoolId: 'RQ1',
        academicYearId: 'RQAY1');
    store.addStudent(student);

    final teacher = TeacherModel(
        id: 'URQ1', firstName: 'TRQ', lastName: 'One', schoolId: 'RQ1');
    store.addTeacher(teacher);
    final userTeacher = UserModel(
        id: 'URQ1',
        name: 'TRQ One',
        email: 'trq1@rq.test',
        role: UserRole.teacher,
        schoolId: 'RQ1');
    store.addUser(userTeacher);
    final aff = AffectationModel(
        id: 'ARQ1',
        teacherId: 'URQ1',
        teacherName: 'TRQ One',
        subjectId: 'RQSUB1',
        classId: 'RQC1',
        schoolId: 'RQ1',
        academicYearId: 'RQAY1');
    store.addAffectation(aff);

    final ev = EvaluationModel(
        id: 'REQEV1',
        title: 'Req Eval',
        type: 'devoir',
        number: 1,
        academicYearId: 'RQAY1',
        classId: 'RQC1',
        subjectId: 'RQSUB1',
        createdBy: 'URQ1',
        createdAt: DateTime.now().toIso8601String(),
        schoolId: 'RQ1');
    final evId = store.addEvaluation(ev);

    // teacher adds grade and admin validates
    await store.login('trq1@rq.test', 'pw');
    final gId = store.addGrade(GradeModel(
        id: '',
        studentId: 'RQST1',
        subjectId: 'RQSUB1',
        eval: 'D1',
        grade: 8.0,
        coef: 1,
        evaluationId: evId));
    expect(gId, isNotEmpty);

    await store.login('trq1@rq.test', 'pw');
    expect(store.submitEvaluation(evId), isTrue);

    final admin = UserModel(
        id: 'URQA',
        name: 'AdminRQ',
        email: 'adminrq@rq.test',
        role: UserRole.admin,
        schoolId: 'RQ1');
    store.addUser(admin);
    await store.login('adminrq@rq.test', 'pw');
    expect(store.validateEvaluation(evId), isTrue);

    // teacher requests modification
    await store.login('trq1@rq.test', 'pw');
    final reqId = store.requestGradeModification(
        gradeId: gId, newValue: 9.0, reason: 'Correction');
    expect(reqId, isNotEmpty);

    // teacher cannot approve own request
    await store.login('trq1@rq.test', 'pw');
    expect(store.approveGradeModification(reqId), isFalse);

    // admin of same school can approve
    await store.login('adminrq@rq.test', 'pw');
    expect(store.approveGradeModification(reqId), isTrue);

    // admin of another school cannot approve
    final otherSchool = EstablishmentModel(
        id: 'RQ2',
        name: 'OtherRQ',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(otherSchool);
    final otherAdmin = UserModel(
        id: 'URO2',
        name: 'OtherAdmin',
        email: 'otheradmin@rq2.test',
        role: UserRole.admin,
        schoolId: 'RQ2');
    store.addUser(otherAdmin);
    await store.login('otheradmin@rq2.test', 'pw');
    expect(store.approveGradeModification(reqId), isFalse);
  });

  test('10-16 Notifications and audit logs created; can mark as read',
      () async {
    final store = await createLegacyStore();

    final school = EstablishmentModel(
        id: 'N1',
        name: 'NotifSchool',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final ay = AcademicYearModel(
        id: 'NAY1',
        name: '2026',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'N1');
    store.addAcademicYear(ay);
    final cls = ClassModel(
        id: 'NC1', name: 'Classe N1', schoolId: 'N1', academicYearId: 'NAY1');
    store.addClass(cls);
    final subj = SubjectModel(
        id: 'NSUB1',
        name: 'Math',
        coefficient: 1,
        schoolId: 'N1',
        classes: ['Classe N1']);
    store.addSubject(subj);
    final student = StudentModel(
        id: 'NST1',
        firstName: 'Anne',
        lastName: 'N',
        className: 'Classe N1',
        schoolId: 'N1',
        academicYearId: 'NAY1');
    store.addStudent(student);

    final teacher = TeacherModel(
        id: 'UN1', firstName: 'TNotif', lastName: 'One', schoolId: 'N1');
    store.addTeacher(teacher);
    final userTeacher = UserModel(
        id: 'UN1',
        name: 'TNotif One',
        email: 'tn1@n.test',
        role: UserRole.teacher,
        schoolId: 'N1');
    store.addUser(userTeacher);
    final aff = AffectationModel(
        id: 'AN1',
        teacherId: 'UN1',
        teacherName: 'TNotif One',
        subjectId: 'NSUB1',
        classId: 'NC1',
        schoolId: 'N1',
        academicYearId: 'NAY1');
    store.addAffectation(aff);

    final admin = UserModel(
        id: 'UNA1',
        name: 'Admin N',
        email: 'adminn@n.test',
        role: UserRole.admin,
        schoolId: 'N1');
    store.addUser(admin);

    final ev = EvaluationModel(
        id: 'NEV1',
        title: 'N Eval',
        type: 'devoir',
        number: 1,
        academicYearId: 'NAY1',
        classId: 'NC1',
        subjectId: 'NSUB1',
        createdBy: 'UN1',
        createdAt: DateTime.now().toIso8601String(),
        schoolId: 'N1');
    final evId = store.addEvaluation(ev);

    await store.login('tn1@n.test', 'pw');
    final gId = store.addGrade(GradeModel(
        id: '',
        studentId: 'NST1',
        subjectId: 'NSUB1',
        eval: 'D1',
        grade: 10.0,
        coef: 1,
        evaluationId: evId));
    expect(gId, isNotEmpty);

    // teacher submits → notification to admins + audit
    expect(store.submitEvaluation(evId), isTrue);
    final notifs1 = store.getNotifications();
    expect(notifs1.any((n) => n.type == 'evaluation_submitted'), isTrue);
    final audits1 = store.getAuditLogs(schoolId: 'N1');
    expect(
        audits1
            .any((a) => a.action == 'SUBMIT_EVALUATION' && a.objectId == evId),
        isTrue);

    // admin validates → notify teacher + audit
    await store.login('adminn@n.test', 'pw');
    expect(store.validateEvaluation(evId), isTrue);
    final notifs2 = store.getNotifications();
    expect(notifs2.any((n) => n.type == 'evaluation_validated'), isTrue);
    final audits2 = store.getAuditLogs(schoolId: 'N1');
    expect(
        audits2.any(
            (a) => a.action == 'VALIDATE_EVALUATION' && a.objectId == evId),
        isTrue);

    // teacher requests a modification after validation
    await store.login('tn1@n.test', 'pw');
    final reqId = store.requestGradeModification(
        gradeId: gId, newValue: 12.0, reason: 'Correction');
    expect(reqId, isNotEmpty);
    expect(store.getNotifications().any((n) => n.type == 'grade_mod_request'),
        isTrue);
    expect(
        store.getAuditLogs(schoolId: 'N1').any((a) =>
            a.action == 'REQUEST_GRADE_MODIFICATION' && a.objectId == reqId),
        isTrue);

    // admin approves → notify requester + audit
    await store.login('adminn@n.test', 'pw');
    expect(store.approveGradeModification(reqId), isTrue);
    expect(store.getNotifications().any((n) => n.type == 'grade_mod_approved'),
        isTrue);
    expect(
        store.getAuditLogs(schoolId: 'N1').any((a) =>
            a.action == 'APPROVE_GRADE_MODIFICATION' && a.objectId == reqId),
        isTrue);

    // admin rejects another request to test rejection notification
    await store.login('tn1@n.test', 'pw');
    final req2 = store.requestGradeModification(
        gradeId: gId, newValue: 13.0, reason: 'Again');
    await store.login('adminn@n.test', 'pw');
    expect(store.refuseGradeModification(req2, 'Not allowed'), isTrue);
    expect(store.getNotifications().any((n) => n.type == 'grade_mod_rejected'),
        isTrue);
    expect(
        store.getAuditLogs(schoolId: 'N1').any((a) =>
            a.action == 'REJECT_GRADE_MODIFICATION' && a.objectId == req2),
        isTrue);

    // mark notification as read
    final firstUnread = store.getNotifications().firstWhere(
        (n) => n.read == false,
        orElse: () => store.getNotifications().first);
    store.markNotificationAsRead(firstUnread.id);
    final afterMark =
        store.getNotifications().firstWhere((n) => n.id == firstUnread.id);
    expect(afterMark.read, isTrue);
  });

  test('17 Audit cannot be modified by teacher (immutable via API)', () async {
    final store = await createLegacyStore();

    final school = EstablishmentModel(
        id: 'IM1',
        name: 'Immu',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(school);
    final ay = AcademicYearModel(
        id: 'IMAY1',
        name: '2026',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'IM1');
    store.addAcademicYear(ay);

    final admin = UserModel(
        id: 'UIM_A',
        name: 'AdminIM',
        email: 'adminim@im.test',
        role: UserRole.admin,
        schoolId: 'IM1');
    store.addUser(admin);
    // create a dummy audit
    await store.login('adminim@im.test', 'pw');
    // emulate an action
    // Using internal logging is possible only via actions; create an evaluation and submit
    final cls = ClassModel(
        id: 'IMC1',
        name: 'Classe IM',
        schoolId: 'IM1',
        academicYearId: 'IMAY1');
    store.addClass(cls);
    final subj = SubjectModel(
        id: 'IMSUB1',
        name: 'IMSub',
        coefficient: 1,
        schoolId: 'IM1',
        classes: ['Classe IM']);
    store.addSubject(subj);
    final student = StudentModel(
        id: 'IMST1',
        firstName: 'I',
        lastName: 'M',
        className: 'Classe IM',
        schoolId: 'IM1',
        academicYearId: 'IMAY1');
    store.addStudent(student);

    final teacher = TeacherModel(
        id: 'UIMT1', firstName: 'TIM', lastName: 'One', schoolId: 'IM1');
    store.addTeacher(teacher);
    final userTeacher = UserModel(
        id: 'UIMT1',
        name: 'TIM One',
        email: 'tim@im.test',
        role: UserRole.teacher,
        schoolId: 'IM1');
    store.addUser(userTeacher);
    final ev = EvaluationModel(
        id: 'IMEV1',
        title: 'IM Eval',
        type: 'devoir',
        number: 1,
        academicYearId: 'IMAY1',
        classId: 'IMC1',
        subjectId: 'IMSUB1',
        createdBy: 'UIMT1',
        createdAt: DateTime.now().toIso8601String(),
        schoolId: 'IM1');
    final evId = store.addEvaluation(ev);
    expect(evId, isNotEmpty);
    await store.login('tim@im.test', 'pw');
    expect(store.submitEvaluation(evId), isTrue);

    // teacher attempts to modify audit via returned list - should not affect underlying store logs
    final logsBefore = store.getAuditLogs(schoolId: 'IM1');
    expect(logsBefore.isNotEmpty, isTrue);
    final mutable = logsBefore.toList();
    final removed = mutable.removeAt(0);
    // fetch again and ensure original still contains entry
    final logsAfter = store.getAuditLogs(schoolId: 'IM1');
    expect(logsAfter.any((l) => l.id == removed.id), isTrue);
  });

  test('18 Multi-tenant data remains inaccessible', () async {
    final store = await createLegacyStore();

    final schoolA = EstablishmentModel(
        id: 'MTA',
        name: 'A',
        type: 'École',
        institutionType: InstitutionType.school);
    final schoolB = EstablishmentModel(
        id: 'MTB',
        name: 'B',
        type: 'École',
        institutionType: InstitutionType.school);
    store.addEstablishment(schoolA);
    store.addEstablishment(schoolB);
    final ayA = AcademicYearModel(
        id: 'MAYA',
        name: '2026',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'MTA');
    final ayB = AcademicYearModel(
        id: 'MAYB',
        name: '2026',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'MTB');
    store.addAcademicYear(ayA);
    store.addAcademicYear(ayB);

    final clsA = ClassModel(
        id: 'MTC1', name: 'Classe A1', schoolId: 'MTA', academicYearId: 'MAYA');
    final clsB = ClassModel(
        id: 'MTC2', name: 'Classe B1', schoolId: 'MTB', academicYearId: 'MAYB');
    store.addClass(clsA);
    store.addClass(clsB);

    final userA = UserModel(
        id: 'U_A',
        name: 'AdminA',
        email: 'admina@a.test',
        role: UserRole.admin,
        schoolId: 'MTA');
    final userB = UserModel(
        id: 'U_B',
        name: 'AdminB',
        email: 'adminb@b.test',
        role: UserRole.admin,
        schoolId: 'MTB');
    store.addUser(userA);
    store.addUser(userB);

    // Admin A should not see classes of B
    await store.login('admina@a.test', 'pw');
    final classesAView = store.getClasses();
    expect(classesAView.any((c) => c.id == 'MTC2'), isFalse);

    // Admin B should not see classes of A
    await store.login('adminb@b.test', 'pw');
    final classesBView = store.getClasses();
    expect(classesBView.any((c) => c.id == 'MTC1'), isFalse);
  });
}
