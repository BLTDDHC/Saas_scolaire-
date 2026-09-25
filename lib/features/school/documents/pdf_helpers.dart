import 'dart:convert';

import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../../data/models/annual_bulletin_model.dart';
import '../../../data/services/store_service.dart';
import '../../../core/utils/date_utils.dart';

const bulletinLyceeHeaders = [
  'Matière',
  'Devoir 1',
  'Devoir 2',
  'MC',
  'Composition',
  'Moyenne',
  'Coefficient',
  'Point',
  'Appréciation',
];

pw.Widget _studentPhotoOrPlaceholder(Map? student, {double fontSize = 7}) {
  final photo = student?['photo'] as Map?;
  final encoded = photo?['contentBase64']?.toString();
  if (encoded != null && encoded.isNotEmpty) {
    try {
      return pw.Image(pw.MemoryImage(base64Decode(encoded)), fit: pw.BoxFit.cover);
    } catch (_) {
      // Le bulletin reste générable si une ancienne photo est illisible.
    }
  }
  return pw.Text('PHOTO\nNON DISPONIBLE',
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(fontSize: fontSize, color: PdfColors.grey600));
}

Map<String, dynamic> trimesterPdfDataFromOfficialSource({
  required Map<String, dynamic> source,
  required Map<String, dynamic> selected,
  required Map<String, dynamic> school,
  required String studentId,
  required String yearId,
  required String periodId,
  String? signatoryTitle,
  String colorTheme = 'auto',
}) {
  final classData = Map<String, dynamic>.from(source['class'] as Map);
  final cycle = _cycleOf({
    'class': classData,
    'cycle': classData['cycle'] ?? classData['institutionType'],
  });
  final displayScale =
      cycle == 'maternelle' || cycle == 'primaire' || cycle == 'primary'
          ? 10.0
          : 20.0;
  double? displayAverage(Object? raw) {
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    if (value == null) return null;
    // The official engine already returns the cycle's general-average scale.
    // Individual evaluation grades retain their own original maxValue below.
    return value;
  }

  return <String, dynamic>{
    'school': school,
    'student': Map<String, dynamic>.from(source['student'] as Map),
    'class': classData,
    'cycle': classData['cycle'] ?? classData['institutionType'],
    'displayScale': displayScale,
    'level': classData['level'] ?? classData['grade'],
    'series': classData['series'],
    'academicYearId': (source['academicYear'] as Map?)?['name'] ?? yearId,
    'periodId': selected['period'] ?? periodId,
    'sourceStudentId': studentId,
    'sourceYearId': yearId,
    'sourcePeriodId': periodId,
    'calculatedAt': selected['calculatedAt'],
    'subjects': (selected['subjects'] as List? ?? const []).map((raw) {
      final item = Map<String, dynamic>.from(raw as Map);
      final grades = (item['grades'] as List? ?? const [])
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
      final devoirs = grades
          .where((grade) =>
              grade['type'] == 'devoir' ||
              '${grade['evaluation']}'.toLowerCase().contains('devoir'))
          .toList()
        ..sort((a, b) => '${a['evaluation']}'.compareTo('${b['evaluation']}'));
      final compositions = grades
          .where((grade) =>
              grade['type'] == 'composition' ||
              '${grade['evaluation']}'.toLowerCase().contains('composition'))
          .toList();
      final devoirValues = devoirs
          .map((grade) => grade['value'])
          .whereType<num>()
          .map((value) => value.toDouble())
          .toList();
      return <String, dynamic>{
        'subjectName': item['subject'] ?? '',
        'evaluations': grades,
        'devoirs': devoirValues,
        'mc': item['mc'] ??
            (devoirValues.isEmpty
                ? null
                : devoirValues.reduce((a, b) => a + b) / devoirValues.length),
        'composition': item['composition'] ??
            (compositions.isEmpty ? null : compositions.first['value']),
        'subjectAverage': displayAverage(item['average']),
        'coefficient': item['coefficient'],
        'point': item['point'],
        'scale': item['scale'] ??
            item['barème'] ??
            item['bareme'] ??
            (grades.isEmpty ? null : grades.first['maxValue']),
        'appreciation': item['observation'] ?? '',
        'observation': item['observation'] ?? '',
      };
    }).toList(),
    'generalAverage': displayAverage(selected['average']),
    'ranking': {'rank': selected['rank'], 'effectif': selected['effectif']},
    'behaviorAverage': selected['behaviorAverage'],
    'behaviorObservations': selected['behaviorObservations'] ?? const [],
    'mention': selected['mention'],
    'decision': (source['decision'] as Map?)?['decision'],
    'signatoryTitle':
        signatoryTitle ?? bulletinDefaultSignatoryTitle(classData),
    'colorTheme': colorTheme,
  };
}

/// Build a PDF document for a trimester bulletin from the trimmed data map
Future<pw.Document> buildTrimesterPdfFromData(Map<String, dynamic> data) async {
  final regular =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final medium =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Medium.ttf'));
  final theme = pw.ThemeData.withFont(base: regular, bold: medium);
  final pdf = pw.Document();
  final school = data['school'] as Map<String, dynamic>?;
  final student = data['student'] as Map<String, dynamic>?;
  final cls = data['class'] as Map<String, dynamic>?;
  final subjects = data['subjects'] as List<dynamic>;
  final ranking = data['ranking'] as Map<String, dynamic>?;
  final generalAverage = (data['generalAverage'] as num?)?.toDouble();
  final cycle = _cycleOf(data);
  final isCollege = cycle == 'college';
  final isLycee = cycle == 'lycee';
  final isMaternelle = cycle == 'maternelle' || cycle == 'preschool';
  final isPrimary = cycle == 'primary';
  final periodLabel = _periodLabel(data['periodId']);
  final accentColor = _bulletinAccentColor(data);

  if (isMaternelle) {
    _addMaternellePages(pdf, data, theme, periodLabel);
    return pdf;
  }
  if (isPrimary) {
    _addPrimaryPages(pdf, data, theme, periodLabel);
    return pdf;
  }

  final headers = <String>[];
  int maxDevoirs = 0;
  for (final s in subjects) {
    final devoirs = (s['devoirs'] as List<dynamic>?) ?? [];
    if (devoirs.length > maxDevoirs) maxDevoirs = devoirs.length;
  }
  if (isLycee) {
    headers.addAll(bulletinLyceeHeaders);
  } else {
    headers.add(isPrimary ? 'Disciplines' : 'Matière');
    if (isPrimary) headers.add('Barème');
    for (int i = 0; i < maxDevoirs; i++) headers.add('D${i + 1}');
    headers.addAll(isCollege
        ? ['MC', 'Composition', 'Moyenne', 'Appréciation']
        : ['MC', 'Composition', 'Moyenne', 'Coef', 'Points', 'Appréciation']);
  }

  final rows = <List<String>>[];
  for (final s in subjects) {
    final row = <String>[];
    row.add(s['subjectName'] ?? '');
    if (isLycee) {
      final devoirs = (s['devoirs'] as List<dynamic>?) ?? const [];
      row.add(_number(devoirs.isNotEmpty ? devoirs[0] : null));
      row.add(_number(devoirs.length > 1 ? devoirs[1] : null));
      row.add(_number(s['mc']));
      row.add(_number(s['composition']));
      row.add(_number(s['subjectAverage']));
      row.add(_number(s['coefficient']));
      row.add(_number(s['point']));
      row.add(bulletinMentionLabel(null, s['subjectAverage'], 20));
      rows.add(row);
      continue;
    }
    if (isPrimary) row.add(_scaleOf(s));
    final devoirs = (s['devoirs'] as List<dynamic>?) ?? [];
    for (int i = 0; i < maxDevoirs; i++) {
      if (i < devoirs.length) {
        final d = devoirs[i];
        row.add(d == null ? '-' : d.toString());
      } else {
        row.add('');
      }
    }
    row.add(s['mc'] != null ? s['mc'].toString() : '-');
    row.add(s['composition'] != null ? s['composition'].toString() : '-');
    row.add(s['subjectAverage'] != null ? s['subjectAverage'].toString() : '-');
    if (!isCollege) {
      row.add((s['coefficient'] ?? '').toString());
      final points = s['subjectAverage'] != null
          ? ((s['subjectAverage'] as num) * ((s['coefficient'] ?? 1) as num))
          : null;
      row.add(points != null ? points.toStringAsFixed(2) : '-');
    }
    row.add((s['appreciation'] ?? '').toString());
    rows.add(row);
  }
  if (isLycee) {
    rows.add([
      'TOTAL',
      _number(_sumLyceeColumn(subjects, (subject) {
        final devoirs = (subject['devoirs'] as List<dynamic>?) ?? const [];
        return devoirs.isNotEmpty ? devoirs[0] : null;
      })),
      _number(_sumLyceeColumn(subjects, (subject) {
        final devoirs = (subject['devoirs'] as List<dynamic>?) ?? const [];
        return devoirs.length > 1 ? devoirs[1] : null;
      })),
      _number(_sumLyceeColumn(subjects, (subject) => subject['composition'])),
      _number(_sumLyceeColumn(subjects, (subject) => subject['mc'])),
      _number(
          _sumLyceeColumn(subjects, (subject) => subject['subjectAverage'])),
      _number(_sumLyceeColumn(subjects, (subject) => subject['coefficient'])),
      _number(_sumLyceeColumn(subjects, (subject) => subject['point'])),
      '-',
    ]);
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      margin: const pw.EdgeInsets.all(32),
      footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12),
          child: pw.Text('Page ${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9))),
      build: (pw.Context context) => [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('MINISTÈRE DE L\'ENSEIGNEMENT',
                style:
                    pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.Text('PRÉSCOLAIRE, PRIMAIRE, SECONDAIRE',
                style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 4),
            pw.Text(school?['name'] ?? '',
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('RÉPUBLIQUE DU CONGO',
                style:
                    pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.Text('Unité * Travail * Progrès',
                style: const pw.TextStyle(fontSize: 8)),
          ]),
        ]),
        pw.SizedBox(height: 7),
        pw.Center(
            child: pw.Text('BULLETIN DE NOTES DU ${periodLabel.toUpperCase()}',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold))),
        pw.Divider(),
        pw.Text('Année scolaire: ${data['academicYearId'] ?? ''}',
            style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 8),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
              child: pw.Table.fromTextArray(
            headers: const ['IDENTITÉ DE L\'ÉLÈVE', 'VALEUR'],
            data: [
              ['Noms', '${student?['lastName'] ?? ''}'],
              ['Prénoms', '${student?['firstName'] ?? ''}'],
              [
                'Date de naissance',
                AppDateUtils.formatNumeric(student?['birthDate']?.toString(),
                    fallback: '-')
              ],
              ['Genre', '${student?['sex'] ?? '-'}'],
              ['Adresse', '${student?['address'] ?? '-'}'],
              ['Classe', '${cls?['name'] ?? ''}'],
              ['Série', (data['series'] ?? '-').toString()],
              ['Matricule', '${student?['matricule'] ?? '-'}'],
            ],
            headerDecoration: pw.BoxDecoration(color: accentColor),
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            columnWidths: {
              0: const pw.FixedColumnWidth(100),
              1: const pw.FlexColumnWidth()
            },
          )),
          pw.SizedBox(width: 8),
          pw.Container(
              width: 92,
              height: 143,
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey700, width: .7)),
              alignment: pw.Alignment.center,
              child: _studentPhotoOrPlaceholder(student)),
        ]),
        pw.SizedBox(height: 12),
        pw.Table.fromTextArray(
          headers: headers,
          data: rows,
          border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.7),
          headerDecoration: pw.BoxDecoration(color: accentColor),
          headerStyle:
              pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6.5),
          cellStyle: const pw.TextStyle(fontSize: 6.5),
          cellPadding:
              const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 6),
          cellAlignment: pw.Alignment.center,
          columnWidths: isLycee
              ? {
                  0: const pw.FlexColumnWidth(1.65),
                  1: const pw.FlexColumnWidth(0.65),
                  2: const pw.FlexColumnWidth(0.65),
                  3: const pw.FlexColumnWidth(0.75),
                  4: const pw.FlexColumnWidth(0.55),
                  5: const pw.FlexColumnWidth(0.65),
                  6: const pw.FlexColumnWidth(0.60),
                  7: const pw.FlexColumnWidth(0.70),
                  8: const pw.FlexColumnWidth(1.35),
                }
              : null,
        ),
        pw.SizedBox(height: 12),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
              child: pw.Table.fromTextArray(
            data: [
              ['Moyenne générale', _number(generalAverage)],
              ['Rang', bulletinRankLabel(ranking)],
              ['Comportement', _number(data['behaviorAverage'])],
              [
                'Mention',
                bulletinMentionLabel(
                    data['mention'], generalAverage, data['displayScale'])
              ],
              [
                'Décision',
                bulletinDecisionLabel(data['decision'], generalAverage,
                    student?['sex'], data['displayScale'])
              ],
            ],
            border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.7),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.all(4),
            oddRowDecoration: pw.BoxDecoration(color: accentColor),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.2),
              1: const pw.FlexColumnWidth(1.8)
            },
          )),
          pw.SizedBox(width: 18),
          pw.Container(
              width: 175,
              height: 78,
              alignment: pw.Alignment.topCenter,
              child: pw.Column(children: [
                pw.Text('Fait à ${school?['city'] ?? ''}',
                    style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(height: 5),
                pw.Text('${data['signatoryTitle'] ?? 'Le/La Responsable'}',
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.Spacer(),
                pw.Text('Cachet / signature',
                    style: const pw.TextStyle(
                        fontSize: 7, color: PdfColors.grey600)),
              ])),
        ]),
      ],
    ),
  );

  return pdf;
}

void _addMaternellePages(pw.Document pdf, Map<String, dynamic> data,
    pw.ThemeData theme, String periodLabel) {
  final accent = const PdfColor.fromInt(0xffffe3b5);
  final subjects = (data['subjects'] as List<dynamic>? ?? const []);
  pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      theme: theme,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => pw.Column(children: [
            _cycleHeader(
                data, 'CARNET DE SUIVI - MATERNELLE', periodLabel, accent),
            pw.SizedBox(height: 16),
            _studentIdentity(data, accent),
            pw.SizedBox(height: 16),
            _periodCard(periodLabel, accent),
            pw.Spacer(),
            pw.Text(
                'Ce document reprend uniquement les informations officielles disponibles dans le système.',
                textAlign: pw.TextAlign.center,
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            _pageFooter(context),
          ])));

  final table = bulletinPrimaryCycleTable(subjects, periodLabel);
  pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a5.landscape,
      theme: theme,
      margin: const pw.EdgeInsets.all(24),
      footer: _pageFooter,
      build: (context) => [
            _cycleHeader(data, 'DOMAINES D’APPRENTISSAGE', periodLabel, accent),
            pw.SizedBox(height: 12),
            pw.Table.fromTextArray(
              headers: table.headers,
              data: table.rows,
              border: pw.TableBorder.all(color: PdfColors.grey700, width: .7),
              headerDecoration: pw.BoxDecoration(color: accent),
              headerStyle:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
              cellStyle: const pw.TextStyle(fontSize: 7),
              cellPadding: const pw.EdgeInsets.all(4),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.5),
                1: pw.FlexColumnWidth(.6),
                2: pw.FlexColumnWidth(.8),
                3: pw.FlexColumnWidth(.8),
                4: pw.FlexColumnWidth(1.2),
                5: pw.FlexColumnWidth(1.0),
                6: pw.FlexColumnWidth(1.3),
              },
            ),
          ]));

  pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      theme: theme,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => pw.Column(children: [
            _cycleHeader(data, 'SYNTHÈSE DU TRIMESTRE', periodLabel, accent),
            pw.SizedBox(height: 14),
            _officialSynthesis(data, accent,
                showRanking: false,
                showAcademicResults: data['generalAverage'] != null),
            pw.SizedBox(height: 12),
            _behaviorObservations(data, accent),
            pw.Spacer(),
            _signatureZones(data),
            _pageFooter(context),
          ])));
}

void _addPrimaryPages(pw.Document pdf, Map<String, dynamic> data,
    pw.ThemeData theme, String periodLabel) {
  final accent = const PdfColor.fromInt(0xffdcefdc);
  final subjects = (data['subjects'] as List<dynamic>? ?? const []);
  pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      theme: theme,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => pw.Column(children: [
            _cycleHeader(
                data, 'BULLETIN SCOLAIRE - PRIMAIRE', periodLabel, accent),
            pw.SizedBox(height: 16),
            _studentIdentity(data, accent),
            pw.SizedBox(height: 16),
            _periodCard(periodLabel, accent),
            pw.Spacer(),
            _pageFooter(context),
          ])));

  final table = bulletinPrimaryCycleTable(subjects, periodLabel);
  pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a5.landscape,
      theme: theme,
      margin: const pw.EdgeInsets.all(24),
      footer: _pageFooter,
      build: (context) => [
            _cycleHeader(data, 'RÉSULTATS OFFICIELS', periodLabel, accent),
            pw.SizedBox(height: 14),
            pw.Table.fromTextArray(
              headers: table.headers,
              data: table.rows,
              border: pw.TableBorder.all(color: PdfColors.grey700, width: .6),
              headerDecoration: pw.BoxDecoration(color: accent),
              headerStyle:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6.5),
              cellStyle: const pw.TextStyle(fontSize: 6.5),
              cellPadding:
                  const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 5),
              cellAlignment: pw.Alignment.center,
              columnWidths: {
                0: const pw.FlexColumnWidth(1.6),
                1: const pw.FlexColumnWidth(.65),
                2: const pw.FlexColumnWidth(.75),
                3: const pw.FlexColumnWidth(.75),
                4: const pw.FlexColumnWidth(1.15),
                5: const pw.FlexColumnWidth(1.05),
                6: const pw.FlexColumnWidth(1.4),
              },
            ),
          ]));

  pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      theme: theme,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => pw.Column(children: [
            _cycleHeader(data, 'SYNTHÈSE DU TRIMESTRE', periodLabel, accent),
            pw.SizedBox(height: 14),
            _officialSynthesis(data, accent),
            pw.SizedBox(height: 12),
            _behaviorObservations(data, accent),
            pw.Spacer(),
            _signatureZones(data),
            _pageFooter(context),
          ])));
}

pw.Widget _cycleHeader(Map<String, dynamic> data, String title,
    String periodLabel, PdfColor accent) {
  final school = data['school'] as Map?;
  return pw.Column(children: [
    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('MINISTÈRE DE L’ENSEIGNEMENT',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        pw.Text('${school?['name'] ?? ''}',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text('RÉPUBLIQUE DU CONGO',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        pw.Text('Unité * Travail * Progrès',
            style: const pw.TextStyle(fontSize: 8)),
      ]),
    ]),
    pw.SizedBox(height: 14),
    pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        color: accent,
        child: pw.Column(children: [
          pw.Text(title,
              textAlign: pw.TextAlign.center,
              style:
                  pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          pw.Text(periodLabel.toUpperCase(),
              style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Année scolaire ${data['academicYearId'] ?? ''}',
              style: const pw.TextStyle(fontSize: 9)),
        ])),
  ]);
}

pw.Widget _studentIdentity(Map<String, dynamic> data, PdfColor accent) {
  final student = data['student'] as Map?;
  final cls = data['class'] as Map?;
  return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.Expanded(
        child: pw.Table.fromTextArray(
      headers: const ['IDENTIFICATION DE L’ÉLÈVE', 'INFORMATION'],
      data: [
        ['Nom', '${student?['lastName'] ?? ''}'],
        ['Prénom', '${student?['firstName'] ?? ''}'],
        [
          'Date de naissance',
          AppDateUtils.formatNumeric(student?['birthDate']?.toString(),
              fallback: '-')
        ],
        ['Genre', '${student?['sex'] ?? '-'}'],
        ['Matricule', '${student?['matricule'] ?? '-'}'],
        ['Classe', '${cls?['name'] ?? ''}'],
        ['Niveau', '${data['level'] ?? cls?['level'] ?? '-'}'],
      ],
      headerDecoration: pw.BoxDecoration(color: accent),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellPadding: const pw.EdgeInsets.all(5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.1),
        1: pw.FlexColumnWidth(2.4),
      },
    )),
    pw.SizedBox(width: 12),
    pw.Container(
        width: 105,
        height: 150,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey700, width: .7)),
        child: _studentPhotoOrPlaceholder(student, fontSize: 8)),
  ]);
}

pw.Widget _periodCard(String periodLabel, PdfColor accent) => pw.Container(
    width: double.infinity,
    decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey700, width: .7)),
    child: pw.Table.fromTextArray(
      data: [
        ['Période officielle', periodLabel],
        ['Mois', bulletinTrimesterMonths(periodLabel).join(' - ')],
      ],
      oddRowDecoration: pw.BoxDecoration(color: accent),
      cellStyle: const pw.TextStyle(fontSize: 10),
      cellPadding: const pw.EdgeInsets.all(8),
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(2.5),
      },
    ));

pw.Widget _officialSynthesis(Map<String, dynamic> data, PdfColor accent,
    {bool showRanking = true, bool showAcademicResults = true}) {
  final ranking = data['ranking'] as Map<String, dynamic>?;
  final inferredScale =
      {'maternelle', 'preschool', 'primary'}.contains(_cycleOf(data)) ? 10 : 20;
  final displayScale = data['displayScale'] ?? inferredScale;
  return pw.Table.fromTextArray(
    data: [
      if (showAcademicResults)
        [
          'Moyenne officielle /${_number(displayScale)}',
          _number(data['generalAverage'])
        ],
      if (showAcademicResults && showRanking)
        ['Rang officiel', bulletinRankLabel(ranking)],
      ['Comportement officiel', _number(data['behaviorAverage'])],
      if (showAcademicResults)
        [
          'Mention',
          bulletinMentionLabel(
              data['mention'], data['generalAverage'], displayScale)
        ],
      if (showAcademicResults)
        [
          'Décision',
          bulletinDecisionLabel(data['decision'], data['generalAverage'],
              (data['student'] as Map?)?['sex'], displayScale)
        ],
    ],
    border: pw.TableBorder.all(color: PdfColors.grey700, width: .7),
    oddRowDecoration: pw.BoxDecoration(color: accent),
    cellStyle: const pw.TextStyle(fontSize: 10),
    cellPadding: const pw.EdgeInsets.all(8),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.2),
      1: pw.FlexColumnWidth(2),
    },
  );
}

pw.Widget _behaviorObservations(Map<String, dynamic> data, PdfColor accent) {
  final observations = (data['behaviorObservations'] as List? ?? const [])
      .map((value) => value.toString().trim())
      .where((value) => value.isNotEmpty)
      .toList();
  return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey700, width: .7)),
      child:
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(
            width: double.infinity,
            color: accent,
            padding: const pw.EdgeInsets.all(8),
            child: pw.Text('OBSERVATIONS COMPORTEMENTALES ENREGISTRÉES',
                style:
                    pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
        pw.Padding(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Text(observations.isEmpty
                ? 'Aucune observation enregistrée.'
                : observations.join('\n'))),
      ]));
}

pw.Widget _signatureZones(Map<String, dynamic> data) {
  final school = data['school'] as Map?;
  return pw.Column(children: [
    pw.Text('Fait à ${school?['city'] ?? ''}',
        style: const pw.TextStyle(fontSize: 9)),
    pw.SizedBox(height: 12),
    pw.Row(children: [
      for (final title in [
        'L’enseignant(e)',
        'Le parent / responsable',
        '${data['signatoryTitle'] ?? 'Le/La Directeur(trice)'}'
      ])
        pw.Expanded(
            child: pw.Container(
                height: 92,
                margin: const pw.EdgeInsets.symmetric(horizontal: 4),
                padding: const pw.EdgeInsets.all(7),
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey700, width: .7)),
                child: pw.Column(children: [
                  pw.Text(title,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Spacer(),
                  pw.Text('Signature / cachet',
                      style: const pw.TextStyle(
                          fontSize: 7, color: PdfColors.grey600)),
                ])))
    ]),
  ]);
}

pw.Widget _pageFooter(pw.Context context) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14),
    child: pw.Text('Page ${context.pageNumber} / ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 8)));

({List<String> headers, List<List<String>> rows}) bulletinPrimaryCycleTable(
    List<dynamic> subjects, String periodLabel) {
  final months = bulletinTrimesterMonths(periodLabel);
  final displayedMonths =
      months.length == 3 ? months : const ['Mois 1', 'Mois 2', 'Composition'];
  final headers = <String>[
    'Disciplines',
    'Barème',
    displayedMonths[0],
    displayedMonths[1],
    'Composition du $periodLabel',
    'Moyenne officielle /10',
    'Appréciation',
  ];
  final rows = <List<String>>[];
  final totals = List<num>.filled(4, 0);
  final hasTotals = List<bool>.filled(4, false);

  for (final raw in subjects) {
    final subject = raw as Map<dynamic, dynamic>;
    var evaluations = (subject['evaluations'] as List<dynamic>? ?? const [])
        .map((item) => Map<dynamic, dynamic>.from(item as Map))
        .toList();
    if (evaluations.isEmpty) {
      evaluations = [
        for (final value in subject['devoirs'] as List<dynamic>? ?? const [])
          {'type': 'devoir', 'value': value},
        if (subject['composition'] != null)
          {'type': 'composition', 'value': subject['composition']},
      ];
    }
    final used = <int>{};
    Object? monthlyValue(int monthIndex) {
      final month = displayedMonths[monthIndex].toLowerCase();
      var index = -1;
      for (var candidate = 0; candidate < evaluations.length; candidate++) {
        if (!used.contains(candidate) &&
            '${evaluations[candidate]['evaluation'] ?? ''}'
                .toLowerCase()
                .contains(month)) {
          index = candidate;
          break;
        }
      }
      if (index < 0) {
        for (var candidate = 0; candidate < evaluations.length; candidate++) {
          final evaluation = evaluations[candidate];
          final label = '${evaluation['evaluation'] ?? ''}'.toLowerCase();
          if (!used.contains(candidate) &&
              evaluation['type'] != 'composition' &&
              !label.contains('composition')) {
            index = candidate;
            break;
          }
        }
      }
      if (index < 0) return null;
      used.add(index);
      return evaluations[index]['value'];
    }

    final first = monthlyValue(0);
    final second = monthlyValue(1);
    final compositionIndex = evaluations.indexWhere((evaluation) {
      final label = '${evaluation['evaluation'] ?? ''}'.toLowerCase();
      return evaluation['type'] == 'composition' ||
          label.contains('composition') ||
          label.contains(displayedMonths[2].toLowerCase());
    });
    final composition =
        compositionIndex < 0 ? null : evaluations[compositionIndex]['value'];
    final average = subject['subjectAverage'];
    final values = [first, second, composition, average];
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      final numeric = value is num ? value : num.tryParse('$value');
      if (numeric != null) {
        totals[index] += numeric;
        hasTotals[index] = true;
      }
    }
    rows.add([
      '${subject['subjectName'] ?? ''}',
      '/10',
      _number(first),
      _number(second),
      _number(composition),
      _number(average),
      _storedAppreciation(subject),
    ]);
  }
  if (rows.isEmpty) {
    rows.add(List<String>.generate(headers.length,
        (index) => index == 0 ? 'Aucun résultat officiel disponible' : '-'));
  } else {
    rows.add([
      'TOTAL',
      '-',
      for (var index = 0; index < totals.length; index++)
        hasTotals[index] ? _number(totals[index]) : '-',
      '-',
    ]);
  }
  return (headers: headers, rows: rows);
}

String _storedAppreciation(Map<dynamic, dynamic> subject) {
  final value =
      '${subject['appreciation'] ?? subject['observation'] ?? ''}'.trim();
  return value.isEmpty ? 'Non renseignée' : value;
}

List<String> bulletinTrimesterMonths(Object? period) {
  final label = _periodLabel(period);
  switch (label) {
    case '1er trimestre':
      return const ['Octobre', 'Novembre', 'Décembre'];
    case '2e trimestre':
      return const ['Janvier', 'Février', 'Mars'];
    case '3e trimestre':
      return const ['Avril', 'Mai', 'Juin'];
    default:
      return const [];
  }
}

String _number(Object? value) {
  if (value == null) return '-';
  if (value is num) {
    final fixed = value.toDouble().toStringAsFixed(2);
    return fixed.replaceFirst(RegExp(r'\.00$'), '');
  }
  return value.toString();
}

num? _sumLyceeColumn(
    List<dynamic> subjects, Object? Function(Map<dynamic, dynamic>) valueOf) {
  num total = 0;
  var hasValue = false;
  for (final raw in subjects) {
    final subject = raw as Map<dynamic, dynamic>;
    final value = valueOf(subject);
    if (value is num) {
      total += value;
      hasValue = true;
    } else if (value != null) {
      final parsed = num.tryParse('$value');
      if (parsed != null) {
        total += parsed;
        hasValue = true;
      }
    }
  }
  return hasValue ? total : null;
}

String bulletinDefaultSignatoryTitle(Map<String, dynamic> classData) {
  final cycle = '${classData['cycle'] ?? classData['institutionType'] ?? ''}'
      .toLowerCase();
  if (cycle.contains('lyc')) return 'Le/La Proviseur(e)';
  if (cycle.contains('coll')) return 'Le/La Principal(e)';
  return 'Le/La Directeur(trice)';
}

String bulletinColorThemeKey(Map<String, dynamic> data) {
  final selected = '${data['colorTheme'] ?? 'auto'}'.toLowerCase();
  if (selected != 'auto') return selected;
  final cls = data['class'] as Map?;
  final level =
      '${data['level'] ?? cls?['level'] ?? cls?['name'] ?? ''}'.toLowerCase();
  if (level.contains('seconde') ||
      RegExp(r'(^|\s)2nde?(\s|$)').hasMatch(level)) {
    return 'seconde';
  }
  if (level.contains('première') ||
      level.contains('premiere') ||
      RegExp(r'(^|\s)1re?(\s|$)').hasMatch(level)) {
    return 'premiere';
  }
  if (level.contains('terminale') ||
      RegExp(r'(^|\s)t(le)?(\s|$)').hasMatch(level)) {
    return 'terminale';
  }
  return 'neutre';
}

PdfColor _bulletinAccentColor(Map<String, dynamic> data) {
  switch (bulletinColorThemeKey(data)) {
    case 'seconde':
    case 'bleu':
      return const PdfColor.fromInt(0xffdceaf7);
    case 'premiere':
    case 'vert':
      return const PdfColor.fromInt(0xffdcefdc);
    case 'terminale':
    case 'bordeaux':
      return const PdfColor.fromInt(0xffead9e5);
    default:
      return const PdfColor.fromInt(0xffe8e8e8);
  }
}

String bulletinRankLabel(Map<String, dynamic>? ranking) {
  if (ranking == null) return '-';
  final rank = int.tryParse('${ranking['rank'] ?? ''}');
  final effectif = int.tryParse('${ranking['effectif'] ?? ''}');
  if (rank == null || effectif == null) return '-';
  return '${rank == 1 ? '1er' : '${rank}e'} sur $effectif';
}

String bulletinMentionLabel(Object? raw, Object? average,
    [Object? scale = 20]) {
  final stored = (raw ?? '').toString().trim();
  if (stored.isNotEmpty) return stored;
  final value =
      average is num ? average.toDouble() : double.tryParse('$average');
  if (value == null) return '-';
  final maximum = scale is num ? scale.toDouble() : double.tryParse('$scale');
  final ratio = value / ((maximum == null || maximum <= 0) ? 20 : maximum);
  if (ratio >= .8) return 'Très bien';
  if (ratio >= .7) return 'Bien';
  if (ratio >= .6) return 'Assez bien';
  if (ratio >= .5) return 'Passable';
  return 'Insuffisant';
}

String bulletinDecisionLabel(Object? raw, Object? average, Object? sex,
    [Object? scale = 20]) {
  final normalized = (raw ?? '').toString().trim().toLowerCase();
  final feminine = {'f', 'female', 'féminin', 'feminin'}
      .contains((sex ?? '').toString().trim().toLowerCase());
  final value =
      average is num ? average.toDouble() : double.tryParse('$average');
  final maximum = scale is num ? scale.toDouble() : double.tryParse('$scale');
  final threshold = ((maximum == null || maximum <= 0) ? 20 : maximum) / 2;
  final admitted = normalized == 'admitted' ||
      normalized == 'admis' ||
      normalized == 'admise' ||
      (normalized.isEmpty && value != null && value >= threshold);
  final failed = normalized == 'repeat' ||
      normalized == 'recalé' ||
      normalized == 'recale' ||
      normalized == 'recalée' ||
      normalized == 'recalee' ||
      (normalized.isEmpty && value != null && value < threshold);
  if (admitted) return feminine ? 'Admise' : 'Admis';
  if (failed) return feminine ? 'Recalée' : 'Recalé';
  if (normalized == 'excluded' ||
      normalized == 'exclu' ||
      normalized == 'exclue') {
    return feminine ? 'Exclue' : 'Exclu';
  }
  return normalized.isEmpty ? '-' : (raw ?? '').toString();
}

String bulletinFileName(Map<String, dynamic> data) {
  final student = data['student'] as Map<String, dynamic>? ?? const {};
  final cls = data['class'] as Map<String, dynamic>? ?? const {};
  final raw = 'Bulletin - ${_periodLabel(data['periodId'])} - '
      '${student['lastName'] ?? ''} ${student['firstName'] ?? ''} - '
      '${cls['name'] ?? ''} - ${data['academicYearId'] ?? ''}.pdf';
  return raw
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _cycleOf(Map<String, dynamic> data) {
  final raw = (data['cycle'] ??
          (data['class'] as Map?)?['cycle'] ??
          (data['class'] as Map?)?['institutionType'] ??
          (data['class'] as Map?)?['level'] ??
          (data['class'] as Map?)?['name'] ??
          '')
      .toString()
      .toLowerCase();
  if (raw.contains('lyc') || raw.contains('high')) return 'lycee';
  if (raw.contains('coll')) return 'college';
  if (raw.contains('mater') || raw.contains('preschool')) return 'maternelle';
  if (raw.contains('prim') || raw.contains('element')) return 'primary';
  if (RegExp(r'(^|\s)(cp|ce1|ce2|cm1|cm2|sil|sg|ms|gs)(\s|$)').hasMatch(raw))
    return 'primary';
  return 'lycee';
}

String _periodLabel(Object? value) {
  final raw = value?.toString().toLowerCase() ?? '';
  if (raw == 't1' || raw.contains('1er') || raw.contains('trimestre 1'))
    return '1er trimestre';
  if (raw == 't2' || raw.contains('2e') || raw.contains('trimestre 2'))
    return '2e trimestre';
  if (raw == 't3' || raw.contains('3e') || raw.contains('trimestre 3'))
    return '3e trimestre';
  return value?.toString() ?? '';
}

String _scaleOf(dynamic subject) {
  final scale = subject is Map
      ? (subject['scale'] ?? subject['barème'] ?? subject['bareme'])
      : null;
  return scale == null
      ? '/20'
      : (scale.toString().startsWith('/') ? scale.toString() : '/$scale');
}

/// Build a PDF document for an annual bulletin using the stored model and store to resolve names
Future<pw.Document> buildAnnualPdfFromModel(
    AnnualBulletinModel b, StoreService store) async {
  final regular =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final medium =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Medium.ttf'));
  final theme = pw.ThemeData.withFont(base: regular, bold: medium);
  final pdf = pw.Document();
  final school = store.getEstablishmentById(b.establishmentId);
  final students =
      store.getStudents().where((s) => s.id == b.studentId).toList();
  final student = students.isNotEmpty ? students.first : null;

  final headers = ['Matière', 'Coef', 'T1', 'T2', 'T3', 'Moy. Année'];
  final rows = <List<String>>[];
  for (final s in b.subjectResults) {
    rows.add([
      s.subjectName,
      s.coefficient.toString(),
      s.t1 != null ? s.t1!.toStringAsFixed(2) : '-',
      s.t2 != null ? s.t2!.toStringAsFixed(2) : '-',
      s.t3 != null ? s.t3!.toStringAsFixed(2) : '-',
      s.annualAverage != null ? s.annualAverage!.toStringAsFixed(2) : '-',
    ]);
  }

  // decision only displayed if validated/locked
  String displayedDecision = 'À DÉCIDER';
  final decs = store
      .getDecisionsForStudent(b.studentId)
      .where((d) => d.academicYearId == b.academicYearId)
      .toList();
  if (decs.isNotEmpty) {
    final d = decs.first;
    if (d.status == 'validated' || d.status == 'locked')
      displayedDecision = d.decision;
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      build: (pw.Context ctx) => [
        pw.Header(
            level: 0,
            child: pw.Text(school?.name ?? '',
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold))),
        pw.Text('Année: ${b.academicYearId}'),
        pw.SizedBox(height: 8),
        pw.Text('Élève: ${student != null ? student.fullName : b.studentId}'),
        pw.Text(
            'Classe: ${b.classId}    Effectif: ${b.classSize}    Rang: ${b.rank != null ? '${b.rank} / ${b.classSize}' : '-'}'),
        pw.SizedBox(height: 12),
        pw.Table.fromTextArray(
          headers: headers,
          data: rows,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignment: pw.Alignment.centerLeft,
        ),
        pw.SizedBox(height: 12),
        pw.Text(
            'Moyenne générale annuelle: ${b.generalAverage != null ? b.generalAverage!.toStringAsFixed(2) : '-'}'),
        pw.Text('Décision: $displayedDecision'),
        pw.SizedBox(height: 24),
        pw.Text('Appréciations:'),
        pw.SizedBox(height: 48),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Professeur principal: ____________________'),
          pw.Text('Administration: ____________________'),
        ]),
      ],
    ),
  );

  return pdf;
}
