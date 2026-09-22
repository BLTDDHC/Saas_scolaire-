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

  group('AnnualBulletin store integration', () {
    test('create -> validate -> lock flow and permissions', () async {
      final store = await createLegacyStore(withSeedData: true);

      final seededStudent = store.getStudents().first;
      final teacherUser = UserModel(
        id: 'LEGACY_BULLETIN_TEACHER',
        name: 'Legacy Bulletin Teacher',
        email: 'legacy.bulletin.teacher@test.local',
        role: UserRole.teacher,
        schoolId: seededStudent.schoolId,
      );
      store.addUser(teacherUser);
      await store.login(teacherUser.email, legacyTestPassword);
      final students = store.getStudents();
      expect(students.isNotEmpty, true);
      final student = students.first;
      final classId = student.classId ?? '';
      final yearId = store.getSelectedAcademicYearId() ?? '';

      // Teachers should be allowed to request/create a bulletin but cannot validate/lock
      final createdId = store.createAnnualBulletinRecord(
          classId: classId, studentId: student.id);
      expect(createdId.isNotEmpty, true);

      final cannotValidate = store.validateAnnualBulletin(createdId);
      expect(cannotValidate, false);

      // login as admin
      final admin = store.getUsers().firstWhere(
            (u) => u.role == UserRole.admin && u.schoolId == student.schoolId,
          );
      await store.login(admin.email, 'test-only-password');

      final validated = store.validateAnnualBulletin(createdId);
      expect(validated, true);

      final locked = store.lockAnnualBulletinRecord(createdId);
      expect(locked, true);

      final isLocked = store.isAnnualBulletinLocked(student.id, yearId);
      expect(isLocked, true);
    });
  });
}
