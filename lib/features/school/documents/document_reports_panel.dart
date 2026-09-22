import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/pdf_download.dart';
import '../../../data/datasources/api_client.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/responsive_grid.dart';
import 'document_report_pdf.dart';

enum _ReportOutput { preview, download, send }

class DocumentReportsPanel extends StatefulWidget {
  const DocumentReportsPanel({super.key, required this.onGenerated});

  final VoidCallback onGenerated;

  @override
  State<DocumentReportsPanel> createState() => _DocumentReportsPanelState();
}

class _DocumentReportsPanelState extends State<DocumentReportsPanel> {
  String _reportType = 'unpaid_tuition';
  String? _cycleId;
  String? _levelId;
  String? _classId;
  String? _periodId;
  String? _subjectId;
  String? _month;
  bool _busy = false;
  List<Map<String, dynamic>> _periods = const [];
  String? _loadedYearId;

  static const _reportTypes = <String, String>{
    'unpaid_tuition': 'Impayés mensuels par classe',
    'partial_tuition': 'Avances mensuelles par classe',
    'class_results': 'Résultats par classe',
    'enrolled_students': 'Élèves inscrits par classe',
    'evaluation_schedule': 'Calendrier des évaluations',
    'cycle_top10': '10 meilleurs du cycle',
    'cycle_statistics': 'Rapport statistique de l’écran',
  };

  bool get _needsClass => const {
        'unpaid_tuition',
        'partial_tuition',
        'class_results',
        'enrolled_students',
      }.contains(_reportType);
  bool get _needsCycle => const {
        'evaluation_schedule',
        'cycle_top10',
      }.contains(_reportType);
  bool get _needsMonth =>
      const {'unpaid_tuition', 'partial_tuition'}.contains(_reportType);
  bool get _needsPeriod => _reportType == 'class_results';
  bool get _isStatistics => _reportType == 'cycle_statistics';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.watch<StoreService>();
    final yearId = store.getSelectedAcademicYearId();
    if (yearId != null && yearId != _loadedYearId) {
      _loadedYearId = yearId;
      _loadPeriods(store, yearId);
      final year = store.getSelectedAcademicYear();
      if (year != null) {
        final start = DateTime.tryParse(year.start);
        if (start != null) {
          _month =
              '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}';
        }
      }
    }
  }

  Future<void> _loadPeriods(StoreService store, String yearId) async {
    try {
      final values = await store.academicPeriodsRemote(yearId);
      if (!mounted || yearId != _loadedYearId) return;
      setState(() {
        _periods =
            values.where((item) => item['periodType'] == 'trimester').toList();
        _periodId = _periods.isEmpty ? null : '${_periods.first['id']}';
      });
    } catch (_) {
      if (mounted) setState(() => _periods = const []);
    }
  }

  List<String> _months(StoreService store) {
    final year = store.getSelectedAcademicYear();
    if (year == null) return const [];
    final start = DateTime.tryParse(year.start);
    final end = DateTime.tryParse(year.end);
    if (start == null || end == null) return const [];
    final result = <String>[];
    var cursor = DateTime(start.year, start.month);
    final last = DateTime(end.year, end.month);
    while (!cursor.isAfter(last) && result.length < 12) {
      result.add(
          '${cursor.year.toString().padLeft(4, '0')}-${cursor.month.toString().padLeft(2, '0')}');
      cursor = DateTime(cursor.year + (cursor.month == 12 ? 1 : 0),
          cursor.month == 12 ? 1 : cursor.month + 1);
    }
    return result;
  }

  Future<void> _generate({required _ReportOutput output}) async {
    final store = context.read<StoreService>();
    final yearId = store.getSelectedAcademicYearId();
    if (yearId == null) {
      AppToast.warning(context, 'Sélectionnez une année scolaire.');
      return;
    }
    if (_needsClass && _classId == null) {
      AppToast.warning(context, 'Sélectionnez une classe.');
      return;
    }
    if (_needsCycle && _cycleId == null) {
      AppToast.warning(context, 'Sélectionnez un cycle.');
      return;
    }
    if (_needsPeriod && _periodId == null) {
      AppToast.warning(context, 'Sélectionnez un trimestre.');
      return;
    }
    if (_needsMonth && _month == null) {
      AppToast.warning(context, 'Sélectionnez un mois.');
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await store.generateDocumentReport({
        'reportType': _reportType,
        'academicYearId': yearId,
        if (_cycleId != null) 'cycleId': _cycleId,
        if (_levelId != null && _isStatistics) 'levelId': _levelId,
        if (_classId != null) 'classId': _classId,
        if (_periodId != null) 'periodId': _periodId,
        if (_subjectId != null && _isStatistics) 'subjectId': _subjectId,
        if (_month != null && _needsMonth) 'month': _month,
      });
      final report = Map<String, dynamic>.from(response['report'] as Map);
      final pdf = await buildSchoolReportPdf(report);
      final bytes = await pdf.save();
      final filename = schoolReportFileName(report);
      switch (output) {
        case _ReportOutput.preview:
          await Printing.layoutPdf(name: filename, onLayout: (_) => bytes);
        case _ReportOutput.download:
          await downloadPdfFile(bytes, filename);
        case _ReportOutput.send:
          await Printing.sharePdf(bytes: bytes, filename: filename);
      }
      widget.onGenerated();
      if (mounted) AppToast.success(context, 'Document généré et archivé.');
    } on ApiException catch (error) {
      if (mounted) AppToast.error(context, error.message);
    } catch (_) {
      if (mounted)
        AppToast.error(context, 'Impossible de générer ce document.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final cycles =
        store.getSchoolCycles().where((item) => item.isActive).toList();
    final levels = store
        .getSchoolLevels()
        .where((item) =>
            item.status == 'active' &&
            (_cycleId == null || item.cycleId == _cycleId))
        .toList();
    final subjects =
        store.getSubjects().where((item) => item.status == 'active').toList();
    final classes = store
        .getClassesByYear(store.getSelectedAcademicYearId())
        .where((item) =>
            (_cycleId == null || item.cycleId == _cycleId) &&
            (_levelId == null ||
                item.levelId == _levelId ||
                item.structuredLevelId == _levelId))
        .toList();
    final months = _months(store);
    if (_month != null && !months.contains(_month)) {
      _month = months.isEmpty ? null : months.first;
    }
    if (_classId != null && !classes.any((item) => item.id == _classId)) {
      _classId = null;
    }

    return AppCard(
      title: 'Listes, résultats et statistiques PDF',
      subtitle:
          'Les documents respectent l’année scolaire, le cycle et la classe sélectionnés et sont archivés dans Documents.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ResponsiveFormGrid(
            minFieldWidth: 230,
            maxColumns: 3,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _reportType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Document'),
                items: _reportTypes.entries
                    .map((entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                          _reportType = value ?? _reportType;
                          _levelId = null;
                          _classId = null;
                          _subjectId = null;
                        }),
              ),
              if (_needsCycle || _needsClass || _isStatistics)
                DropdownButtonFormField<String?>(
                  initialValue: _cycleId,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: _needsCycle ? 'Cycle *' : 'Cycle'),
                  items: [
                    if (!_needsCycle)
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('Tous les cycles')),
                    ...cycles.map((cycle) => DropdownMenuItem(
                          value: cycle.id,
                          child:
                              Text(cycle.name, overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                            _cycleId = value;
                            _levelId = null;
                            _classId = null;
                          }),
                ),
              if (_isStatistics)
                DropdownButtonFormField<String?>(
                  value: _levelId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Niveau'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Tous les niveaux')),
                    ...levels.map((level) => DropdownMenuItem<String?>(
                          value: level.id,
                          child: Text(level.name,
                              overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                            _levelId = value;
                            _classId = null;
                          }),
                ),
              if (_needsClass || _isStatistics)
                DropdownButtonFormField<String?>(
                  initialValue: _classId,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: _needsClass ? 'Classe *' : 'Classe'),
                  items: [
                    if (_isStatistics)
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('Toutes les classes')),
                    ...classes.map((schoolClass) => DropdownMenuItem<String?>(
                          value: schoolClass.id,
                          child: Text(schoolClass.name,
                              overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                            _classId = value;
                            final selected = classes
                                .where((item) => item.id == value)
                                .firstOrNull;
                            if (selected?.cycleId != null) {
                              _cycleId = selected!.cycleId;
                            }
                          }),
                ),
              if (_needsPeriod || _isStatistics)
                DropdownButtonFormField<String?>(
                  initialValue: _periodId,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: _needsPeriod ? 'Trimestre *' : 'Période'),
                  items: [
                    if (_isStatistics)
                      const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Dernière période officielle')),
                    ..._periods.map((period) => DropdownMenuItem<String?>(
                          value: '${period['id']}',
                          child: Text('${period['name']}',
                              overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _periodId = value),
                ),
              if (_needsMonth)
                DropdownButtonFormField<String>(
                  initialValue: _month,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Mois *'),
                  items: months
                      .map((month) => DropdownMenuItem(
                            value: month,
                            child: Text(month),
                          ))
                      .toList(),
                  onChanged:
                      _busy ? null : (value) => setState(() => _month = value),
                ),
              if (_isStatistics)
                DropdownButtonFormField<String?>(
                  value: _subjectId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Matière'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Toutes les matières')),
                    ...subjects.map((subject) => DropdownMenuItem<String?>(
                          value: subject.id,
                          child: Text(subject.name,
                              overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _subjectId = value),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _generate(output: _ReportOutput.preview),
                icon: const Icon(Icons.visibility_outlined),
                label: Text(_busy ? 'Génération…' : 'Voir le PDF'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _generate(output: _ReportOutput.download),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Télécharger'),
              ),
              OutlinedButton.icon(
                onPressed:
                    _busy ? null : () => _generate(output: _ReportOutput.send),
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('Envoyer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
