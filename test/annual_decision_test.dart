import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/data/models/user_model.dart';

import 'package:edupro_flutter_web/core/constants/establishment_types.dart';
import 'support/legacy_store_test_harness.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('Annual decision workflow', () {
    test(
        'create decision from bulletin, propose, admin confirm, history, re-enroll',
        () async {
      final store = await createLegacyStore(withSeedData: true);

      final seededStudent = store.getStudents().first;
      final teacherUser = UserModel(
        id: 'LEGACY_DECISION_TEACHER',
        name: 'Legacy Decision Teacher',
        email: 'legacy.decision.teacher@test.local',
        role: UserRole.teacher,
        schoolId: seededStudent.schoolId,
      );
      store.addUser(teacherUser);
      await store.login(teacherUser.email, legacyTestPassword);
      final students = store.getStudents();
      expect(students.isNotEmpty, true);
      final student = students.first;

      // create a bulletin first
      final classId = student.classId ?? '';
      final createdBulletinId = store.createAnnualBulletinRecord(
          classId: classId, studentId: student.id);
      expect(createdBulletinId.isNotEmpty, true);

      // login as teacher and create a decision (teacher can create but cannot validate)
      final decisionId =
          store.createAnnualDecisionFromBulletin(createdBulletinId);
      expect(decisionId.isNotEmpty, true);

      final proposed =
          store.proposeAnnualDecisionFromBulletin(createdBulletinId);
      expect(proposed.isNotEmpty, true);

      // teacher cannot validate
      final cannotValidate = store.validateAnnualDecision(decisionId);
      expect(cannotValidate, false);

      // login as admin
      final admin = store.getUsers().firstWhere(
            (u) => u.role == UserRole.admin && u.schoolId == student.schoolId,
          );
      await store.login(admin.email, 'test-only-password');

      // admin can set/modify decision
      final setOk = store.setAnnualDecision(decisionId, 'ADMIS',
          reason: 'Conseil de classe');
      expect(setOk, true);

      // change is recorded in logs
      final logs = store.getDecisionChangeLogs(decisionId);
      expect(logs.isNotEmpty, true);
      expect(logs.last.newDecision == 'ADMIS', true);

      // admin validate
      final validated = store.validateAnnualDecision(decisionId);
      expect(validated, true);

      // after validation, non-superadmin cannot modify
      await store.login(teacherUser.email, 'test-only-password');
      final cannotModify =
          store.setAnnualDecision(decisionId, 'REDOUBLE', reason: 'Attempt');
      expect(cannotModify, false);

      // admin lock decision
      await store.login(admin.email, 'test-only-password');
      final locked = store.lockAnnualDecision(decisionId);
      expect(locked, true);

      // prepare re-enrollment (does not modify student)
      final nextYearId = (store.getAcademicYears().firstWhere(
          (y) => y.id != store.getSelectedAcademicYearId(),
          orElse: () => store.getAcademicYears().first)).id;
      final reId =
          store.prepareReEnrollment(decisionId, nextYearId, toClassId: null);
      expect(reId.isNotEmpty, true);

      final reReqs = store.getReEnrollmentRequestsForStudent(student.id);
      expect(reReqs.any((r) => r.id == reId), true);

      // ensure student academicYear not modified
      final freshStudent =
          store.getStudents().firstWhere((s) => s.id == student.id);
      expect(freshStudent.academicYearId == student.academicYearId, true);
    });
  });
}
