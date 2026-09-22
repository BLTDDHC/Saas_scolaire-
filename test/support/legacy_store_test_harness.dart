import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const legacyTestPassword = 'test-only-password';

Future<StoreService> createLegacyStore({bool withSeedData = false}) async {
  SharedPreferences.setMockInitialValues({
    'edupro_initialized': 'true',
    if (!withSeedData) ...{
      'edupro_usersList': '[]',
      'edupro_establishments': '[]',
      'edupro_academicYears': '[]',
      'edupro_students': '[]',
    },
  });

  late final StoreService store;
  final client = MockClient((request) async {
    if (request.url.path == '/api/v1/auth/login') {
      final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      final email = body['identifier']?.toString().toLowerCase();
      final user = store
          .getUsers()
          .where((item) => item.email.toLowerCase() == email)
          .firstOrNull;
      if (user == null || body['password']?.toString().isEmpty != false) {
        return _jsonResponse({'detail': 'Identifiants invalides'}, 401);
      }
      return _jsonResponse({
        'accessToken': 'legacy-test-jwt-${user.id}',
        'user': user.toJson(),
      }, 200);
    }
    if (request.url.path == '/api/v1/bootstrap') {
      return _jsonResponse(_bootstrap(store), 200);
    }
    if (request.url.path == '/api/v1/school/academic-years') {
      return _jsonResponse(
          store.getAcademicYears().map((item) => item.toJson()).toList(), 200);
    }
    if (request.url.path == '/api/v1/school/classes') {
      return _jsonResponse(
          store.getClasses().map((item) => item.toJson()).toList(), 200);
    }
    if (request.url.path == '/api/v1/school/students') {
      return _jsonResponse(
          store.getStudents().map((item) => item.toJson()).toList(), 200);
    }
    if (request.url.path ==
        '/api/v1/school/students/re-enrollment-candidates') {
      final selectedClassId = request.url.queryParameters['class_id'];
      final students = store
          .getStudents()
          .where((item) =>
              selectedClassId == null || item.classId == selectedClassId)
          .map((item) => item.toJson())
          .toList();
      return _jsonResponse({
        'items': students,
        'total': students.length,
        'classes': store
            .getClasses()
            .map((item) => {'id': item.id, 'name': item.name})
            .toList(),
        'previousAcademicYear': {'name': 'Année précédente'},
      }, 200);
    }
    if (request.url.path == '/api/v1/auth/me') {
      final user = store.currentUser;
      return user == null
          ? _jsonResponse({'detail': 'Session invalide'}, 401)
          : _jsonResponse(user.toJson(), 200);
    }
    if (request.method == 'DELETE') return http.Response('', 204);
    if (request.method == 'POST' || request.method == 'PUT') {
      final decoded = request.body.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      return _jsonResponse(
        decoded['payload'] ?? decoded,
        request.method == 'POST' ? 201 : 200,
      );
    }
    return _jsonResponse(<Object?>[], 200);
  });
  store = StoreService(api: ApiClient(client: client));
  await store.init();
  return store;
}

http.Response _jsonResponse(Object? body, int statusCode) => http.Response(
      jsonEncode(body),
      statusCode,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _bootstrap(StoreService store) {
  final students = store.getStudents();
  final bulletins = students
      .expand((student) => store.getAnnualBulletinsForStudent(student.id))
      .toList();
  final decisions = students
      .expand((student) => store.getDecisionsForStudent(student.id))
      .toList();
  return {
    'establishments':
        store.getEstablishments().map((item) => item.toJson()).toList(),
    'subscriptions':
        store.getSubscriptions().map((item) => item.toJson()).toList(),
    'academic-years':
        store.getAcademicYears().map((item) => item.toJson()).toList(),
    'students': students.map((item) => item.toJson()).toList(),
    'teachers': store.getTeachers().map((item) => item.toJson()).toList(),
    'classes': store.getClasses().map((item) => item.toJson()).toList(),
    'cycles': store.getSchoolCycles().map((item) => item.toJson()).toList(),
    'school-levels':
        store.getSchoolLevels().map((item) => item.toJson()).toList(),
    'subjects': store.getSubjects().map((item) => item.toJson()).toList(),
    'evaluations': store.getEvaluations().map((item) => item.toJson()).toList(),
    'grades': store.getGrades().map((item) => item.toJson()).toList(),
    'behavior-assessments':
        store.getBehaviorAssessments().map((item) => item.toJson()).toList(),
    'affectations':
        store.getAffectations().map((item) => item.toJson()).toList(),
    'absences': store.getAbsences().map((item) => item.toJson()).toList(),
    'assignments': store.getAssignments().map((item) => item.toJson()).toList(),
    'finance-fees':
        store.getFinanceFees().map((item) => item.toJson()).toList(),
    'finance-registrations':
        store.getFinanceRegistrations().map((item) => item.toJson()).toList(),
    'finance-fee-assignments':
        store.getFinanceFeeAssignments().map((item) => item.toJson()).toList(),
    'finance-payments':
        store.getFinancePayments().map((item) => item.toJson()).toList(),
    'finance-receipts':
        store.getFinanceReceipts().map((item) => item.toJson()).toList(),
    'annual-bulletins': bulletins.map((item) => item.toJson()).toList(),
    'annual-decisions': decisions.map((item) => item.toJson()).toList(),
    'student-registrations': <Map<String, dynamic>>[],
    'documents': <Map<String, dynamic>>[],
    'announcements': <Map<String, dynamic>>[],
    're-enrollment-requests': <Map<String, dynamic>>[],
  };
}
