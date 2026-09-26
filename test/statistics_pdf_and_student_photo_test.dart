import 'dart:convert';

import 'package:edupro_flutter_web/data/datasources/api_client.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/documents/document_report_pdf.dart';
import 'package:edupro_flutter_web/features/school/students/student_photo_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const transparentPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Wl8sAAAAASUVORK5CYII=';

  test('le rapport PDF conserve exactement l instantané affiché et son périmètre',
      () {
    final statistics = <String, dynamic>{
      'officialStudentCount': 18,
      'overallAverage': 13.25,
      'successRate': 77.78,
      'failureRate': 22.22,
    };
    final report = statisticsPdfReport(
      statistics: statistics,
      schoolName: 'Établissement test',
      academicYear: '2026-2027',
      cycleName: 'Collège',
      levelName: '3e',
      className: '3e A',
      periodName: 'Trimestre 2',
      subjectName: 'Mathématiques',
    );

    expect(identical(report['statisticsData'], statistics), isTrue);
    expect(report['className'], '3e A');
    expect(report['periodName'], 'Trimestre 2');
    expect(report['subjectName'], 'Mathématiques');
  });

  test('le PDF statistiques reprend les KPI, graphes et tableaux filtrés',
      () async {
    final pdf = await buildSchoolReportPdf({
      'title': 'Statistiques scolaires',
      'schoolName': 'Établissement test',
      'academicYear': '2026-2027',
      'cycleName': 'Lycée',
      'levelName': 'Terminale',
      'className': 'Terminale C1',
      'periodName': 'Trimestre 1',
      'subjectName': 'Mathématiques',
      'columns': const [],
      'rows': const [],
      'statisticsData': {
        'officialStudentCount': 2,
        'overallAverage': 12,
        'successRate': 50,
        'failureRate': 50,
        'attendanceRate': 75,
        'classCount': 1,
        'distribution': {'Bien': 1, 'Insuffisant': 1},
        'evolution': [
          {'period': 'T1', 'average20': 12}
        ],
        'byClass': [
          {
            'className': 'Terminale C1',
            'studentCount': 2,
            'average20': 12,
            'successRate': 50,
          }
        ],
        'bySubject': [
          {
            'subject': 'Mathématiques',
            'studentCount': 2,
            'average20': 12,
            'successRate': 50,
          }
        ],
        'top10': [
          {
            'name': 'Élève test',
            'className': 'Terminale C1',
            'average20': 16,
            'mention': 'Très bien',
          }
        ],
      },
    });
    final bytes = await pdf.save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  testWidgets('la photo privée chargée par API remplace les initiales',
      (tester) async {
    var photoRequests = 0;
    final api = ApiClient(client: MockClient((request) async {
      if (request.url.path == '/api/v1/school/students/student-1/photo') {
        photoRequests++;
        return http.Response.bytes(base64Decode(transparentPng), 200,
            headers: {'content-type': 'image/png'});
      }
      return http.Response('{}', 404,
          headers: {'content-type': 'application/json'});
    }));
    final store = StoreService(api: api);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(
          home: Scaffold(
            body: StudentPhotoAvatar(
              studentId: 'student-1',
              initials: 'ET',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isA<MemoryImage>());
    expect(photoRequests, 1);
  });

  testWidgets(
      'un import photo en masse rafraîchit immédiatement un avatar déjà affiché',
      (tester) async {
    var imported = false;
    var photoRequests = 0;
    final api = ApiClient(client: MockClient((request) async {
      if (request.url.path == '/api/v1/school/students/student-1/photo') {
        photoRequests++;
        if (!imported) {
          return http.Response('{}', 404,
              headers: {'content-type': 'application/json'});
        }
        return http.Response.bytes(base64Decode(transparentPng), 200,
            headers: {'content-type': 'image/png'});
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/school/students/photos/import') {
        imported = true;
        return http.Response(
          jsonEncode({
            'processed': 1,
            'items': [
              {
                'name': '1.png',
                'status': 'associated',
                'studentId': 'student-1',
                'studentName': 'ÉLÈVE Test',
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404,
          headers: {'content-type': 'application/json'});
    }));
    final store = StoreService(api: api);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(
          home: Scaffold(
            body: StudentPhotoAvatar(
              studentId: 'student-1',
              initials: 'ET',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isNull);
    expect(photoRequests, 1);

    await store.importStudentPhotosRemote(
      academicYearId: 'year-1',
      cycleId: 'cycle-1',
      files: const [
        {
          'name': '1.png',
          'mimeType': 'image/png',
          'contentBase64': transparentPng,
        }
      ],
    );
    await tester.pumpAndSettle();

    avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isA<MemoryImage>());
    expect(photoRequests, 2);
  });

}
