import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/models/academic_year_model.dart';
import 'package:edupro_flutter_web/data/models/class_model.dart';
import 'package:edupro_flutter_web/data/repositories/school_repository.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('repository utilise exclusivement les routes relationnelles ADMIN 1',
      () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}?${request.url.query}');
      if (request.url.path == '/api/v1/school/academic-years' &&
          request.method == 'GET') {
        return _json([_year('year-1', true)], 200);
      }
      if (request.url.path == '/api/v1/school/academic-years' &&
          request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['name'], '2027-2028');
        return _json(_year('year-2', false), 201);
      }
      if (request.url.path.endsWith('/activate'))
        return _json(_year('year-2', true), 200);
      if (request.url.path == '/api/v1/school/classes' &&
          request.method == 'GET') {
        return _json([_schoolClass()], 200);
      }
      if (request.url.path == '/api/v1/school/classes' &&
          request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['cycleId'], 'cycle-1');
        expect(body['structuredLevelId'], 'level-1');
        return _json(_schoolClass(), 201);
      }
      if (request.url.path == '/api/v1/school/organization-summary') {
        return _json({
          'activeAcademicYear': _year('year-1', true),
          'selectedAcademicYear': _year('year-2', false),
          'activeCycleCount': 2,
          'classCount': 1,
        }, 200);
      }
      return _json({'detail': 'unexpected'}, 500);
    });
    final repository = SchoolRepository(ApiClient(client: client));

    expect((await repository.academicYears()).single['id'], 'year-1');
    await repository.createAcademicYear(
        {'name': '2027-2028', 'start': '2027-09-01', 'end': '2028-07-31'});
    await repository.activateAcademicYear('year-2');
    expect((await repository.schoolClasses()).single['cycleId'], 'cycle-1');
    await repository.createSchoolClass({
      'academicYearId': 'year-1',
      'cycleId': 'cycle-1',
      'structuredLevelId': 'level-1',
      'name': 'CP1 A',
    });
    expect((await repository.schoolOrganizationSummary())['classCount'], 1);
    expect(calls, isNot(contains('GET /api/v1/academic-years?')));
    expect(calls, isNot(contains('GET /api/v1/classes?')));
  });

  test('repository propage clairement un module ADMIN 1 désactivé', () async {
    final repository = SchoolRepository(ApiClient(
        client: MockClient((_) async => _json(
            {'detail': "Module 'classes' désactivé pour cet établissement"},
            403))));

    await expectLater(
        repository.schoolClasses(),
        throwsA(isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having(
                (error) => error.message, 'message', contains('désactivé'))));
  });

  test(
      'année sélectionnée reste distincte de l’année active et filtre strictement les classes',
      () async {
    SharedPreferences.setMockInitialValues({'edupro_initialized': 'true'});
    final store =
        StoreService(api: ApiClient(client: MockClient((request) async {
      if (request.method == 'POST' || request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(
            body['payload'] ?? body, request.method == 'POST' ? 201 : 200);
      }
      return _json([], 200);
    })));
    await store.init();
    store.addAcademicYear(AcademicYearModel(
        id: 'active',
        name: '2026-2027',
        start: '2026-09-01',
        end: '2027-07-31',
        schoolId: 'school-a',
        isActive: true));
    store.addAcademicYear(AcademicYearModel(
        id: 'history',
        name: '2025-2026',
        start: '2025-09-01',
        end: '2026-07-31',
        schoolId: 'school-a',
        isActive: false,
        status: 'inactive'));
    store.addClass(ClassModel(
        id: 'class-active',
        name: 'CP1 A',
        schoolId: 'school-a',
        academicYearId: 'active'));
    store.addClass(ClassModel(
        id: 'class-history',
        name: 'CP1 B',
        schoolId: 'school-a',
        academicYearId: 'history'));

    store.setSelectedAcademicYearId('history');
    expect(store.getActiveAcademicYear()?.id, 'active');
    expect(store.getSelectedAcademicYear()?.id, 'history');
    expect(store.getClassesByYear('history').map((item) => item.id),
        ['class-history']);
  });
}

Map<String, dynamic> _year(String id, bool active) => {
      'id': id,
      'name': active ? '2026-2027' : '2027-2028',
      'start': '2026-09-01',
      'end': '2027-07-31',
      'schoolId': 'school-a',
      'status': active ? 'active' : 'inactive',
      'isActive': active,
    };

Map<String, dynamic> _schoolClass() => {
      'id': 'class-1',
      'name': 'CP1 A',
      'schoolId': 'school-a',
      'academicYearId': 'year-1',
      'cycleId': 'cycle-1',
      'structuredLevelId': 'level-1',
      'levelId': 'level-1',
      'cycle': 'Primaire',
      'level': 'CP1',
    };

http.Response _json(Object? value, int status) => http.Response(
      jsonEncode(value),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
