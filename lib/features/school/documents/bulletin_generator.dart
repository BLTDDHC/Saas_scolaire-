import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/services/store_service.dart';
import '../../../data/datasources/api_client.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/responsive_grid.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pdf_helpers.dart';

class BulletinGenerator extends StatefulWidget {
  const BulletinGenerator({super.key, this.onGenerated});

  final VoidCallback? onGenerated;

  @override
  State<BulletinGenerator> createState() => _BulletinGeneratorState();
}

class _BulletinGeneratorState extends State<BulletinGenerator> {
  String? _selectedLevel;
  String? _selectedClassId;
  String? _selectedStudentId;
  String? _selectedPeriodId;
  Map<String, dynamic>? _bulletinData;
  List<Map<String, dynamic>> _periods = const [];
  bool _loadingPeriods = false;
  bool _generating = false;
  bool _savingPdf = false;
  String? _error;
  String _signatoryTitle = 'Le/La Proviseur(e)';
  String _colorTheme = 'auto';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPeriods());
  }

  Future<void> _loadPeriods() async {
    final store = context.read<StoreService>();
    final yearId = store.getSelectedAcademicYearId();
    if (yearId == null || _loadingPeriods) return;
    setState(() => _loadingPeriods = true);
    try {
      final periods = await store.academicPeriodsRemote(yearId);
      if (!mounted) return;
      setState(() => _periods = periods
          .where((item) =>
              item['periodType'] == 'trimester' &&
              item['status'] == 'active' &&
              bulletinTrimesterMonths(item['name']).isNotEmpty)
          .take(3)
          .toList());
    } on ApiException {
      if (mounted)
        setState(() => _error = 'Impossible de charger les trimestres.');
    } finally {
      if (mounted) setState(() => _loadingPeriods = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<StoreService>();
    final allClasses =
        store.getClassesByYear(store.getSelectedAcademicYearId());
    final levels = allClasses
        .map((item) => (item.level ?? '').trim())
        .where((level) => level.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final classes = _selectedLevel == null
        ? allClasses
        : allClasses.where((item) => item.level == _selectedLevel).toList();
    final periods = _periods;

    final students = _selectedClassId != null
        ? store
            .getStudents()
            .where((s) => s.classId == _selectedClassId)
            .toList()
        : <dynamic>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Générateur de bulletin trimestriel',
            style: AppTypography.heading3()),
        const SizedBox(height: AppSpacing.s4),
        ResponsiveFormGrid(
          maxColumns: 4,
          children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
                initialValue: _selectedLevel,
                hint: const Text('Sélectionner un niveau'),
                items: levels
                    .map((level) => DropdownMenuItem<String>(
                        value: level, child: Text(level)))
                    .toList(),
                onChanged: (value) => setState(() {
                  _selectedLevel = value;
                  _selectedClassId = null;
                  _selectedStudentId = null;
                  _bulletinData = null;
                }),
              ),
            DropdownButtonFormField<String>(
              isExpanded: true,
                initialValue: _selectedClassId,
                hint: const Text('Sélectionner une classe'),
                items: classes
                    .map((c) => DropdownMenuItem<String>(
                        value: c.id, child: Text(c.name)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedClassId = v;
                  _selectedStudentId = null;
                  _bulletinData = null;
                  final selectedClass =
                      v == null ? null : store.getClassById(v);
                  _signatoryTitle = bulletinDefaultSignatoryTitle({
                    'cycle': selectedClass?.cycle,
                    'name': selectedClass?.name,
                  });
                }),
              ),
            DropdownButtonFormField<String>(
              isExpanded: true,
                initialValue: _selectedStudentId,
                key: ValueKey(_selectedClassId),
                hint: const Text('Sélectionner un élève'),
                items: students
                    .map((s) => DropdownMenuItem<String>(
                        value: s.id as String, child: Text(s.fullName)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedStudentId = v;
                  _bulletinData = null;
                }),
              ),
            DropdownButtonFormField<String>(
              isExpanded: true,
                initialValue: _selectedPeriodId,
                hint: const Text('Sélectionner une période'),
                items: periods
                    .map((p) => DropdownMenuItem<String>(
                        value: p['id']?.toString(),
                        child: Text('${p['name']}')))
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedPeriodId = v;
                  _bulletinData = null;
                }),
              ),
          ],
        ),
        if (_selectedClassId != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s3),
            child: Text(
              'Modèle déterminé automatiquement : ${_automaticModelLabel(store.getClassById(_selectedClassId!))}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: AppSpacing.s3),
        ResponsiveFormGrid(
          children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
                key: ValueKey(_signatoryTitle),
                initialValue: _signatoryTitle,
                decoration:
                    const InputDecoration(labelText: 'Fonction du signataire'),
                items: const [
                  DropdownMenuItem(
                      value: 'Le/La Proviseur(e)',
                      child: Text('Le/La Proviseur(e)')),
                  DropdownMenuItem(
                      value: 'Le/La Principal(e)',
                      child: Text('Le/La Principal(e)')),
                  DropdownMenuItem(
                      value: 'Le/La Directeur(trice)',
                      child: Text('Le/La Directeur(trice)')),
                  DropdownMenuItem(
                      value: 'Le/La Responsable de l’établissement',
                      child: Text('Le/La Responsable de l’établissement')),
                ],
                onChanged: (value) => setState(() {
                  _signatoryTitle = value ?? _signatoryTitle;
                  _bulletinData = null;
                }),
              ),
            DropdownButtonFormField<String>(
              isExpanded: true,
                initialValue: _colorTheme,
                decoration:
                    const InputDecoration(labelText: 'Couleur du bulletin'),
                items: const [
                  DropdownMenuItem(
                      value: 'auto',
                      child: Text('Automatique selon le niveau')),
                  DropdownMenuItem(value: 'bleu', child: Text('Bleu')),
                  DropdownMenuItem(value: 'vert', child: Text('Vert')),
                  DropdownMenuItem(value: 'bordeaux', child: Text('Bordeaux')),
                ],
                onChanged: (value) => setState(() {
                  _colorTheme = value ?? 'auto';
                  _bulletinData = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        Row(
          children: [
            AppButton(
                label: _generating ? 'Génération…' : 'Générer le bulletin',
                onPressed: _canGenerate() && !_generating ? _generate : null),
            const SizedBox(width: AppSpacing.s3),
            AppButton(
                label: 'Voir / imprimer',
                onPressed:
                    _bulletinData != null && !_savingPdf ? _printPdf : null,
                icon: Icons.print_rounded),
            const SizedBox(width: AppSpacing.s3),
            AppButton(
                label: _savingPdf ? 'Téléchargement…' : 'Télécharger PDF',
                onPressed:
                    _bulletinData != null && !_savingPdf ? _downloadPdf : null,
                icon: Icons.download_rounded),
          ],
        ),
        const SizedBox(height: AppSpacing.s6),
        if (_loadingPeriods) const LinearProgressIndicator(),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        if (_bulletinData != null) _buildPreview(_bulletinData!),
      ],
    );
  }

  bool _canGenerate() =>
      _selectedClassId != null &&
      _selectedStudentId != null &&
      _selectedPeriodId != null;

  String _automaticModelLabel(dynamic schoolClass) {
    final cycle = '${schoolClass?.cycle ?? ''}'.toLowerCase();
    if (cycle.contains('mater')) return 'Maternelle';
    if (cycle.contains('prim')) return 'Primaire';
    if (cycle.contains('coll')) return 'Collège';
    if (cycle.contains('lyc')) return 'Lycée';
    return 'selon le cycle de la classe';
  }

  Future<void> _generate() async {
    final store = context.read<StoreService>();
    final yearId = store.getSelectedAcademicYearId();
    if (yearId == null) return;
    final classId = _selectedClassId!;
    final studentId = _selectedStudentId!;
    final periodId = _selectedPeriodId!;
    setState(() {
      _generating = true;
      _error = null;
      _bulletinData = null;
    });
    try {
      final source = await store.studentBulletinRemote(studentId, yearId);
      final period = (source['periods'] as List? ?? const [])
          .cast<Map>()
          .where((item) => item['periodId']?.toString() == periodId)
          .toList();
      if (period.isEmpty || period.single['average'] == null) {
        throw ApiException(
            'Les résultats de cette période ne sont pas encore officiels.',
            409);
      }
      final selected = Map<String, dynamic>.from(period.single);
      if (selected['calculationStatus'] != 'official' ||
          selected['detailsAvailable'] != true) {
        throw ApiException(
            'Recalculez les résultats pour obtenir le détail officiel du bulletin.',
            409);
      }
      final school =
          store.getEstablishmentById(store.getClassById(classId)!.schoolId);
      final data = trimesterPdfDataFromOfficialSource(
        source: source,
        selected: selected,
        school: {'name': school?.name ?? '', 'city': school?.city ?? ''},
        studentId: studentId,
        yearId: yearId,
        periodId: periodId,
        signatoryTitle: _signatoryTitle,
        colorTheme: _colorTheme,
      );
      await store.createDocumentRemote(
        schoolId: store.getClassById(classId)?.schoolId,
        title:
            'Bulletin — ${selected['period']} — ${data['student']['lastName']} ${data['student']['firstName']} — ${data['class']['name']} — ${data['academicYearId']}',
        type: 'official_results',
        entityId: classId,
        metadata: {
          'documentKind': 'bulletin',
          'studentId': studentId,
          'periodId': periodId,
          'resultStatus': 'official',
          'signatoryTitle': _signatoryTitle,
          'colorTheme': _colorTheme,
        },
      );
      widget.onGenerated?.call();
      if (mounted &&
          _selectedStudentId == studentId &&
          _selectedPeriodId == periodId &&
          _selectedClassId == classId) setState(() => _bulletinData = data);
    } on ApiException catch (error) {
      if (mounted)
        setState(() => _error = error.statusCode == 403
            ? 'Vous n’êtes pas autorisé à générer ce bulletin.'
            : AppToast.humanErrorMessage(
                error.message,
                fallback: 'Impossible de générer le bulletin pour le moment.',
              ));
    } catch (_) {
      if (mounted)
        setState(
            () => _error = 'Impossible de générer le bulletin pour le moment.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Widget _buildPreview(Map<String, dynamic> data) {
    final school = data['school'] as Map<String, dynamic>?;
    final student = data['student'] as Map<String, dynamic>?;
    final cls = data['class'] as Map<String, dynamic>?;
    final subjects = data['subjects'] as List<dynamic>;
    final ranking = data['ranking'] as Map<String, dynamic>?;
    final generalAverage = data['generalAverage'] as double?;
    final accent = _previewAccentColor(data);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(school?['name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(school?['city'] ?? ''),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Année: ${data['academicYearId'] ?? ''}'),
                Text('Période: ${data['periodId'] ?? ''}'),
              ])
            ],
          ),
          const SizedBox(height: 12),
          Text(
              'Élève: ${student?['lastName'] ?? ''} ${student?['firstName'] ?? ''}'),
          Text('Classe: ${cls?['name'] ?? ''}'),
          const SizedBox(height: 12),
          // Table header
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(accent),
              columns: _buildTableColumns(subjects),
              rows: [
                ...subjects.map((s) => _buildSubjectRow(s)),
                if (_isLycee) _buildTotalRow(subjects),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_isLycee)
            Text('Total coefficients: ${_computeTotalCoefficients(subjects)}'),
          if (_isLycee)
            Text('Total pondéré: ${_computeTotalWeighted(subjects)}'),
          Text(
              'Moyenne générale /${_displayScale.toStringAsFixed(0)}: ${generalAverage != null ? generalAverage.toString() : '—'}'),
          Text('Rang: ${bulletinRankLabel(ranking)}'),
          Text(
              'Mention: ${bulletinMentionLabel(data['mention'], generalAverage, _displayScale)}'),
          Text(
              'Décision: ${bulletinDecisionLabel(data['decision'], generalAverage, student?['sex'], _displayScale)}'),
          Text('Fait à ${school?['city'] ?? ''}'),
          Text('${data['signatoryTitle'] ?? 'Le/La Responsable'}'),
        ],
      ),
    );
  }

  List<DataColumn> _buildTableColumns(List<dynamic> subjects) {
    if (_isLycee) {
      return const [
        DataColumn(label: Text('Matière')),
        DataColumn(label: Text('Devoir 1')),
        DataColumn(label: Text('Devoir 2')),
        DataColumn(label: Text('Composition')),
        DataColumn(label: Text('MC')),
        DataColumn(label: Text('Moyenne')),
        DataColumn(label: Text('Coefficient')),
        DataColumn(label: Text('Point')),
        DataColumn(label: Text('Appréciation')),
      ];
    }
    // Determine max number of devoirs across subjects
    int maxDevoirs = 0;
    for (final s in subjects) {
      final devoirs = s['devoirs'] as List<dynamic>;
      if (devoirs.length > maxDevoirs) maxDevoirs = devoirs.length;
    }
    final cols = <DataColumn>[];
    cols.add(DataColumn(label: Text(_isMaternelle ? 'Domaine' : 'Matière')));
    if (_usesTenPointScale) {
      cols.add(const DataColumn(label: Text('Barème')));
    }
    for (int i = 0; i < maxDevoirs; i++)
      cols.add(DataColumn(label: Text('Dev ${i + 1}')));
    cols.add(const DataColumn(label: Text('MC')));
    cols.add(const DataColumn(label: Text('Composition')));
    cols.add(DataColumn(
        label: Text('Moyenne /${_displayScale.toStringAsFixed(0)}')));
    cols.add(const DataColumn(label: Text('Appréciation')));
    return cols;
  }

  DataRow _buildSubjectRow(dynamic s) {
    final devo = s['devoirs'] as List<dynamic>;
    if (_isLycee) {
      String value(Object? item) => item == null ? '—' : item.toString();
      return DataRow(cells: [
        DataCell(Text(s['subjectName'] ?? '')),
        DataCell(Text(value(devo.isNotEmpty ? devo[0] : null))),
        DataCell(Text(value(devo.length > 1 ? devo[1] : null))),
        DataCell(Text(value(s['composition']))),
        DataCell(Text(value(s['mc']))),
        DataCell(Text(value(s['subjectAverage']))),
        DataCell(Text(value(s['coefficient']))),
        DataCell(Text(value(s['point']))),
        DataCell(Text(bulletinMentionLabel(null, s['subjectAverage']))),
      ]);
    }
    final cells = <DataCell>[];
    cells.add(DataCell(Text(s['subjectName'] ?? '')));
    if (_usesTenPointScale) {
      cells.add(DataCell(Text('${s['scale'] ?? 10}')));
    }
    for (final d in devo) {
      if (d == null)
        cells.add(const DataCell(Text('—')));
      else
        cells.add(DataCell(Text((d as num).toString())));
    }
    cells.add(
        DataCell(Text(s['mc'] != null ? (s['mc'] as num).toString() : '—')));
    cells.add(DataCell(Text(s['composition'] != null
        ? (s['composition'] as num).toString()
        : '—')));
    cells.add(DataCell(Text(s['subjectAverage'] != null
        ? (s['subjectAverage'] as num).toString()
        : '—')));
    final stored = '${s['appreciation'] ?? ''}'.trim();
    cells.add(DataCell(Text(stored.isNotEmpty
        ? stored
        : bulletinMentionLabel(null, s['subjectAverage'], _displayScale))));
    return DataRow(cells: cells);
  }

  bool get _isLycee =>
      _bulletinData?['cycle']?.toString().toLowerCase().contains('lyc') == true;

  String get _cycle => (_bulletinData?['cycle'] ?? '').toString().toLowerCase();

  bool get _isMaternelle =>
      _cycle.contains('mater') || _cycle.contains('preschool');

  bool get _usesTenPointScale =>
      _isMaternelle || _cycle.contains('prim') || _cycle.contains('element');

  double get _displayScale =>
      (_bulletinData?['displayScale'] as num?)?.toDouble() ??
      (_usesTenPointScale ? 10 : 20);

  DataRow _buildTotalRow(List<dynamic> subjects) {
    Text total(Object? value) =>
        Text(value == null ? '—' : _displayNumber(value),
            style: const TextStyle(fontWeight: FontWeight.bold));
    return DataRow(cells: [
      const DataCell(
          Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold))),
      DataCell(total(_sumColumn(subjects, (subject) {
        final values = subject['devoirs'] as List<dynamic>? ?? const [];
        return values.isNotEmpty ? values[0] : null;
      }))),
      DataCell(total(_sumColumn(subjects, (subject) {
        final values = subject['devoirs'] as List<dynamic>? ?? const [];
        return values.length > 1 ? values[1] : null;
      }))),
      DataCell(
          total(_sumColumn(subjects, (subject) => subject['composition']))),
      DataCell(total(_sumColumn(subjects, (subject) => subject['mc']))),
      DataCell(
          total(_sumColumn(subjects, (subject) => subject['subjectAverage']))),
      DataCell(
          total(_sumColumn(subjects, (subject) => subject['coefficient']))),
      DataCell(total(_sumColumn(subjects, (subject) => subject['point']))),
      const DataCell(Text('—', style: TextStyle(fontWeight: FontWeight.bold))),
    ]);
  }

  num? _sumColumn(List<dynamic> subjects, Object? Function(dynamic) valueOf) {
    num sum = 0;
    var hasValue = false;
    for (final subject in subjects) {
      final value = valueOf(subject);
      if (value is num) {
        sum += value;
        hasValue = true;
      }
    }
    return hasValue ? sum : null;
  }

  String _displayNumber(Object value) {
    if (value is! num) return '$value';
    return value
        .toDouble()
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'\.00$'), '');
  }

  Color _previewAccentColor(Map<String, dynamic> data) {
    switch (bulletinColorThemeKey(data)) {
      case 'seconde':
      case 'bleu':
        return const Color(0xffdceaf7);
      case 'premiere':
      case 'vert':
        return const Color(0xffdcefdc);
      case 'terminale':
      case 'bordeaux':
        return const Color(0xffead9e5);
      default:
        return const Color(0xffe8e8e8);
    }
  }

  num _computeTotalCoefficients(List<dynamic> subjects) {
    num sum = 0;
    for (final s in subjects) {
      if (s['subjectAverage'] != null) sum += (s['coefficient'] as num);
    }
    return sum;
  }

  num _computeTotalWeighted(List<dynamic> subjects) {
    num sum = 0;
    for (final s in subjects) {
      if (s['subjectAverage'] != null)
        sum += (s['subjectAverage'] as num) * (s['coefficient'] as num);
    }
    return sum;
  }

  Future<void> _printPdf() async {
    if (_bulletinData == null) return;
    final data = _bulletinData!;
    try {
      final source = await context
          .read<StoreService>()
          .studentBulletinRemote(data['sourceStudentId'], data['sourceYearId']);
      final periods = (source['periods'] as List).cast<Map>();
      final period = periods
          .where((p) => p['periodId'] == data['sourcePeriodId'])
          .toList();
      if (period.length != 1 ||
          period.single['calculationStatus'] != 'official' ||
          period.single['calculatedAt'] != data['calculatedAt']) {
        throw ApiException(
            'Les résultats ont changé. Générez de nouveau le bulletin.', 409);
      }
      final doc = await _buildPdf(data);
      await Printing.layoutPdf(onLayout: (format) => doc.save());
    } catch (_) {
      if (mounted)
        setState(() {
          _bulletinData = null;
          _error =
              'Impossible de vérifier ou imprimer ce bulletin. Actualisez les résultats puis générez-le de nouveau.';
        });
    }
  }

  Future<void> _downloadPdf() async {
    if (_bulletinData == null || _savingPdf) return;
    setState(() => _savingPdf = true);
    try {
      final data = _bulletinData!;
      final source = await context
          .read<StoreService>()
          .studentBulletinRemote(data['sourceStudentId'], data['sourceYearId']);
      final periods = (source['periods'] as List).cast<Map>();
      final period = periods
          .where((p) => p['periodId'] == data['sourcePeriodId'])
          .toList();
      if (period.length != 1 ||
          period.single['calculationStatus'] != 'official' ||
          period.single['calculatedAt'] != data['calculatedAt']) {
        throw ApiException(
            'Les résultats ont changé. Générez de nouveau le bulletin.', 409);
      }
      final doc = await _buildPdf(data);
      final bytes = await doc.save();
      await Printing.sharePdf(bytes: bytes, filename: bulletinFileName(data));
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Le téléchargement du PDF a échoué. Actualisez les résultats puis réessayez.');
    } finally {
      if (mounted) setState(() => _savingPdf = false);
    }
  }

  Future<pw.Document> _buildPdf(Map<String, dynamic> data) =>
      buildTrimesterPdfFromData(data);
}
