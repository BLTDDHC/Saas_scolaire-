import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pdf_font_theme.dart';

String _cell(dynamic value) {
  if (value == null) return '';
  if (value is num) {
    if (value is double && value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }
  return value.toString();
}

/// Builds the printable report from the exact immutable snapshot currently
/// displayed by the statistics screen. Keeping the same map instance prevents
/// a second request from silently producing different values while the user is
/// opening or downloading the PDF.
Map<String, dynamic> statisticsPdfReport({
  required Map<String, dynamic> statistics,
  required String schoolName,
  required String academicYear,
  String? schoolCity,
  String? cycleName,
  String? levelName,
  String? className,
  String? periodName,
  String? subjectName,
}) =>
    {
      'title': 'Statistiques scolaires',
      'reportType': 'cycle_statistics',
      'schoolName': schoolName,
      'schoolCity': schoolCity,
      'academicYear': academicYear,
      'cycleName': cycleName,
      'levelName': levelName,
      'className': className,
      'periodName': periodName,
      'subjectName': subjectName,
      'columns': const <Map<String, dynamic>>[],
      'rows': const <Map<String, dynamic>>[],
      'statisticsData': statistics,
    };

List<pw.Widget> _statisticsDashboard(Map<String, dynamic> statistics) {
  final distribution =
      Map<String, dynamic>.from(statistics['distribution'] as Map? ?? const {});
  final byClass = (statistics['byClass'] as List? ?? const [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  final byLevel = (statistics['byLevel'] as List? ?? const [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  final bySubject = (statistics['bySubject'] as List? ?? const [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  final top10 = (statistics['top10'] as List? ?? const [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  final evolution = (statistics['evolution'] as List? ?? const [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  final monthlyEvolution =
      (statistics['monthlyEvolution'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
  final attendanceByClass =
      (statistics['attendanceByClass'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
  final gradeCompletion =
      (statistics['gradeCompletion'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
  final insights = (statistics['insights'] as List? ?? const [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  final alerts = (statistics['alerts'] as List? ?? const [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  final finance = statistics['finance'] is Map
      ? Map<String, dynamic>.from(statistics['finance'] as Map)
      : null;
  final teacherStatistics = Map<String, dynamic>.from(
      statistics['teacherStatistics'] as Map? ?? const {});
  pw.Widget metric(String label, dynamic value) => pw.Container(
        width: 150,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 3),
              pw.Text(_cell(value),
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold)),
            ]),
      );
  pw.Widget table(
          String title, List<String> headers, List<List<String>> rows) =>
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(height: 14),
        pw.Text(title,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        if (rows.isEmpty)
          pw.Text('Aucune donnée pour les critères sélectionnés.',
              style: const pw.TextStyle(fontSize: 9))
        else
          pw.TableHelper.fromTextArray(
            data: [headers, ...rows],
            headerCount: 1,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellPadding: const pw.EdgeInsets.all(6),
          ),
      ]);
  pw.Widget chart(String title, List<MapEntry<String, double>> values,
      PdfColor color) {
    final maximum = values.fold<double>(
        0, (max, item) => item.value > max ? item.value : max);
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(height: 14),
      pw.Text(title,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      ...values.map((item) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(children: [
              pw.SizedBox(
                  width: 105,
                  child: pw.Text(item.key,
                      style: const pw.TextStyle(fontSize: 9))),
              pw.Container(
                width: maximum <= 0 ? 0 : 280 * item.value / maximum,
                height: 9,
                color: color,
              ),
              pw.SizedBox(width: 6),
              pw.Text(_cell(item.value),
                  style: const pw.TextStyle(fontSize: 9)),
            ]),
          )),
    ]);
  }

  return [
    pw.Wrap(spacing: 8, runSpacing: 8, children: [
      metric('Élèves avec résultats', statistics['officialStudentCount'] ?? 0),
      metric(
          'Moyenne générale',
          statistics['overallAverage'] == null
              ? 'Non calculée'
              : '${statistics['overallAverage']} / 20'),
      metric(
          'Taux de réussite',
          statistics['successRate'] == null
              ? 'Non calculé'
              : '${statistics['successRate']} %'),
      metric(
          'Taux d’échec',
          statistics['failureRate'] == null
              ? 'Non calculé'
              : '${statistics['failureRate']} %'),
      metric(
          'Taux de présence',
          statistics['attendanceRate'] == null
              ? 'Non calculé'
              : '${statistics['attendanceRate']} %'),
      metric('Absences', statistics['absenceCount'] ?? 0),
      metric('Enseignants actifs', statistics['teacherCount'] ?? 0),
      metric('Classes', statistics['classCount'] ?? 0),
      metric(
          'Notes saisies',
          statistics['gradeCompletionRate'] == null
              ? 'Non calculé'
              : '${statistics['gradeCompletionRate']} %'),
    ]),
    if (evolution.isNotEmpty)
      chart(
          'Évolution des moyennes officielles',
          evolution
              .map((row) => MapEntry('${row['period']}',
                  (row['average20'] as num?)?.toDouble() ?? 0))
              .toList(),
          PdfColors.green600),
    if (monthlyEvolution.isNotEmpty)
      chart(
          'Évolution mensuelle des notes publiées',
          monthlyEvolution
              .map((row) => MapEntry('${row['month']}',
                  (row['average20'] as num?)?.toDouble() ?? 0))
              .toList(),
          PdfColors.teal600),
    if (byLevel.isNotEmpty)
      chart(
          'Comparaison graphique des niveaux',
          byLevel
              .map((row) => MapEntry('${row['level']}',
                  (row['average20'] as num?)?.toDouble() ?? 0))
              .toList(),
          PdfColors.indigo600),
    if (byClass.isNotEmpty)
      chart(
          'Comparaison graphique des classes',
          byClass
              .map((row) => MapEntry('${row['className']}',
                  (row['average20'] as num?)?.toDouble() ?? 0))
              .toList(),
          PdfColors.blue600),
    if (attendanceByClass.isNotEmpty)
      chart(
          'Présence par classe',
          attendanceByClass
              .map((row) => MapEntry('${row['className']}',
                  (row['rate'] as num?)?.toDouble() ?? 0))
              .toList(),
          PdfColors.green700),
    if (gradeCompletion.isNotEmpty)
      chart(
          'Complétude de la saisie des notes',
          gradeCompletion
              .take(12)
              .map((row) => MapEntry(
                  '${row['teacher']} · ${row['subject']} · ${row['className']}',
                  (row['completionRate'] as num?)?.toDouble() ?? 0))
              .toList(),
          PdfColors.orange600),
    chart(
        'Répartition graphique des résultats',
        distribution.entries
            .map((entry) => MapEntry(
                entry.key, (entry.value as num?)?.toDouble() ?? 0))
            .toList(),
        PdfColors.blue600),
    table(
        'Répartition des résultats',
        ['Catégorie', 'Élèves'],
        distribution.entries
            .map((entry) => [entry.key, _cell(entry.value)])
            .toList()),
    table(
        'Suivi des enseignants et des cours',
        ['Indicateur', 'Valeur'],
        [
          ['Enseignants actifs', _cell(teacherStatistics['active'])],
          ['Cours planifiés', _cell(teacherStatistics['plannedCourses'])],
          ['Appels verrouillés', _cell(teacherStatistics['completedCourses'])],
        ]),
    if (finance != null)
      table(
          'Situation financière du périmètre',
          ['Indicateur', 'Valeur'],
          [
            ['Attendu', '${_cell(finance['expected'])} FCFA'],
            ['Encaissé', '${_cell(finance['paid'])} FCFA'],
            ['Reste à encaisser', '${_cell(finance['remaining'])} FCFA'],
            ['Taux de recouvrement', '${_cell(finance['collectionRate'])} %'],
          ]),
    table(
        'Comparaison des niveaux',
        ['Niveau', 'Élèves', 'Moyenne /20'],
        byLevel
            .map((row) => [
                  _cell(row['level']),
                  _cell(row['studentCount']),
                  _cell(row['average20']),
                ])
            .toList()),
    table(
        'Comparaison des classes',
        ['Classe', 'Élèves', 'Moyenne /20', 'Réussite'],
        byClass
            .map((row) => [
                  _cell(row['className']),
                  _cell(row['studentCount']),
                  _cell(row['average20']),
                  row['successRate'] == null ? '—' : '${row['successRate']} %',
                ])
            .toList()),
    table(
        'Performance par matière',
        ['Matière', 'Élèves', 'Moyenne /20', 'Réussite'],
        bySubject
            .map((row) => [
                  _cell(row['subject']),
                  _cell(row['studentCount']),
                  _cell(row['average20']),
                  row['successRate'] == null ? '—' : '${row['successRate']} %',
                ])
            .toList()),
    table(
        'Classement — 10 meilleurs',
        ['Rang', 'Élève', 'Classe', 'Moyenne /20', 'Appréciation'],
        top10
            .asMap()
            .entries
            .map((entry) => [
                  '${entry.key + 1}',
                  _cell(entry.value['name']),
                  _cell(entry.value['className']),
                  _cell(entry.value['average20']),
                  _cell(entry.value['mention']),
                ])
            .toList()),
    table(
        'Ce qu’il faut retenir',
        ['Analyse', 'Observation'],
        insights
            .map((item) => [_cell(item['title']), _cell(item['message'])])
            .toList()),
    if (alerts.isNotEmpty)
      table(
          'Points d’attention',
          ['Alerte', 'Observation'],
          alerts
              .map((item) => [_cell(item['title']), _cell(item['message'])])
              .toList()),
  ];
}

Future<pw.Document> buildSchoolReportPdf(Map<String, dynamic> report) async {
  final pdf = pw.Document();
  final theme = await buildSchoolPdfTheme();
  final columns = List<Map<String, dynamic>>.from(
    (report['columns'] as List? ?? const []).map(
      (item) => Map<String, dynamic>.from(item as Map),
    ),
  );
  final rows = List<Map<String, dynamic>>.from(
    (report['rows'] as List? ?? const []).map(
      (item) => Map<String, dynamic>.from(item as Map),
    ),
  );
  final statistics = report['statisticsData'] is Map
      ? Map<String, dynamic>.from(report['statisticsData'] as Map)
      : null;
  final data = <List<String>>[
    columns.map((column) => _cell(column['label'])).toList(),
    ...rows.map(
      (row) => columns.map((column) => _cell(row[column['key']])).toList(),
    ),
  ];

  pdf.addPage(
    pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
      build: (_) => [
        // Keep the same institutional header language and balance as the
        // official bulletin, as requested for school result lists/reports.
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'MINISTÈRE DE L\'ENSEIGNEMENT',
                    style: pw.TextStyle(
                        fontSize: 8, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text('PRÉSCOLAIRE, PRIMAIRE, SECONDAIRE',
                      style: const pw.TextStyle(fontSize: 8)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _cell(report['schoolName']),
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                  if (_cell(report['schoolCity']).isNotEmpty)
                    pw.Text(_cell(report['schoolCity']),
                        style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('RÉPUBLIQUE DU CONGO',
                    style: pw.TextStyle(
                        fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.Text('Unité * Travail * Progrès',
                    style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Center(
          child: pw.Text(
            _cell(report['title']).toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Wrap(spacing: 16, runSpacing: 4, children: [
          pw.Text('Année : ${_cell(report['academicYear'])}'),
          if (_cell(report['cycleName']).isNotEmpty)
            pw.Text('Cycle : ${_cell(report['cycleName'])}'),
          if (_cell(report['levelName']).isNotEmpty)
            pw.Text('Niveau : ${_cell(report['levelName'])}'),
          if (_cell(report['className']).isNotEmpty)
            pw.Text('Classe : ${_cell(report['className'])}'),
          if (_cell(report['periodName']).isNotEmpty)
            pw.Text('Période : ${_cell(report['periodName'])}'),
          if (_cell(report['subjectName']).isNotEmpty)
            pw.Text('Matière : ${_cell(report['subjectName'])}'),
          if (_cell(report['month']).isNotEmpty)
            pw.Text('Mois : ${_cell(report['month'])}'),
        ]),
        pw.SizedBox(height: 16),
        if (statistics != null)
          ..._statisticsDashboard(statistics)
        else if (rows.isEmpty)
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.Text('Aucune donnée pour les critères sélectionnés.'),
          )
        else
          pw.TableHelper.fromTextArray(
            data: data,
            headerCount: 1,
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 6,
            ),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellStyle: const pw.TextStyle(fontSize: 9.5),
          ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Document généré depuis les données enregistrées dans le système.',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    ),
  );
  return pdf;
}

String schoolReportFileName(Map<String, dynamic> report) {
  final raw = '${report['title'] ?? 'rapport-scolaire'}'
      .replaceAll(RegExp(r'[^A-Za-z0-9À-ÿ _-]'), '')
      .replaceAll(RegExp(r'\s+'), '-')
      .toLowerCase();
  return '$raw.pdf';
}
