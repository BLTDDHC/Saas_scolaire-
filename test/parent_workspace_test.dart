import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/navigation/nav_items.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parent loads only linked school context and authorized navigation',
      () async {
    SharedPreferences.setMockInitialValues({});
    final user = <String, dynamic>{
      'id': 'parent-user-1',
      'name': 'Parent Test',
      'email': 'parent@example.invalid',
      'role': 'parent',
      'roleName': 'parent',
      'schoolId': 'school-1',
      'status': 'active',
      'mustChangePassword': false,
    };
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return http.Response(
            jsonEncode({
              'accessToken': 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.signature',
              'user': user,
            }),
            200);
      }
      if (request.url.path == '/api/v1/bootstrap') {
        return http.Response(jsonEncode(<String, dynamic>{}), 200);
      }
      if (request.url.path == '/api/v1/school/parent/workspace') {
        return http.Response(
            jsonEncode({
              'establishment': {
                'id': 'school-1',
                'name': 'École Parent',
                'type': 'Établissement scolaire',
                'institutionType': 'school',
                'status': 'active',
                'enabledModules': [
                  'students',
                  'grades',
                  'schedule',
                  'finance',
                  'messages'
                ],
              },
              'guardian': {
                'id': 'guardian-1',
                'schoolId': 'school-1',
                'firstName': 'Parent',
                'lastName': 'Test',
                'status': 'active',
              },
              'academicYears': [
                {
                  'id': 'year-1',
                  'schoolId': 'school-1',
                  'name': '2026-2027',
                  'start': '2026-09-01',
                  'end': '2027-07-31',
                  'status': 'active',
                  'isActive': true,
                }
              ],
              'cycles': [
                {
                  'id': 'cycle-1',
                  'schoolId': 'school-1',
                  'code': 'COLLEGE',
                  'name': 'Collège',
                  'status': 'active',
                }
              ],
              'schoolLevels': [
                {
                  'id': 'level-1',
                  'schoolId': 'school-1',
                  'cycleId': 'cycle-1',
                  'code': '3E',
                  'name': '3e',
                  'status': 'active',
                }
              ],
              'classes': [
                {
                  'id': 'class-1',
                  'schoolId': 'school-1',
                  'name': '3e A',
                  'academicYearId': 'year-1',
                  'cycleId': 'cycle-1',
                  'levelId': 'level-1',
                  'status': 'active',
                }
              ],
              'students': [
                {
                  'id': 'student-linked',
                  'schoolId': 'school-1',
                  'firstName': 'Élève',
                  'lastName': 'Lié',
                  'classId': 'class-1',
                  'class': '3e A',
                  'academicYearId': 'year-1',
                  'status': 'active',
                  'guardians': [
                    {'id': 'guardian-1', 'isPrimary': true}
                  ],
                }
              ],
              'registrations': [
                {
                  'id': 'registration-1',
                  'studentId': 'student-linked',
                  'schoolId': 'school-1',
                  'academicYearId': 'year-1',
                  'classId': 'class-1',
                  'className': '3e A',
                  'status': 'active',
                }
              ],
            }),
            200);
      }
      if (request.url.path == '/api/v1/school/schedule') {
        expect(request.url.queryParameters['academic_year_id'], 'year-1');
        expect(request.url.queryParameters['class_id'], 'class-1');
        return http.Response(
            jsonEncode([
              {
                'id': 'schedule-1',
                'classId': 'class-1',
                'academicYearId': 'year-1',
                'status': 'active',
              }
            ]),
            200);
      }
      return http.Response(jsonEncode({'detail': 'Not Found'}), 404);
    });
    final store = StoreService(api: ApiClient(client: client));
    await store.init();
    expect(await store.login('parent@example.invalid', 'Temporary!9'), isTrue);

    expect(store.currentUser?.role, UserRole.parent);
    expect(store.getStudents().map((item) => item.id), ['student-linked']);
    expect(store.getClasses().map((item) => item.id), ['class-1']);
    expect(store.getSelectedAcademicYearId(), 'year-1');
    expect(
        await store.scheduleRemote('year-1', classId: 'class-1'), hasLength(1));
    final dashboardChildren = await store.parentDashboardChildrenRemote();
    expect(dashboardChildren.single['fullName'], 'Lié Élève');
    expect((dashboardChildren.single['years'] as List).single['className'],
        '3e A');

    final navigation = NavItems.getNavItemsForRole(UserRole.parent)
        .map((item) => item.id)
        .toSet();
    expect(navigation,
        containsAll({'dashboard', 'tracking', 'grades', 'schedule', 'finance'}));
    expect(navigation, isNot(contains('messages')));
    expect(navigation, isNot(contains('attendance')));
    expect(navigation, isNot(contains('behavior')));
    expect(navigation, isNot(contains('documents')));
  });
}
