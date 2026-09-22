import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/datasources/seed_data.dart';
import 'package:edupro_flutter_web/data/models/class_model.dart';
import 'package:edupro_flutter_web/data/models/education/school_cycle_model.dart';
import 'package:edupro_flutter_web/data/models/education/school_level_model.dart';
import 'package:edupro_flutter_web/data/repositories/school_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('le catalogue primaire suit le mapping CP1 a CM2 definitif', () {
    final primaryLevels = SeedData.schoolLevels
        .where((level) => level.cycle == 'Primaire')
        .map((level) => level.name)
        .toList();

    expect(primaryLevels, ['CP1', 'CP2', 'CE1', 'CE2', 'CM1', 'CM2']);
    expect(primaryLevels, isNot(contains('CP')));
  });

  test('cycle, niveau et classe conservent les références structurées', () {
    final cycle = SchoolCycleModel.fromJson(const {
      'id': 'cycle-1',
      'schoolId': 'school-a',
      'code': 'PRIMAIRE',
      'name': 'Primaire',
      'status': 'active',
      'sortOrder': 20,
    });
    final level = SchoolLevelModel.fromJson(const {
      'id': 'level-1',
      'schoolId': 'school-a',
      'cycleId': 'cycle-1',
      'cycle': 'Primaire',
      'code': 'CP',
      'name': 'Cours préparatoire',
      'status': 'active',
      'sortOrder': 5,
    });
    final schoolClass = ClassModel.fromJson(const {
      'id': 'class-1',
      'name': 'CP A',
      'schoolId': 'school-a',
      'cycle': 'Primaire',
      'cycleId': 'cycle-1',
      'level': 'Cours préparatoire',
      'levelId': 'legacy-level',
      'structuredLevelId': 'level-1',
      'academicYearId': 'year-1',
    });

    expect(cycle.isActive, isTrue);
    expect(cycle.toJson()['code'], 'PRIMAIRE');
    expect(level.cycleId, cycle.id);
    expect(level.toJson()['code'], 'CP');
    expect(schoolClass.cycleId, cycle.id);
    expect(schoolClass.levelId, 'legacy-level');
    expect(schoolClass.structuredLevelId, level.id);
    expect(schoolClass.toJson()['academicYearId'], 'year-1');
  });

  test('le modèle niveau reste compatible avec les anciennes données', () {
    final level = SchoolLevelModel.fromJson(const {
      'id': 'SL_L_TER',
      'name': 'Terminale',
      'cycle': 'Lycée',
      'schoolId': '',
    });

    expect(level.cycleId, isEmpty);
    expect(level.code, isEmpty);
    expect(level.status, 'active');
  });

  test('repository utilise les routes multi-cycles réelles', () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}?${request.url.query}');
      if (request.url.path.endsWith('/catalog')) {
        return http.Response(
            jsonEncode([
              {'code': 'PRIMAIRE', 'name': 'Primaire', 'sortOrder': 20}
            ]),
            200);
      }
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/school/cycles') {
        return http.Response(
            jsonEncode([
              {
                'id': 'cycle-1',
                'schoolId': 'school-a',
                'code': 'PRIMAIRE',
                'name': 'Primaire'
              }
            ]),
            200);
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/school/cycles') {
        expect(jsonDecode(request.body)['code'], 'PRIMAIRE');
        return http.Response(
            jsonEncode({
              'id': 'cycle-1',
              'schoolId': 'school-a',
              'code': 'PRIMAIRE',
              'name': 'Primaire'
            }),
            201);
      }
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/school/cycles/cycle-1/levels') {
        return http.Response(
            jsonEncode([
              {
                'id': 'level-1',
                'schoolId': 'school-a',
                'cycleId': 'cycle-1',
                'cycle': 'Primaire',
                'code': 'CP',
                'name': 'Cours préparatoire'
              }
            ]),
            200);
      }
      return http.Response(jsonEncode({'detail': 'unexpected'}), 500);
    });
    final repository = SchoolRepository(ApiClient(client: client));

    expect((await repository.schoolCycleCatalog()).single['code'], 'PRIMAIRE');
    expect((await repository.schoolCycles(schoolId: 'school-a')).single['id'],
        'cycle-1');
    expect((await repository.createSchoolCycle({'code': 'PRIMAIRE'}))['id'],
        'cycle-1');
    expect((await repository.schoolLevels('cycle-1')).single['id'], 'level-1');
    expect(calls, contains('GET /api/v1/school/cycles?school_id=school-a'));
  });
}
