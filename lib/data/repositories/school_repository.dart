import 'dart:typed_data';

import '../datasources/api_client.dart';

class SchoolRepository {
  SchoolRepository(this._api);
  final ApiClient _api;
  Future<List<Map<String, dynamic>>> workflowNotifications() async =>
      List<Map<String, dynamic>>.from(
          (await _api.get('/api/v1/notifications') as List)
              .map((row) => Map<String, dynamic>.from(row)));
  Future<void> markWorkflowNotificationRead(String id) =>
      _api.put('/api/v1/notifications/$id/read', const {});
  Future<void> markAllWorkflowNotificationsRead() =>
      _api.post('/api/v1/notifications/read-all', const {});
  Future<Map<String, dynamic>> notifyTeachersInApp(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _api.post(
          '/api/v1/school/notifications/teachers', payload));
  Future<List<Map<String, dynamic>>> schoolDocuments() async =>
      List<Map<String, dynamic>>.from(
          (await _api.get('/api/v1/documents') as List)
              .map((row) => Map<String, dynamic>.from(row)));
  Future<Map<String, dynamic>> financeWorkspace(
          Map<String, String> query) async =>
      Map<String, dynamic>.from(await _api.get(
          '/api/v1/school/finance/roster?${Uri(queryParameters: query).query}'));
  Future<Map<String, dynamic>> financeMonthlySituation(
          String registrationId, Map<String, String> query) async =>
      Map<String, dynamic>.from(await _api.get(
          '/api/v1/school/finance/monthly-situation/${Uri.encodeComponent(registrationId)}?${Uri(queryParameters: query).query}'));

  Future<Map<String, dynamic>> parentFinanceSituation(
          String studentId, String academicYearId) async =>
      Map<String, dynamic>.from(await _api.get(
          '/api/v1/school/finance/parent-situation/${Uri.encodeComponent(studentId)}?${Uri(queryParameters: {
            'academic_year_id': academicYearId,
          }).query}'));
  Future<Map<String, dynamic>> schoolFinancePayment(
          Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/finance/school-payments', body));
  Future<Map<String, dynamic>> updateFinanceTariff(
          String id, Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/school/finance/fees/$id', body));
  Future<Map<String, dynamic>> financeReceipt(
          String id, String? schoolId) async =>
      Map<String, dynamic>.from(await _api.get(
          '/api/v1/school/finance/receipts/$id?${Uri(queryParameters: {
            if (schoolId != null) 'school_id': schoolId
          }).query}'));
  Future<Map<String, dynamic>> login(
          String identifier, String password) async =>
      Map<String, dynamic>.from(await _api.post('/api/v1/auth/login',
          {'identifier': identifier, 'password': password}));
  Future<Map<String, dynamic>> me() async =>
      Map<String, dynamic>.from(await _api.get('/api/v1/auth/me'));
  Future<Map<String, dynamic>> updateOwnProfile(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/auth/profile', payload));
  Future<Map<String, dynamic>> updateOwnProfilePhoto(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/auth/profile/photo', payload));
  Future<Uint8List> ownProfilePhoto() =>
      _api.getBytes('/api/v1/auth/profile/photo');
  Future<Map<String, dynamic>> changeRequiredPassword(
          String newPassword) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/auth/change-password', {
        'new_password': newPassword,
        'new_password_confirmation': newPassword,
      }));
  Future<Map<String, dynamic>> changePassword(String currentPassword,
          String newPassword, String confirmation) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/auth/change-password', {
        'current_password': currentPassword,
        'new_password': newPassword,
        'new_password_confirmation': confirmation,
      }));
  Future<Map<String, dynamic>> adminEstablishment() async =>
      Map<String, dynamic>.from(await _api.get('/api/v1/admin/establishment'));
  Future<Map<String, dynamic>> updateAdminEstablishment(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/admin/establishment', payload));
  Future<Map<String, List<Map<String, dynamic>>>> bootstrap() async {
    final raw = Map<String, dynamic>.from(await _api.get('/api/v1/bootstrap'));
    return raw.map((key, value) => MapEntry(
        key,
        List<Map<String, dynamic>>.from(
            (value as List).map((x) => Map<String, dynamic>.from(x)))));
  }

  Future<Map<String, dynamic>> createUser(Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _api.post('/api/v1/users', payload));
  Future<Map<String, dynamic>> superAdminDashboard() async =>
      Map<String, dynamic>.from(await _api.get('/api/v1/superadmin/dashboard'));
  Future<Map<String, dynamic>> superAdminSubscriptions() async =>
      Map<String, dynamic>.from(
          await _api.get('/api/v1/superadmin/subscriptions'));
  Future<Map<String, dynamic>> renewSuperAdminSubscription(
          String id, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _api.post(
          '/api/v1/superadmin/subscriptions/$id/renew', payload));
  Future<List<Map<String, dynamic>>> superAdminModuleCatalog() async =>
      List<Map<String, dynamic>>.from(
          (await _api.get('/api/v1/superadmin/modules/catalog') as List)
              .map((item) => Map<String, dynamic>.from(item)));
  Future<List<Map<String, dynamic>>> superAdminPlans() async =>
      List<Map<String, dynamic>>.from(
          (await _api.get('/api/v1/superadmin/plans') as List)
              .map((item) => Map<String, dynamic>.from(item)));
  Future<Map<String, dynamic>> superAdminPlan(String id) async =>
      Map<String, dynamic>.from(await _api.get('/api/v1/superadmin/plans/$id'));
  Future<Map<String, dynamic>> createSuperAdminPlan(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/superadmin/plans', payload));
  Future<Map<String, dynamic>> updateSuperAdminPlan(
          String id, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/superadmin/plans/$id', payload));
  Future<List<Map<String, dynamic>>> superAdminEstablishments(
      {String? search, String? status}) async {
    final query = <String, String>{
      if (search != null && search.isNotEmpty) 'search': search,
      if (status != null && status.isNotEmpty) 'status_filter': status,
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return List<Map<String, dynamic>>.from(
        (await _api.get('/api/v1/superadmin/establishments$suffix') as List)
            .map((item) => Map<String, dynamic>.from(item)));
  }

  Future<Map<String, dynamic>> superAdminEstablishment(String id) async =>
      Map<String, dynamic>.from(
          await _api.get('/api/v1/superadmin/establishments/$id'));
  Future<Map<String, dynamic>> superAdminDirections(
          String establishmentId) async =>
      Map<String, dynamic>.from(await _api.get(
          '/api/v1/superadmin/establishments/$establishmentId/directions'));
  Future<Map<String, dynamic>> createSuperAdminDirection(
          String establishmentId, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _api.post(
          '/api/v1/superadmin/establishments/$establishmentId/directions',
          payload));
  Future<Map<String, dynamic>> updateSuperAdminDirection(
          String directionId, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _api.put(
          '/api/v1/superadmin/directions/$directionId', payload));
  Future<Map<String, dynamic>> assignDirectionAdministrator(
          String directionId, String? userId) async =>
      Map<String, dynamic>.from(await _api.put(
          '/api/v1/superadmin/directions/$directionId/administrator',
          {'userId': userId}));
  Future<Map<String, dynamic>> superAdminEstablishmentModules(
          String id) async =>
      Map<String, dynamic>.from(
          await _api.get('/api/v1/superadmin/establishments/$id/modules'));
  Future<Map<String, dynamic>> updateSuperAdminEstablishmentModules(
          String id, List<String> enabledModules) async =>
      Map<String, dynamic>.from(await _api.put(
          '/api/v1/superadmin/establishments/$id/modules',
          {'enabledModules': enabledModules}));

  Future<Map<String, dynamic>> createSuperAdminEstablishment(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/superadmin/establishments', payload));
  Future<Map<String, dynamic>> updateSuperAdminEstablishment(
          String id, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _api
          .put('/api/v1/superadmin/establishments/$id', {'payload': payload}));
  Future<List<Map<String, dynamic>>> superAdminUsers({
    String? role,
    String? search,
    String? status,
    String? establishmentId,
  }) async {
    final query = <String, String>{
      if (role != null) 'role': role,
      if (search != null && search.isNotEmpty) 'search': search,
      if (status != null && status.isNotEmpty) 'status_filter': status,
      if (establishmentId != null && establishmentId.isNotEmpty)
        'establishment_id': establishmentId,
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return List<Map<String, dynamic>>.from(
        (await _api.get('/api/v1/superadmin/users$suffix') as List)
            .map((item) => Map<String, dynamic>.from(item)));
  }

  Future<Map<String, dynamic>> superAdminUser(String userId) async =>
      Map<String, dynamic>.from(
          await _api.get('/api/v1/superadmin/users/$userId'));

  Future<Map<String, dynamic>> updateAdminAccountStatus(
          String userId, String status) async =>
      Map<String, dynamic>.from(await _api
          .put('/api/v1/superadmin/users/$userId/status', {'status': status}));

  Future<String> resetAdminPassword(String userId) async {
    final response = Map<String, dynamic>.from(await _api
        .post('/api/v1/superadmin/users/$userId/reset-password', const {}));
    final password = response['temporaryPassword'];
    if (password is! String || password.isEmpty) {
      throw ApiException('Réponse de réinitialisation invalide', 500);
    }
    return password;
  }

  Future<List<Map<String, dynamic>>> schoolCycleCatalog() async =>
      List<Map<String, dynamic>>.from(
          (await _api.get('/api/v1/school/cycles/catalog') as List)
              .map((item) => Map<String, dynamic>.from(item)));

  Future<List<Map<String, dynamic>>> schoolCycles({String? schoolId}) async {
    final suffix = schoolId == null || schoolId.isEmpty
        ? ''
        : '?${Uri(queryParameters: {'school_id': schoolId}).query}';
    return List<Map<String, dynamic>>.from(
        (await _api.get('/api/v1/school/cycles$suffix') as List)
            .map((item) => Map<String, dynamic>.from(item)));
  }

  Future<Map<String, dynamic>> createSchoolCycle(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/cycles', payload));

  Future<Map<String, dynamic>> updateSchoolCycle(
          String cycleId, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/school/cycles/$cycleId', payload));

  Future<List<Map<String, dynamic>>> schoolLevels(String cycleId) async =>
      List<Map<String, dynamic>>.from(
          (await _api.get('/api/v1/school/cycles/$cycleId/levels') as List)
              .map((item) => Map<String, dynamic>.from(item)));

  Future<Map<String, dynamic>> createSchoolLevel(
          String cycleId, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/cycles/$cycleId/levels', payload));

  Future<Map<String, dynamic>> updateSchoolLevel(
          String levelId, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/school/levels/$levelId', payload));

  Future<List<Map<String, dynamic>>> academicYears({String? schoolId}) async {
    final suffix = schoolId == null || schoolId.isEmpty
        ? ''
        : '?${Uri(queryParameters: {'school_id': schoolId}).query}';
    return List<Map<String, dynamic>>.from(
        (await _api.get('/api/v1/school/academic-years$suffix') as List)
            .map((item) => Map<String, dynamic>.from(item)));
  }

  Future<Map<String, dynamic>> createAcademicYear(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/academic-years', payload));

  Future<Map<String, dynamic>> updateAcademicYear(
          String yearId, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/school/academic-years/$yearId', payload));

  Future<Map<String, dynamic>> activateAcademicYear(String yearId) async =>
      Map<String, dynamic>.from(await _api
          .put('/api/v1/school/academic-years/$yearId/activate', const {}));

  Future<Map<String, dynamic>> copyAcademicYearConfiguration(
          String targetYearId, String sourceYearId) async =>
      Map<String, dynamic>.from(await _api.post(
          '/api/v1/school/academic-years/$targetYearId/copy-configuration',
          {'sourceYearId': sourceYearId}));

  Future<void> deleteAcademicYear(String yearId) =>
      _api.delete('/api/v1/school/academic-years/$yearId');

  Future<List<Map<String, dynamic>>> schoolClasses({
    String? schoolId,
    String? academicYearId,
    String? cycleId,
    String? levelId,
  }) async {
    final query = <String, String>{
      if (schoolId != null && schoolId.isNotEmpty) 'school_id': schoolId,
      if (academicYearId != null && academicYearId.isNotEmpty)
        'academic_year_id': academicYearId,
      if (cycleId != null && cycleId.isNotEmpty) 'cycle_id': cycleId,
      if (levelId != null && levelId.isNotEmpty) 'level_id': levelId,
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return List<Map<String, dynamic>>.from(
        (await _api.get('/api/v1/school/classes$suffix') as List)
            .map((item) => Map<String, dynamic>.from(item)));
  }

  Future<Map<String, dynamic>> createSchoolClass(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/classes', payload));

  Future<Map<String, dynamic>> updateSchoolClass(
          String classId, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/school/classes/$classId', payload));

  Future<void> deleteSchoolClass(String classId) =>
      _api.delete('/api/v1/school/classes/$classId');

  Future<Map<String, dynamic>> setClassMainTeacher(
          String classId, String teacherId) async =>
      Map<String, dynamic>.from(await _api.put(
          '/api/v1/school/classes/$classId/main-teacher',
          {'teacherId': teacherId}));

  Future<void> clearClassMainTeacher(String classId) =>
      _api.delete('/api/v1/school/classes/$classId/main-teacher');

  Future<List<Map<String, dynamic>>> students({
    String? academicYearId,
    String? cycleId,
    String? levelId,
    String? classId,
    String? search,
  }) async {
    final query = <String, String>{
      if (academicYearId != null && academicYearId.isNotEmpty)
        'academic_year_id': academicYearId,
      if (cycleId != null && cycleId.isNotEmpty) 'cycle_id': cycleId,
      if (levelId != null && levelId.isNotEmpty) 'level_id': levelId,
      if (classId != null && classId.isNotEmpty) 'class_id': classId,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return List<Map<String, dynamic>>.from(
        (await _api.get('/api/v1/school/students$suffix') as List)
            .map((item) => Map<String, dynamic>.from(item)));
  }

  Future<Map<String, dynamic>> reEnrollmentCandidates({
    required String targetAcademicYearId,
    String? classId,
    String? lastName,
    String? firstName,
    String? matricule,
  }) async {
    final query = <String, String>{
      'target_academic_year_id': targetAcademicYearId,
      if (classId != null && classId.isNotEmpty) 'class_id': classId,
      if (lastName != null && lastName.trim().isNotEmpty)
        'last_name': lastName.trim(),
      if (firstName != null && firstName.trim().isNotEmpty)
        'first_name': firstName.trim(),
      if (matricule != null && matricule.trim().isNotEmpty)
        'matricule': matricule.trim(),
    };
    return Map<String, dynamic>.from(await _api.get(
        '/api/v1/school/students/re-enrollment-candidates?${Uri(queryParameters: query).query}'));
  }

  Future<Map<String, dynamic>> createStudent(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/students', payload));

  Future<Map<String, dynamic>> studentDetails(String studentId,
          {String? academicYearId}) async =>
      Map<String, dynamic>.from(await _api.get(
          '/api/v1/school/students/$studentId${academicYearId == null ? '' : '?${Uri(queryParameters: {
                  'academic_year_id': academicYearId
                }).query}'}'));

  Future<Map<String, dynamic>> updateStudent(
          String studentId, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/school/students/$studentId', payload));

  Future<Map<String, dynamic>> importStudentPhotos(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _api
          .post('/api/v1/school/students/photos/import', payload));

  Future<Map<String, dynamic>> updateStudentPhoto(
          String studentId, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _api
          .put('/api/v1/school/students/$studentId/photo', payload));

  Future<Uint8List> studentPhoto(String studentId) =>
      _api.getBytes('/api/v1/school/students/$studentId/photo');

  Future<Map<String, dynamic>> provisionStudentAccess(String studentId) async =>
      Map<String, dynamic>.from(await _api
          .post('/api/v1/school/students/$studentId/access', const {}));

  Future<void> archiveStudent(String studentId) =>
      _api.delete('/api/v1/school/students/$studentId');

  Future<List<Map<String, dynamic>>> studentRegistrations(
          String studentId) async =>
      List<Map<String, dynamic>>.from((await _api
              .get('/api/v1/school/students/$studentId/registrations') as List)
          .map((item) => Map<String, dynamic>.from(item)));

  Future<Map<String, dynamic>> createStudentRegistration(
          String studentId, String classId,
          {String? schoolRegime,
          bool hasTd = false,
          Map<String, dynamic> options = const {}}) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/students/$studentId/registrations', {
        'classId': classId,
        if (schoolRegime != null) 'schoolRegime': schoolRegime,
        'hasTd': hasTd,
        'options': options,
      }));

  Future<Map<String, dynamic>> updateStudentRegistration(
          String registrationId, String classId) async =>
      Map<String, dynamic>.from(await _api.put(
          '/api/v1/school/student-registrations/$registrationId',
          {'classId': classId}));

  Future<Map<String, dynamic>> changeStudentRegime(
          String registrationId, String regime, String effectiveDate) async =>
      Map<String, dynamic>.from(await _api.post(
          '/api/v1/school/student-registrations/$registrationId/regime',
          {'regime': regime, 'effectiveDate': effectiveDate}));

  Future<List<Map<String, dynamic>>> preEnrollments(
      {String? academicYearId, String? status}) async {
    final query = <String, String>{
      if (academicYearId != null && academicYearId.isNotEmpty)
        'academic_year_id': academicYearId,
      if (status != null && status.isNotEmpty) 'status_filter': status,
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return List<Map<String, dynamic>>.from(
        (await _api.get('/api/v1/school/pre-enrollments$suffix') as List)
            .map((item) => Map<String, dynamic>.from(item)));
  }

  Future<Map<String, dynamic>> createPreEnrollment(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/pre-enrollments', payload));

  Future<Map<String, dynamic>> updatePreEnrollmentStatus(
          String id, String status, {String? decisionNote}) async =>
      Map<String, dynamic>.from(await _api.put(
          '/api/v1/school/pre-enrollments/$id/status',
          {'status': status, 'decisionNote': decisionNote}));

  Future<Map<String, dynamic>> updatePreEnrollment(
          String id, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/school/pre-enrollments/$id', payload));

  Future<Map<String, dynamic>> approvePreEnrollment(String id,
          {String? classId,
          String schoolRegime = 'normal',
          bool hasTd = false,
          Map<String, dynamic> options = const {}}) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/pre-enrollments/$id/approve', {
        if (classId != null) 'classId': classId,
        if (schoolRegime != null) 'schoolRegime': schoolRegime,
        'hasTd': hasTd,
        'options': options,
      }));

  Future<List<Map<String, dynamic>>> guardians({String? search}) async {
    final suffix = search == null || search.trim().isEmpty
        ? ''
        : '?${Uri(queryParameters: {'search': search.trim()}).query}';
    return List<Map<String, dynamic>>.from(
        (await _api.get('/api/v1/school/guardians$suffix') as List)
            .map((item) => Map<String, dynamic>.from(item)));
  }

  Future<Map<String, dynamic>> createGuardian(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/guardians', payload));

  Future<Map<String, dynamic>> updateGuardian(
          String guardianId, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/school/guardians/$guardianId', payload));

  Future<Map<String, dynamic>> provisionParentAccess(String guardianId) async =>
      Map<String, dynamic>.from(await _api
          .post('/api/v1/school/guardians/$guardianId/access', const {}));

  Future<Map<String, dynamic>> linkStudentGuardian(String studentId,
          String guardianId, String relationship, bool isPrimary) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/students/$studentId/guardians', {
        'guardianId': guardianId,
        'relationship': relationship,
        'isPrimary': isPrimary,
      }));

  Future<List<Map<String, dynamic>>> teachers(
      {String? search, String? status}) async {
    final query = <String, String>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (status != null && status.isNotEmpty) 'status_filter': status,
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return List<Map<String, dynamic>>.from(
        (await _api.get('/api/v1/school/teachers$suffix') as List)
            .map((item) => Map<String, dynamic>.from(item)));
  }

  Future<Map<String, dynamic>> createTeacher(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/teachers', payload));

  Future<Map<String, dynamic>> updateTeacher(
          String teacherId, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/school/teachers/$teacherId', payload));

  Future<Map<String, dynamic>> provisionTeacherAccess(String teacherId) async =>
      Map<String, dynamic>.from(await _api
          .post('/api/v1/school/teachers/$teacherId/access', const {}));

  Future<Map<String, dynamic>> teacherWorkspace() async =>
      Map<String, dynamic>.from(
          await _api.get('/api/v1/school/teacher/workspace'));

  Future<Map<String, dynamic>> studentWorkspace() async =>
      Map<String, dynamic>.from(
          await _api.get('/api/v1/school/student/workspace'));

  Future<Map<String, dynamic>> parentWorkspace() async =>
      Map<String, dynamic>.from(
          await _api.get('/api/v1/school/parent/workspace'));

  Future<void> archiveTeacher(String teacherId) =>
      _api.delete('/api/v1/school/teachers/$teacherId');

  Future<List<Map<String, dynamic>>> subjects() async =>
      List<Map<String, dynamic>>.from(
          (await _api.get('/api/v1/school/subjects') as List)
              .map((item) => Map<String, dynamic>.from(item)));

  Future<Map<String, dynamic>> createSubject(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/subjects', payload));

  Future<Map<String, dynamic>> updateSubject(
          String subjectId, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/school/subjects/$subjectId', payload));

  Future<void> archiveSubject(String subjectId) =>
      _api.delete('/api/v1/school/subjects/$subjectId');

  Future<Map<String, dynamic>> updateSubjectLevelSetting(
          String subjectId, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _api.put(
          '/api/v1/school/subjects/$subjectId/level-setting', payload));

  Future<List<Map<String, dynamic>>> affectations(
      {String? academicYearId}) async {
    final suffix = academicYearId == null || academicYearId.isEmpty
        ? ''
        : '?${Uri(queryParameters: {
                'academic_year_id': academicYearId
              }).query}';
    return List<Map<String, dynamic>>.from(
        (await _api.get('/api/v1/school/affectations$suffix') as List)
            .map((item) => Map<String, dynamic>.from(item)));
  }

  Future<Map<String, dynamic>> createAffectation(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/affectations', payload));

  Future<Map<String, dynamic>> updateAffectation(
          String affectationId, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _api.put(
          '/api/v1/school/affectations/$affectationId', payload));

  Future<void> archiveAffectation(String affectationId) =>
      _api.delete('/api/v1/school/affectations/$affectationId');

  Future<List<Map<String, dynamic>>> academicPeriods(
          String academicYearId) async =>
      List<Map<String, dynamic>>.from((await _api.get(
              '/api/v1/school/academic-periods?${Uri(queryParameters: {
            'academic_year_id': academicYearId
          }).query}') as List)
          .map((item) => Map<String, dynamic>.from(item)));

  Future<Map<String, dynamic>> createAcademicPeriod(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/academic-periods', payload));

  Future<Map<String, dynamic>> updateAcademicPeriod(
          String id, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/school/academic-periods/$id', payload));

  Future<void> archiveAcademicPeriod(String id) =>
      _api.delete('/api/v1/school/academic-periods/$id');

  Future<List<Map<String, dynamic>>> evaluations({
    String? academicYearId,
    String? classId,
    String? subjectId,
    String? periodId,
  }) async {
    final query = <String, String>{
      if (academicYearId != null && academicYearId.isNotEmpty)
        'academic_year_id': academicYearId,
      if (classId != null && classId.isNotEmpty) 'class_id': classId,
      if (subjectId != null && subjectId.isNotEmpty) 'subject_id': subjectId,
      if (periodId != null && periodId.isNotEmpty) 'period_id': periodId,
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return List<Map<String, dynamic>>.from(
        (await _api.get('/api/v1/school/evaluations$suffix') as List)
            .map((item) => Map<String, dynamic>.from(item)));
  }

  Future<Map<String, dynamic>> createEvaluation(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/evaluations', payload));

  Future<Map<String, dynamic>> createEvaluationProgram(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/evaluation-programs', payload));

  Future<Map<String, dynamic>> updateEvaluationStatus(
          String evaluationId, String status, {String? reason}) async =>
      Map<String, dynamic>.from(await _api.put(
          '/api/v1/school/evaluations/$evaluationId/status',
          {'status': status, if (reason != null) 'reason': reason}));

  Future<List<Map<String, dynamic>>> evaluationGrades(
          String evaluationId) async =>
      List<Map<String, dynamic>>.from((await _api
              .get('/api/v1/school/evaluations/$evaluationId/grades') as List)
          .map((item) => Map<String, dynamic>.from(item)));

  Future<List<Map<String, dynamic>>> grades({
    String? academicYearId,
    String? classId,
  }) async {
    final query = <String, String>{
      if (academicYearId != null && academicYearId.isNotEmpty)
        'academic_year_id': academicYearId,
      if (classId != null && classId.isNotEmpty) 'class_id': classId,
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return List<Map<String, dynamic>>.from(
        (await _api.get('/api/v1/school/grades$suffix') as List)
            .map((item) => Map<String, dynamic>.from(item)));
  }

  Future<List<Map<String, dynamic>>> saveEvaluationGrades(
          String evaluationId, List<Map<String, dynamic>> entries,
          {String? correctionReason}) async =>
      List<Map<String, dynamic>>.from(
          (await _api.put('/api/v1/school/evaluations/$evaluationId/grades', {
        'entries': entries,
        if (correctionReason != null) 'correctionReason': correctionReason,
      }) as List)
              .map((item) => Map<String, dynamic>.from(item)));

  Future<Map<String, dynamic>> schoolResults(String classId, String periodId,
          {String? eventCode}) async =>
      Map<String, dynamic>.from(
          await _api.get('/api/v1/school/results?${Uri(queryParameters: {
            'class_id': classId,
            'period_id': periodId,
            if (eventCode != null) 'event_code': eventCode,
          }).query}'));

  Future<Map<String, dynamic>> calculateSchoolResults(
          String classId, String periodId,
          {String? eventCode}) async =>
      Map<String, dynamic>.from(await _api.post(
          '/api/v1/school/results/calculate?${Uri(queryParameters: {
                'class_id': classId,
                'period_id': periodId,
                if (eventCode != null) 'event_code': eventCode,
              }).query}',
          const {}));

  Future<Map<String, dynamic>> submissionStatus(String classId, String periodId,
          {String? eventCode}) async =>
      Map<String, dynamic>.from(
          await _api.get('/api/v1/school/submissions?${Uri(queryParameters: {
            'class_id': classId,
            'period_id': periodId,
            if (eventCode != null) 'event_code': eventCode,
          }).query}'));

  Future<Map<String, dynamic>> studentBulletin(
          String studentId, String academicYearId) async =>
      Map<String, dynamic>.from(await _api.get(
          '/api/v1/school/students/$studentId/bulletin?${Uri(queryParameters: {
            'academic_year_id': academicYearId,
          }).query}'));

  Future<List<Map<String, dynamic>>> attendance(String classId,
      {String? date, String? scheduleId}) async {
    final query = {
      'class_id': classId,
      if (date != null && date.isNotEmpty) 'attendance_date': date,
      if (scheduleId != null && scheduleId.isNotEmpty)
        'schedule_id': scheduleId,
    };
    return List<Map<String, dynamic>>.from((await _api.get(
                '/api/v1/school/attendance?${Uri(queryParameters: query).query}')
            as List)
        .map((item) => Map<String, dynamic>.from(item)));
  }

  Future<List<Map<String, dynamic>>> saveAttendance(
          Map<String, dynamic> payload) async =>
      List<Map<String, dynamic>>.from(
          (await _api.put('/api/v1/school/attendance', payload) as List)
              .map((item) => Map<String, dynamic>.from(item)));

  Future<Map<String, dynamic>> attendanceSheet(
          String classId, String scheduleId, String date) async =>
      Map<String, dynamic>.from(await _api.get(
          '/api/v1/school/attendance/sheet?${Uri(queryParameters: {
            'class_id': classId,
            'schedule_id': scheduleId,
            'attendance_date': date
          }).query}'));

  Future<Map<String, dynamic>> attendanceReport(
          Map<String, String> filters) async =>
      Map<String, dynamic>.from(await _api.get(
          '/api/v1/school/attendance/report?${Uri(queryParameters: filters).query}'));

  Future<List<Map<String, dynamic>>> attendanceContexts() async =>
      List<Map<String, dynamic>>.from(
          await _api.get('/api/v1/school/attendance/contexts'));

  Future<List<Map<String, dynamic>>> behaviorEvents({
    String? classId,
    String? studentId,
    String? academicYearId,
    String? periodId,
  }) async {
    final query = <String, String>{
      if (classId != null && classId.isNotEmpty) 'class_id': classId,
      if (studentId != null && studentId.isNotEmpty) 'student_id': studentId,
      if (academicYearId != null && academicYearId.isNotEmpty)
        'academic_year_id': academicYearId,
      if (periodId != null && periodId.isNotEmpty) 'period_id': periodId,
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return List<Map<String, dynamic>>.from(
        (await _api.get('/api/v1/school/behavior$suffix') as List)
            .map((item) => Map<String, dynamic>.from(item)));
  }

  Future<Map<String, dynamic>> createBehaviorEvent(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/behavior', payload));

  Future<List<Map<String, dynamic>>> submitBehavior(
          Map<String, dynamic> payload) async =>
      List<Map<String, dynamic>>.from(
          (await _api.put('/api/v1/school/behavior', payload) as List)
              .map((item) => Map<String, dynamic>.from(item)));

  Future<void> archiveBehaviorEvent(String id) =>
      _api.delete('/api/v1/school/behavior/$id');

  Future<Map<String, dynamic>> behaviorResults(
          String classId, String periodId) async =>
      Map<String, dynamic>.from(await _api.get(
          '/api/v1/school/behavior/results?${Uri(queryParameters: {
            'class_id': classId,
            'period_id': periodId
          }).query}'));

  Future<List<Map<String, dynamic>>> behaviorContexts() async =>
      List<Map<String, dynamic>>.from(
          await _api.get('/api/v1/school/behavior/contexts'));

  Future<Map<String, dynamic>> calculateBehavior(
          String classId, String periodId) async =>
      Map<String, dynamic>.from(await _api.post(
          '/api/v1/school/behavior/calculate',
          {'classId': classId, 'periodId': periodId}));

  Future<List<Map<String, dynamic>>> assignments({
    String? academicYearId,
    String? classId,
  }) async {
    final query = <String, String>{
      if (academicYearId != null && academicYearId.isNotEmpty)
        'academic_year_id': academicYearId,
      if (classId != null && classId.isNotEmpty) 'class_id': classId,
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return List<Map<String, dynamic>>.from(
        (await _api.get('/api/v1/school/assignments$suffix') as List)
            .map((item) => Map<String, dynamic>.from(item)));
  }

  Future<Map<String, dynamic>> createAssignment(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/assignments', payload));

  Future<Map<String, dynamic>> updateAssignment(
          String id, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/school/assignments/$id', payload));

  Future<void> archiveAssignment(String id) =>
      _api.delete('/api/v1/school/assignments/$id');

  Future<List<Map<String, dynamic>>> schedule(String academicYearId,
      {String? classId}) async {
    final query = {
      'academic_year_id': academicYearId,
      if (classId != null && classId.isNotEmpty) 'class_id': classId,
    };
    return List<Map<String, dynamic>>.from((await _api.get(
                '/api/v1/school/schedule?${Uri(queryParameters: query).query}')
            as List)
        .map((item) => Map<String, dynamic>.from(item)));
  }

  Future<Map<String, dynamic>> createScheduleEntry(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/schedule', payload));

  Future<Map<String, dynamic>> updateScheduleEntry(
          String id, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/school/schedule/$id', payload));

  Future<void> archiveScheduleEntry(String id) =>
      _api.delete('/api/v1/school/schedule/$id');

  Future<List<Map<String, dynamic>>> schoolSeries({String? cycleId}) async {
    final suffix = cycleId == null || cycleId.isEmpty
        ? ''
        : '?${Uri(queryParameters: {'cycle_id': cycleId}).query}';
    return List<Map<String, dynamic>>.from(
        (await _api.get('/api/v1/school/series$suffix') as List)
            .map((item) => Map<String, dynamic>.from(item)));
  }

  Future<Map<String, dynamic>> createSchoolSeries(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/series', payload));

  Future<Map<String, dynamic>> updateSchoolSeries(
          String id, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/school/series/$id', payload));

  Future<void> archiveSchoolSeries(String id) =>
      _api.delete('/api/v1/school/series/$id');

  Future<Map<String, dynamic>?> calendarSettings(String academicYearId) async {
    final value = await _api.get(
        '/api/v1/school/calendar/settings?${Uri(queryParameters: {
          'academic_year_id': academicYearId
        }).query}');
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  Future<Map<String, dynamic>> saveCalendarSettings(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/school/calendar/settings', payload));

  Future<List<Map<String, dynamic>>> calendarEvents(
          String academicYearId) async =>
      List<Map<String, dynamic>>.from((await _api.get(
              '/api/v1/school/calendar/events?${Uri(queryParameters: {
            'academic_year_id': academicYearId
          }).query}') as List)
          .map((item) => Map<String, dynamic>.from(item)));

  Future<Map<String, dynamic>> createCalendarEvent(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/calendar/events', payload));

  Future<Map<String, dynamic>> updateCalendarEvent(
          String id, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/school/calendar/events/$id', payload));

  Future<void> archiveCalendarEvent(String id) =>
      _api.delete('/api/v1/school/calendar/events/$id');

  Future<List<Map<String, dynamic>>> evaluationRules(
          String academicYearId) async =>
      List<Map<String, dynamic>>.from((await _api.get(
              '/api/v1/school/evaluation-rules?${Uri(queryParameters: {
            'academic_year_id': academicYearId
          }).query}') as List)
          .map((item) => Map<String, dynamic>.from(item)));

  Future<Map<String, dynamic>> createEvaluationRule(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/evaluation-rules', payload));

  Future<Map<String, dynamic>> updateEvaluationRule(
          String id, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.put('/api/v1/school/evaluation-rules/$id', payload));

  Future<void> archiveEvaluationRule(String id) =>
      _api.delete('/api/v1/school/evaluation-rules/$id');

  Future<Map<String, dynamic>> saveAnnualDecision(
          String studentId, Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _api.put(
          '/api/v1/school/students/$studentId/annual-decision', payload));

  Future<List<Map<String, dynamic>>> annualDecisions(
          String academicYearId) async =>
      List<Map<String, dynamic>>.from((await _api.get(
              '/api/v1/school/annual-decisions?${Uri(queryParameters: {
            'academic_year_id': academicYearId
          }).query}') as List)
          .map((item) => Map<String, dynamic>.from(item)));

  Future<Map<String, dynamic>> attendanceStatistics(String classId,
      {String? periodId, int? month}) async {
    final query = <String, String>{
      'class_id': classId,
      if (periodId != null && periodId.isNotEmpty) 'period_id': periodId,
      if (month != null) 'month': '$month',
    };
    return Map<String, dynamic>.from(await _api.get(
        '/api/v1/school/attendance/statistics?${Uri(queryParameters: query).query}'));
  }

  Future<Map<String, dynamic>> studentResults(
          String studentId, String academicYearId) async =>
      Map<String, dynamic>.from(await _api.get(
          '/api/v1/school/students/$studentId/results?${Uri(queryParameters: {
            'academic_year_id': academicYearId
          }).query}'));

  Future<Map<String, dynamic>> myStudentResults() async =>
      Map<String, dynamic>.from(await _api.get('/api/v1/school/my-results'));

  Future<Map<String, dynamic>> documentOverview(
          {String? academicYearId}) async =>
      Map<String, dynamic>.from(await _api
          .get('/api/v1/school/documents/overview?${Uri(queryParameters: {
            if (academicYearId != null && academicYearId.isNotEmpty)
              'academic_year_id': academicYearId,
          }).query}'));

  Future<Map<String, dynamic>> documentHistoryPage(
          Map<String, String> query) async =>
      Map<String, dynamic>.from(await _api.get(
          '/api/v1/school/documents/history?${Uri(queryParameters: query).query}'));

  Future<List<Map<String, dynamic>>> myChildrenForResults() async =>
      List<Map<String, dynamic>>.from(
          (await _api.get('/api/v1/school/my-children') as List)
              .map((item) => Map<String, dynamic>.from(item as Map)));

  Future<Map<String, dynamic>> myStudentTracking(String academicYearId) async =>
      Map<String, dynamic>.from(await _api.get(
          '/api/v1/school/my-tracking?${Uri(queryParameters: {
            'academic_year_id': academicYearId
          }).query}'));

  Future<Map<String, dynamic>> myChildTracking(
          String studentId, String academicYearId) async =>
      Map<String, dynamic>.from(await _api.get(
          '/api/v1/school/my-children/$studentId/tracking?${Uri(queryParameters: {
            'academic_year_id': academicYearId
          }).query}'));

  Future<Map<String, dynamic>> schoolOrganizationSummary(
      {String? academicYearId}) async {
    final suffix = academicYearId == null || academicYearId.isEmpty
        ? ''
        : '?${Uri(queryParameters: {
                'academic_year_id': academicYearId
              }).query}';
    return Map<String, dynamic>.from(
        await _api.get('/api/v1/school/organization-summary$suffix'));
  }

  Future<Map<String, dynamic>> statistics(
      {String? schoolId,
      String? academicYearId,
      String? cycle,
      String? levelId,
      String? classId,
      String? periodId,
      String? subjectId}) async {
    final query = <String, String>{
      if (schoolId != null) 'school_id': schoolId,
      if (academicYearId != null) 'academic_year_id': academicYearId,
      if (cycle != null) 'cycle': cycle,
      if (levelId != null) 'level_id': levelId,
      if (classId != null) 'class_id': classId,
      if (periodId != null) 'period_id': periodId,
      if (subjectId != null) 'subject_id': subjectId,
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return Map<String, dynamic>.from(
        await _api.get('/api/v1/statistics$suffix'));
  }

  Future<Map<String, dynamic>> reactToAnnouncement(
          String id, String reaction) async =>
      Map<String, dynamic>.from(await _api
          .post('/api/v1/announcements/$id/reactions', {'reaction': reaction}));

  Future<Map<String, dynamic>> createFinanceFee(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/finance/fees', payload));

  Future<Map<String, dynamic>> createFinancePayment(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/finance/payments', payload));

  Future<Map<String, dynamic>> financeSummary(
          {String? schoolId, String? academicYearId}) async =>
      Map<String, dynamic>.from(await _api
          .get('/api/v1/school/finance/summary?${Uri(queryParameters: {
            if (schoolId != null) 'school_id': schoolId,
            if (academicYearId != null) 'academic_year_id': academicYearId,
          }).query}'));

  Future<Map<String, dynamic>> cancelFinancePaymentRemote(
          String paymentId, String reason, {String? schoolId}) async =>
      Map<String, dynamic>.from(await _api.post(
          '/api/v1/school/finance/payments/$paymentId/cancel${schoolId == null ? '' : '?${Uri(queryParameters: {
                  'school_id': schoolId
                }).query}'}',
          {'reason': reason}));

  Future<Map<String, dynamic>> financeStudentByMatricule(
          String matricule) async =>
      Map<String, dynamic>.from(await _api.get(
          '/api/v1/school/finance/students/by-matricule/${Uri.encodeComponent(matricule)}'));

  Future<Map<String, dynamic>> createSchoolDocument(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/documents', payload));

  Future<void> create(String kind, Map<String, dynamic> payload) async {
    try {
      await _api.post('/api/v1/$kind', {'payload': payload});
    } on ApiException catch (error) {
      if (error.statusCode != 409) rethrow;
      await update(kind, payload['id'].toString(), payload);
    }
  }

  Future<void> update(String kind, String id, Map<String, dynamic> payload) =>
      _api.put('/api/v1/$kind/$id', {'payload': payload});
  Future<void> delete(String kind, String id) =>
      _api.delete('/api/v1/$kind/$id');
  Future<Map<String, dynamic>> sendExternalNotification(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
          await _api.post('/api/v1/school/communications/send', payload));

  Future<Map<String, dynamic>> broadcastTeachers(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _api.post(
          '/api/v1/school/communications/teachers/broadcast', payload));

  Future<Map<String, dynamic>> generateDocumentReport(
          Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _api.post(
          '/api/v1/school/documents/reports/generate', payload));
}
