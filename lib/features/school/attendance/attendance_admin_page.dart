import 'package:flutter/material.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/widgets/workspace_header.dart';
import 'package:provider/provider.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/responsive_grid.dart';

class AttendanceAdminPage extends StatefulWidget {
  const AttendanceAdminPage({super.key});
  @override
  State<AttendanceAdminPage> createState() => _AttendanceAdminPageState();
}

class _AttendanceAdminPageState extends State<AttendanceAdminPage> {
  List<Map<String, dynamic>> _contexts = [], _options = [];
  String? _school, _year, _error;
  DateTime _date = DateTime.now();
  bool _history = false, _busy = false;
  Map<String, dynamic>? _report;
  final Map<String, String> _filters = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadContexts());
  }

  Future<void> _loadContexts() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final store = context.read<StoreService>();
      final rows = await store.attendanceContextsRemote();
      if (mounted)
        setState(() {
          _contexts = rows;
          // L'admin travaille déjà dans son établissement, sa direction et son
          // année sélectionnée : ce contexte ne doit pas devenir un filtre à
          // renseigner de nouveau sur chaque écran.
          if (!store.isSuperAdmin()) {
            final selectedYear = store.getSelectedAcademicYearId();
            final chosen = rows
                .where((row) => row['academicYearId'] == selectedYear)
                .toList();
            _year = (chosen.isNotEmpty
                    ? chosen.first
                    : (rows.isEmpty ? null : rows.first))?['academicYearId']
                ?.toString();
          }
        });
      if (mounted && !store.isSuperAdmin() && _year != null) {
        await _load(resetOptions: true);
      }
    } catch (_) {
      if (mounted)
        setState(() =>
            _error = 'Impossible de charger les années scolaires. Réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load({bool resetOptions = false}) async {
    if (_year == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final filters = {
      'academic_year_id': _year!,
      if (!_history)
        'attendance_date': _date.toIso8601String().split('T').first,
      ..._filters
    };
    try {
      final report =
          await context.read<StoreService>().attendanceReportRemote(filters);
      if (!mounted) return;
      setState(() {
        _report = report;
        if (resetOptions || _options.isEmpty) {
          _options = List<Map<String, dynamic>>.from([
            ...report['sessions'] as List,
            ...report['records'] as List,
            ..._contexts
                .where((r) => r['academicYearId'] == _year)
                .expand((r) => (r['periods'] as List?) ?? [])
          ]);
        }
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _report = null;
          _error =
              'Impossible de consulter les présences. Vérifiez la date et l’année sélectionnées.';
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _filter(String key, String idKey, String nameKey, String label) {
    final options = <String, String>{};
    for (final row in _options) {
      if (row[idKey] != null)
        options[row[idKey].toString()] = row[nameKey]?.toString() ?? label;
    }
    return SizedBox(
        width: 220,
        child: DropdownButtonFormField<String>(
          key: ValueKey('$key-$_year-$_history-${_date.toIso8601String()}'),
          initialValue: _filters[key],
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            const DropdownMenuItem(value: '', child: Text('Tous')),
            ...options.entries.map((e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis)))
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() {
                    if (value == null || value.isEmpty) {
                      _filters.remove(key);
                    } else {
                      _filters[key] = value;
                    }
                  }),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final isSuperAdmin = store.isSuperAdmin();
    // Les tests/mocks sans session gardent la sélection explicite, mais une
    // vraie session admin ne voit jamais de faux filtres de contexte.
    final showGlobalControls = isSuperAdmin || store.currentUser == null;
    final schools = {
      for (final row in _contexts)
        row['schoolId'] as String: row['school'] as String
    };
    final years = _contexts.where((r) => r['schoolId'] == _school).toList();
    final stats = _report?['statistics'] as Map?;
    return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WorkspaceHeader(
                title: isSuperAdmin
                    ? 'Présences — suivi et historique'
                    : 'Présences — suivi du jour',
                subtitle:
                    'Comparez les relevés attendus et reçus, puis consultez les présences officielles.',
                actions: [
                  AppButton(
                      label: 'Actualiser',
                      onPressed: _busy ? null : _loadContexts)
                ]),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              WorkspaceNotice(
                  message: _error!, error: true, onRetry: _loadContexts),
            Wrap(spacing: 16, runSpacing: 12, children: [
              if (showGlobalControls)
                SizedBox(
                    width: 250,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                        initialValue: _school,
                        decoration:
                            const InputDecoration(labelText: 'Établissement'),
                        items: schools.entries
                            .map((s) => DropdownMenuItem(
                                value: s.key, child: Text(s.value)))
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                  _school = value;
                                  _year = null;
                                  _report = null;
                                  _options = [];
                                  _filters.clear();
                                }))),
              if (showGlobalControls)
                SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                        key: ValueKey(_school),
                        initialValue: _year,
                        decoration:
                            const InputDecoration(labelText: 'Année scolaire'),
                        items: years
                            .map((y) => DropdownMenuItem(
                                value: y['academicYearId'] as String,
                                child: Text(y['year'] as String)))
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (value) {
                                setState(() {
                                  _year = value;
                                  _filters.clear();
                                  _options = [];
                                  _report = null;
                                });
                                _load(resetOptions: true);
                              })),
              AppButton(
                  label: 'Date : ${AppDateUtils.formatDate(_date)}',
                  onPressed: _busy || _history
                      ? null
                      : () async {
                          final date = await showDatePicker(
                              context: context,
                              initialDate: _date,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100));
                          if (date != null && mounted) {
                            setState(() {
                              _date = date;
                              _filters.clear();
                              _options = [];
                            });
                            _load(resetOptions: true);
                          }
                        }),
            ]),
            SwitchListTile(
                title: const Text('Historique de l’année — toutes les dates'),
                value: _history,
                onChanged: _busy
                    ? null
                    : (value) {
                        setState(() {
                          _history = value;
                          _filters.clear();
                          _options = [];
                        });
                        _load(resetOptions: true);
                      }),
            Wrap(spacing: 12, runSpacing: 12, children: [
              if (showGlobalControls)
                _filter(
                    'direction_id', 'directionId', 'direction', 'Direction'),
              if (showGlobalControls)
                _filter('period_id', 'periodId', 'period', 'Période'),
              if (showGlobalControls)
                _filter('cycle_id', 'cycleId', 'cycle', 'Cycle'),
              if (showGlobalControls)
                _filter('level_id', 'levelId', 'level', 'Niveau'),
              _filter('class_id', 'classId', 'class', 'Classe'),
              _filter('subject_id', 'subjectId', 'subject', 'Matière'),
              _filter('teacher_id', 'teacherId', 'teacher', 'Enseignant'),
              if (showGlobalControls)
                _filter('schedule_id', 'scheduleId', 'startTime', 'Créneau'),
              _filter('student_id', 'studentId', 'student', 'Élève'),
              AppButton(
                  label: 'Consulter / actualiser',
                  onPressed: _busy || _year == null ? null : () => _load()),
            ]),
            const SizedBox(height: 16),
            if (_report != null)
              AppCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    if (!_history) ...[
                      Text(
                          '${_report!['receivedCount']} relevés reçus / ${_report!['expectedCount']} attendus'),
                      ResponsiveDataTable(
                          child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Enseignant')),
                          DataColumn(label: Text('Matière')),
                          DataColumn(label: Text('Classe')),
                          DataColumn(label: Text('État'))
                        ],
                        rows: (_report!['sessions'] as List)
                            .map((row) => DataRow(cells: [
                                  DataCell(Text('${row['teacher'] ?? '—'}')),
                                  DataCell(Text('${row['subject'] ?? '—'}')),
                                  DataCell(Text('${row['class'] ?? '—'}')),
                                  DataCell(Text(row['status'] == 'submitted'
                                      ? 'Reçu'
                                      : row['status'] == 'draft'
                                          ? 'Enregistré'
                                          : 'En attente')),
                                ]))
                            .toList(),
                      )),
                      if (_report!['allReceived'] == true)
                        const Text(
                            'Tous les relevés de présence attendus sont reçus.'),
                    ],
                    if (stats != null)
                      Text(
                          'Présents : ${stats['present']} · Absents : ${stats['absent']} · Justifiés : ${stats['justified']} · Taux : ${stats['attendanceRate'] ?? '—'} %'),
                    const Text('Relevés soumis uniquement'),
                    ResponsiveDataTable(
                        child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Élève')),
                        DataColumn(label: Text('Matière')),
                        DataColumn(label: Text('Enseignant')),
                        DataColumn(label: Text('Statut'))
                      ],
                      rows: (_report!['records'] as List)
                          .map((row) => DataRow(cells: [
                                DataCell(Text('${row['student'] ?? '—'}')),
                                DataCell(Text('${row['subject'] ?? '—'}')),
                                DataCell(Text('${row['teacher'] ?? '—'}')),
                                DataCell(Text(row['status'] == 'present'
                                    ? 'Présent'
                                    : row['status'] == 'absent'
                                        ? 'Absent'
                                        : 'Absent justifié')),
                              ]))
                          .toList(),
                    )),
                  ])),
          ],
        ));
  }
}
