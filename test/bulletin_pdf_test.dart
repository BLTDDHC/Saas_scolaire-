import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:edupro_flutter_web/data/services/result_service.dart';
import 'package:edupro_flutter_web/features/school/documents/pdf_helpers.dart';
import 'support/legacy_store_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bulletin PDF generation', () {
    test(
        'maternelle and primaire use the shared PDF pipeline and save real files',
        () async {
      Map<String, dynamic> fixture(String cycle, String level, String name) => {
            'school': {'name': 'École Les Palmiers', 'city': 'Pointe-Noire'},
            'student': {
              'lastName': name,
              'firstName': 'Grâce',
              'matricule': 'ELP-001',
              'sex': 'F'
            },
            'class': {'name': '$level A', 'cycle': cycle, 'level': level},
            'cycle': cycle,
            'level': level,
            'academicYearId': '2027-2028',
            'periodId': '1er trimestre',
            'generalAverage': 8.0,
            'displayScale': 10,
            'ranking': {'rank': 2, 'effectif': 24},
            'behaviorAverage': 4.5,
            'behaviorObservations': ['Participation régulière'],
            'signatoryTitle': 'Le/La Directeur(trice)',
            'subjects': [
              {
                'subjectName': 'Langage et expression',
                'scale': 10,
                'subjectAverage': 8.5,
                'appreciation': 'Participation régulière',
                'evaluations': [
                  {
                    'evaluation': 'Devoir 1',
                    'type': 'devoir',
                    'value': 8,
                    'maxValue': 10
                  },
                  {
                    'evaluation': 'Composition',
                    'type': 'composition',
                    'value': 9,
                    'maxValue': 10
                  },
                ]
              },
              {
                'subjectName': 'Découverte du monde',
                'scale': 10,
                'subjectAverage': 7.5,
                'appreciation': 'Travail appliqué',
                'evaluations': [
                  {
                    'evaluation': 'Devoir 1',
                    'type': 'devoir',
                    'value': 7,
                    'maxValue': 10
                  },
                  {
                    'evaluation': 'Composition',
                    'type': 'composition',
                    'value': 8,
                    'maxValue': 10
                  },
                ]
              },
            ],
          };

      for (final config in [
        (
          'Maternelle',
          'Grande Section',
          'MBEMBA',
          'BULLETIN_MATERNELLE_QA_OUTPUT'
        ),
        ('Primaire', 'CM2', 'KIM', 'BULLETIN_PRIMAIRE_QA_OUTPUT'),
      ]) {
        final data = fixture(config.$1, config.$2, config.$3);
        final bytes = await (await buildTrimesterPdfFromData(data)).save();
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(2000));
        final output = Platform.environment[config.$4];
        if (output != null && output.isNotEmpty) {
          final file = File(output)..parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes, flush: true);
          expect(file.existsSync(), isTrue);
          expect(file.lengthSync(), bytes.length);
        }
      }
      expect(
          bulletinTrimesterMonths('T1'), ['Octobre', 'Novembre', 'Décembre']);
      expect(bulletinTrimesterMonths('T2'), ['Janvier', 'Février', 'Mars']);
      expect(bulletinTrimesterMonths('T3'), ['Avril', 'Mai', 'Juin']);
      expect(bulletinTrimesterMonths('T4'), isEmpty);
      final primaryTable = bulletinPrimaryCycleTable(
          (fixture('Primaire', 'CM2', 'KIM')['subjects'] as List),
          '1er trimestre');
      expect(primaryTable.headers, [
        'Disciplines',
        'Barème',
        'Octobre',
        'Novembre',
        'Composition du 1er trimestre',
        'Moyenne officielle /10',
        'Appréciation'
      ]);
      expect(primaryTable.rows.last.first, 'TOTAL');
      expect(primaryTable.rows.every((row) => row.length == 7), isTrue);
    });

    test('primary bulletin keeps monthly compositions distinct from trimester composition', () {
      final table = bulletinPrimaryCycleTable([
        {
          'subjectName': 'Mathématiques',
          'subjectAverage': 8,
          'evaluations': [
            {
              'evaluation': 'Composition du mois d’Octobre',
              'type': 'composition',
              'examCode': 'composition_octobre',
              'value': 7,
            },
            {
              'evaluation': 'Composition du mois de Novembre',
              'type': 'composition',
              'examCode': 'composition_novembre',
              'value': 8,
            },
            {
              'evaluation': 'Composition du 1er trimestre',
              'type': 'composition',
              'examCode': 'composition',
              'value': 9,
            },
          ],
        }
      ], '1er trimestre');
      expect(table.rows.first[2], '7');
      expect(table.rows.first[3], '8');
      expect(table.rows.first[4], '9');
    });

    test(
        'lycee official payload maps the required columns and saves a named PDF',
        () async {
      final subjects = <Map<String, dynamic>>[];
      const names = [
        'Français',
        'Philosophie',
        'Histoire-Géographie',
        'Anglais',
        'Mathématiques',
        'Physique-Chimie',
        'SVT',
        'EPS'
      ];
      const coefficients = [3, 3, 3, 3, 5, 5, 4, 2];
      for (var index = 0; index < names.length; index++) {
        final average = 16.73 + (index % 4) * .25;
        subjects.add({
          'subject': names[index],
          'average': average,
          'coefficient': coefficients[index],
          'point': average * coefficients[index],
          'observation': 'Donnée permanente de présentation',
          'grades': [
            {'evaluation': 'Devoir 1', 'type': 'devoir', 'value': average - .4},
            {'evaluation': 'Devoir 2', 'type': 'devoir', 'value': average + .4},
            {
              'evaluation': 'Composition',
              'type': 'composition',
              'value': average
            },
          ]
        });
      }
      final data = trimesterPdfDataFromOfficialSource(source: {
        'student': {'lastName': 'BOUAKO', 'firstName': 'Leader'},
        'class': {
          'name': 'Terminale C2',
          'cycle': 'Lycée',
          'level': 'Terminale',
          'series': 'Série C'
        },
        'academicYear': {'name': '2027-2028'}
      }, selected: {
        'period': '1er trimestre',
        'average': 17.06,
        'rank': 1,
        'effectif': 8,
        'calculatedAt': '2026-09-10T00:00:00Z',
        'behaviorAverage': 5.0,
        'behaviorObservations': ['Participation et attitude en classe'],
        'subjects': subjects
      }, school: {
        'name': 'Le cogito',
        'city': 'Brazzaville'
      }, studentId: 'student-id', yearId: 'year-id', periodId: 'period-id');
      expect(data['subjects'][0]['devoirs'], hasLength(2));
      expect(data['subjects'][0]['mc'], closeTo(16.73, 0.001));
      expect(data['subjects'][0]['composition'], isNotNull);
      expect(data['subjects'][0]['point'], isNotNull);
      expect(bulletinLyceeHeaders, [
        'Matière',
        'Devoir 1',
        'Devoir 2',
        'MC',
        'Composition',
        'Moyenne',
        'Coefficient',
        'Point',
        'Appréciation'
      ]);
      expect(bulletinLyceeHeaders, containsAll(['MC', 'Moyenne']));
      expect(data['school']['city'], 'Brazzaville');
      expect(data['signatoryTitle'], 'Le/La Proviseur(e)');
      expect(bulletinColorThemeKey(data), 'terminale');
      expect(bulletinColorThemeKey({'colorTheme': 'auto', 'level': 'Seconde'}),
          'seconde');
      expect(bulletinColorThemeKey({'colorTheme': 'auto', 'level': 'Première'}),
          'premiere');
      expect(
          bulletinColorThemeKey({'colorTheme': 'auto', 'level': 'Terminale'}),
          'terminale');
      expect(bulletinRankLabel(data['ranking']), '1er sur 8');
      expect(bulletinMentionLabel(data['mention'], data['generalAverage']),
          'Très bien');
      expect(
          bulletinDecisionLabel(data['decision'], data['generalAverage'], null),
          'Admis');
      expect(bulletinFileName(data),
          'Bulletin - 1er trimestre - BOUAKO Leader - Terminale C2 - 2027-2028.pdf');
      final bytes = await (await buildTrimesterPdfFromData(data)).save();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
      final output = Platform.environment['BULLETIN_QA_OUTPUT'];
      if (output != null && output.isNotEmpty) {
        final file = File(output);
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes, flush: true);
        expect(file.existsSync(), isTrue);
        expect(file.lengthSync(), bytes.length);
      }
    });
    test('production builder accepts the three official period payloads',
        () async {
      for (final period in ['1er trimestre', '2e trimestre', '3e trimestre']) {
        final pdf = await buildTrimesterPdfFromData({
          'school': {'name': 'Établissement de test'},
          'student': {'lastName': 'Test', 'firstName': 'Élève'},
          'class': {'name': 'CP1 A'},
          'academicYearId': '2026-2027',
          'periodId': period,
          'generalAverage': 14.25,
          'ranking': {'rank': 1, 'effectif': 2},
          'subjects': [
            {
              'subjectName': 'Français',
              'devoirs': <dynamic>[],
              'mc': null,
              'composition': null,
              'subjectAverage': 14.25,
              'coefficient': 1
            }
          ],
        });
        final bytes = await pdf.save();
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(500));
      }
    });

    test(
        'cycle-specific layouts omit college coefficients and keep primary scales',
        () async {
      final college = await buildTrimesterPdfFromData({
        'cycle': 'college',
        'periodId': 'T2',
        'academicYearId': '2026-2027',
        'school': {'name': 'Collège test'},
        'student': {'lastName': 'ÉPINI', 'firstName': 'Àngèle'},
        'class': {'name': '3e A'},
        'generalAverage': 12.5,
        'subjects': [
          {
            'subjectName': 'Français',
            'devoirs': [12],
            'mc': 12,
            'composition': 13,
            'subjectAverage': 12.5,
            'coefficient': 4
          }
        ],
      });
      final primary = await buildTrimesterPdfFromData({
        'cycle': 'primary',
        'periodId': 'T3',
        'academicYearId': '2026-2027',
        'school': {'name': 'École test'},
        'student': {'lastName': 'DUPONT', 'firstName': 'Élève'},
        'class': {'name': 'CM2'},
        'generalAverage': 15,
        'subjects': [
          {
            'subjectName': 'Mathématiques',
            'devoirs': [15],
            'mc': 15,
            'composition': null,
            'subjectAverage': 15,
            'coefficient': 1,
            'scale': 10
          }
        ],
      });
      expect((await college.save()).length, greaterThan(500));
      expect((await primary.save()).length, greaterThan(500));
    });

    test('official primary and maternelle averages are presented on ten',
        () async {
      for (final cycle in ['Primaire', 'Maternelle']) {
        final data = trimesterPdfDataFromOfficialSource(
          source: {
            'student': {'lastName': 'TEST', 'firstName': cycle, 'sex': 'F'},
            'class': {
              'name': cycle == 'Primaire' ? 'CM2 A' : 'Grande Section A',
              'cycle': cycle,
              'level': cycle == 'Primaire' ? 'CM2' : 'Grande Section',
            },
            'academicYear': {'name': '2027-2028'},
          },
          selected: {
            'period': '1er trimestre',
            'average': 7.5,
            'rank': 1,
            'effectif': 8,
            'subjects': [
              {
                'subject': 'Langage',
                'average': 8,
                'grades': [
                  {
                    'evaluation': 'Composition',
                    'type': 'composition',
                    'value': 8,
                    'maxValue': 10,
                  }
                ],
              }
            ],
          },
          school: {'name': 'École test', 'city': 'Dolisie'},
          studentId: 'student',
          yearId: 'year',
          periodId: 'period',
        );
        expect(data['displayScale'], 10);
        expect(data['generalAverage'], 7.5);
        expect(data['subjects'][0]['subjectAverage'], 8);
        expect(bulletinMentionLabel(null, data['generalAverage'], 10), 'Bien');
        expect(
            bulletinDecisionLabel(
                null, data['generalAverage'], data['student']['sex'], 10),
            'Admise');
        final bytes = await (await buildTrimesterPdfFromData(data)).save();
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      }
    });
    test('Trimester PDF can be generated from ResultService data', () async {
      final store = await createLegacyStore(withSeedData: true);

      final students = store.getStudents();
      expect(students.isNotEmpty, true);
      final student = students.first;
      final classId = student.classId ?? '';
      final periods = ['T1', 'T2', 'T3'];
      final periodId = periods.first;

      final rs = ResultService(store);
      final data = rs.generateTrimesterBulletin(classId, student.id, periodId);
      expect(data, isNotNull);

      final pdf = await buildTrimesterPdfFromData(data);
      final bytes = await pdf.save();
      expect(bytes.isNotEmpty, true);
      final header = String.fromCharCodes(bytes.take(5));
      expect(header, contains('%PDF'));
    });

    test('Annual PDF can be generated from stored AnnualBulletinModel',
        () async {
      final store = await createLegacyStore(withSeedData: true);
      await store.login('admin@edupro.com', legacyTestPassword);

      final students = store.getStudents();
      expect(students.isNotEmpty, true);
      final student = students.first;
      final classId = student.classId ?? '';

      final bulletinId = store.createAnnualBulletinRecord(
          classId: classId, studentId: student.id);
      expect(bulletinId.isNotEmpty, true);
      final bulletin = store.getAnnualBulletinById(bulletinId);
      expect(bulletin, isNotNull);

      final pdf = await buildAnnualPdfFromModel(bulletin!, store);
      final bytes = await pdf.save();
      expect(bytes.isNotEmpty, true);
      final header = String.fromCharCodes(bytes.take(5));
      expect(header, contains('%PDF'));
    });
  });
}
