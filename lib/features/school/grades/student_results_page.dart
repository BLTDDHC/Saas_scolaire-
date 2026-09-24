import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../data/datasources/api_client.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/responsive_grid.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/workspace_header.dart';

Widget _planRestriction(BuildContext context, ApiException error) => AppCard(
      title: 'Résultats publiés',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppToast.humanErrorMessage(
            error.message,
            fallback:
                'Cette fonctionnalité est disponible dans un forfait supérieur.',
          )),
          const SizedBox(height: AppSpacing.s3),
          OutlinedButton(
            onPressed: () => AppToast.info(
                context, 'Contactez le Super Admin pour changer de forfait.'),
            child: const Text('Changer de forfait'),
          ),
        ],
      ),
    );

/// Consultation strictement personnelle des résultats issus de PostgreSQL.
class StudentResultsPage extends StatefulWidget {
  const StudentResultsPage({
    super.key,
    this.request,
    this.loader,
    this.embedded = false,
  });

  final Future<Map<String, dynamic>>? request;
  final Future<Map<String, dynamic>> Function()? loader;
  final bool embedded;

  @override
  State<StudentResultsPage> createState() => _StudentResultsPageState();
}

class _StudentResultsPageState extends State<StudentResultsPage> {
  Future<Map<String, dynamic>>? _request;
  String? _periodFilter;
  String? _subjectFilter;
  String? _typeFilter;
  bool _showResults = false;
  String? _resultSelection;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _request ??= widget.request ??
        widget.loader?.call() ??
        context.read<StoreService>().myStudentResultsRemote();
  }

  @override
  void didUpdateWidget(covariant StudentResultsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request != widget.request || oldWidget.loader != widget.loader) {
      _request = widget.request ?? widget.loader?.call();
      _periodFilter = null;
      _subjectFilter = null;
      _typeFilter = null;
      _showResults = false;
      _resultSelection = null;
    }
  }

  void _reload() {
    setState(() {
      _request = widget.loader?.call() ??
          widget.request ??
          context.read<StoreService>().myStudentResultsRemote();
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = FutureBuilder<Map<String, dynamic>>(
          future: _request,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const WorkspaceLoadingState(
                label: 'Chargement de vos résultats…',
              );
            }
            if (snapshot.hasError) {
              if (snapshot.error is ApiException &&
                  (snapshot.error as ApiException).statusCode == 403) {
                return _planRestriction(
                    context, snapshot.error as ApiException);
              }
              return WorkspaceErrorState(
                message: 'Impossible de charger vos résultats.',
                onRetry: _reload,
              );
            }
            final data = snapshot.data ?? const <String, dynamic>{};
            final years = List<Map<String, dynamic>>.from(
              (data['years'] as List? ?? const [])
                  .map((item) => Map<String, dynamic>.from(item as Map)),
            )..sort((left, right) {
                final leftRegistration = Map<String, dynamic>.from(
                    left['registration'] as Map? ?? const {});
                final rightRegistration = Map<String, dynamic>.from(
                    right['registration'] as Map? ?? const {});
                return '${leftRegistration['academicYearName'] ?? left['academicYearId'] ?? ''}'
                    .compareTo(
                        '${rightRegistration['academicYearName'] ?? right['academicYearId'] ?? ''}');
              });
            if (years.isEmpty) {
              return const AppEmptyState(
                iconData: Icons.school_outlined,
                title: 'Aucun résultat disponible.',
                message:
                    'Les résultats apparaîtront après leur validation par l’administration.',
              );
            }
            final periodOptions = <String>{};
            final subjectOptions = <String>{};
            final typeOptions = <String>{};
            for (final year in years) {
              for (final period in (year['periods'] as List? ?? const [])) {
                final row = Map<String, dynamic>.from(period as Map);
                final name = '${row['period'] ?? ''}'.trim();
                if (name.isNotEmpty) periodOptions.add(name);
                for (final subject in (row['subjects'] as List? ?? const [])) {
                  final item = Map<String, dynamic>.from(subject as Map);
                  final subjectName = '${item['subject'] ?? ''}'.trim();
                  if (subjectName.isNotEmpty) subjectOptions.add(subjectName);
                  for (final grade in (item['grades'] as List? ?? const [])) {
                    final value = Map<String, dynamic>.from(grade as Map);
                    final code = '${value['examCode'] ?? value['type'] ?? ''}'.trim();
                    if (code.isNotEmpty) typeOptions.add(code);
                  }
                }
                for (final exam in (row['exams'] as List? ?? const [])) {
                  final item = Map<String, dynamic>.from(exam as Map);
                  final code = '${item['code'] ?? ''}'.trim();
                  if (code.isNotEmpty) typeOptions.add(code);
                }
              }
              for (final note in (year['notes'] as List? ?? const [])) {
                final row = Map<String, dynamic>.from(note as Map);
                final periodName = '${row['period'] ?? ''}'.trim();
                final subjectName = '${row['subject'] ?? ''}'.trim();
                final code =
                    '${row['examCode'] ?? row['evaluationType'] ?? ''}'.trim();
                if (periodName.isNotEmpty) periodOptions.add(periodName);
                if (subjectName.isNotEmpty) subjectOptions.add(subjectName);
                if (code.isNotEmpty) typeOptions.add(code);
              }
            }
            final sortedPeriods = periodOptions.toList()..sort();
            final sortedSubjects = subjectOptions.toList()..sort();
            final sortedTypes = typeOptions.toList()..sort();
            final resultOptions = <Map<String, String>>[];
            for (final year in years) {
              for (final rawPeriod in (year['periods'] as List? ?? const [])) {
                final period =
                    Map<String, dynamic>.from(rawPeriod as Map);
                final periodId = '${period['periodId'] ?? ''}';
                final periodName = '${period['period'] ?? ''}'.trim();
                if (periodId.isEmpty || periodName.isEmpty) continue;
                resultOptions.add({
                  'value': 'period:$periodId',
                  'label': periodName,
                  'periodId': periodId,
                  'eventCode': '',
                });
                for (final rawExam in (period['exams'] as List? ?? const [])) {
                  final exam = Map<String, dynamic>.from(rawExam as Map);
                  final code = '${exam['code'] ?? ''}'.trim();
                  final name = '${exam['name'] ?? ''}'.trim();
                  if (code.isEmpty || name.isEmpty) continue;
                  resultOptions.add({
                    'value': 'event:$periodId:$code',
                    'label': '$periodName · $name',
                    'periodId': periodId,
                    'eventCode': code,
                  });
                }
              }
            }
            final seenResultValues = <String>{};
            resultOptions.retainWhere(
                (item) => seenResultValues.add(item['value']!));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ('${data['studentName'] ?? ''}'.isNotEmpty) ...[
                  Text(
                    '${data['studentName']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.s3),
                ],
                AppCard(
                  title: _showResults ? 'Résultats' : 'Notes',
                  subtitle: _showResults
                      ? 'Résultats officiels : choisissez une période ou une évaluation spécifique.'
                      : 'Notes réellement soumises ou validées par les enseignants.',
                  headerAction: FilledButton.tonalIcon(
                    key: Key(_showResults
                        ? 'student-show-notes'
                        : 'student-show-results'),
                    onPressed: () => setState(() {
                      _showResults = !_showResults;
                      _resultSelection = null;
                      _periodFilter = null;
                      _subjectFilter = null;
                      _typeFilter = null;
                    }),
                    icon: Icon(_showResults
                        ? Icons.edit_note_outlined
                        : Icons.insights_outlined),
                    label:
                        Text(_showResults ? 'Voir les notes' : 'Voir les résultats'),
                  ),
                  child: _showResults
                      ? DropdownButtonFormField<String>(
                          key: const Key('student-result-selection'),
                          isExpanded: true,
                          initialValue: _resultSelection,
                          decoration: const InputDecoration(
                            labelText: 'Période / résultat',
                            hintText: 'Sélectionner un résultat',
                          ),
                          items: resultOptions
                              .map((item) => DropdownMenuItem<String>(
                                    value: item['value'],
                                    child: Text(
                                      item['label']!,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _resultSelection = value),
                        )
                      : const Text(
                          'Utilisez les filtres ci-dessous pour retrouver une note par période, matière ou type d’évaluation.',
                        ),
                ),
                const SizedBox(height: AppSpacing.s4),
                if (!_showResults &&
                    (sortedPeriods.isNotEmpty ||
                        sortedSubjects.isNotEmpty ||
                        sortedTypes.isNotEmpty)) ...[
                  AppCard(
                    title: 'Filtres des notes',
                    child: Wrap(
                      spacing: AppSpacing.s3,
                      runSpacing: AppSpacing.s3,
                      children: [
                        SizedBox(
                          width: 230,
                          child: DropdownButtonFormField<String?>(
                            isExpanded: true,
                            initialValue: _periodFilter,
                            decoration:
                                const InputDecoration(labelText: 'Période'),
                            items: [
                              const DropdownMenuItem<String?>(
                                  value: null, child: Text('Toutes')),
                              ...sortedPeriods.map((value) =>
                                  DropdownMenuItem<String?>(
                                      value: value, child: Text(value))),
                            ],
                            onChanged: (value) =>
                                setState(() => _periodFilter = value),
                          ),
                        ),
                        SizedBox(
                          width: 230,
                          child: DropdownButtonFormField<String?>(
                            isExpanded: true,
                            initialValue: _subjectFilter,
                            decoration:
                                const InputDecoration(labelText: 'Matière'),
                            items: [
                              const DropdownMenuItem<String?>(
                                  value: null, child: Text('Toutes')),
                              ...sortedSubjects.map((value) =>
                                  DropdownMenuItem<String?>(
                                      value: value, child: Text(value))),
                            ],
                            onChanged: (value) =>
                                setState(() => _subjectFilter = value),
                          ),
                        ),
                        SizedBox(
                          width: 230,
                          child: DropdownButtonFormField<String?>(
                            isExpanded: true,
                            initialValue: _typeFilter,
                            decoration: const InputDecoration(
                                labelText: 'Type d’évaluation'),
                            items: [
                              const DropdownMenuItem<String?>(
                                  value: null, child: Text('Tous')),
                              ...sortedTypes.map((value) =>
                                  DropdownMenuItem<String?>(
                                      value: value,
                                      child:
                                          Text(_evaluationTypeLabel(value)))),
                            ],
                            onChanged: (value) =>
                                setState(() => _typeFilter = value),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                ],
                if (_showResults && _resultSelection == null)
                  const AppEmptyState(
                    iconData: Icons.fact_check_outlined,
                    title: 'Sélectionnez un résultat.',
                    message:
                        'Seul le résultat choisi sera affiché : trimestre, mois ou évaluation spécifique.',
                  )
                else
                  ...years.map((year) => _yearCard(
                        year,
                        resultOptions: resultOptions,
                      )),
              ],
            );
          },
        );
    if (widget.embedded) return content;
    return WorkspacePage(
      title: _showResults ? 'Résultats' : 'Notes',
      subtitle: _showResults
          ? 'Consultez un résultat officiel à la fois.'
          : 'Notes soumises par vos enseignants.',
      actions: [
        IconButton.filledTonal(
          tooltip: 'Actualiser les résultats',
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      children: [content],
    );
  }

  Widget _yearCard(
    Map<String, dynamic> year, {
    required List<Map<String, String>> resultOptions,
  }) {
    final registration = Map<String, dynamic>.from(
      year['registration'] as Map? ?? const <String, dynamic>{},
    );
    var periods = List<Map<String, dynamic>>.from(
      (year['periods'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    periods.sort((left, right) {
      final byOrder = ((left['periodOrder'] as num?)?.toInt() ?? 0)
          .compareTo((right['periodOrder'] as num?)?.toInt() ?? 0);
      if (byOrder != 0) return byOrder;
      return '${left['period']}'.compareTo('${right['period']}');
    });
    if (_periodFilter != null) {
      periods = periods
          .where((item) => item['period']?.toString() == _periodFilter)
          .toList();
    }
    var notes = List<Map<String, dynamic>>.from(
      (year['notes'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    notes = notes.where((note) {
      if (_periodFilter != null &&
          note['period']?.toString() != _periodFilter) {
        return false;
      }
      if (_subjectFilter != null &&
          note['subject']?.toString() != _subjectFilter) {
        return false;
      }
      final type = '${note['examCode'] ?? note['evaluationType'] ?? ''}';
      if (_typeFilter != null && type != _typeFilter) return false;
      return true;
    }).toList()
      ..sort((left, right) {
        final byPeriod = ((left['periodOrder'] as num?)?.toInt() ?? 0)
            .compareTo((right['periodOrder'] as num?)?.toInt() ?? 0);
        if (byPeriod != 0) return byPeriod;
        final bySubject =
            '${left['subject']}'.compareTo('${right['subject']}');
        if (bySubject != 0) return bySubject;
        final byType =
            '${left['examCode'] ?? left['evaluationType'] ?? ''}'
                .compareTo('${right['examCode'] ?? right['evaluationType'] ?? ''}');
        if (byType != 0) return byType;
        return '${left['date']}'.compareTo('${right['date']}');
      });
    Map<String, String>? selectedResult;
    if (_showResults && _resultSelection != null) {
      selectedResult = resultOptions
          .where((item) => item['value'] == _resultSelection)
          .firstOrNull;
      if (selectedResult != null) {
        periods = periods
            .where((item) =>
                '${item['periodId']}' == selectedResult!['periodId'])
            .toList();
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: AppCard(
        title: '${registration['academicYearName'] ?? 'Année scolaire'}',
        subtitle: [
          registration['className'],
          registration['cycle'],
          registration['level'],
          registration['series'],
        ].where((value) => value != null && '$value'.isNotEmpty).join(' · '),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_showResults) ...[
              if (notes.isNotEmpty)
                _submittedNotesTable(notes)
              else
                const Text(
                    'Aucune note ne correspond aux filtres sélectionnés.'),
            ] else if (selectedResult != null && periods.isNotEmpty) ...[
              ...periods.map((period) => _periodCard(
                    period,
                    registration,
                    selectedEventCode: selectedResult!['eventCode']!.isEmpty
                        ? null
                        : selectedResult['eventCode'],
                    eventOnly: selectedResult['eventCode']!.isNotEmpty,
                  )),
            ] else
              const Text('Aucun résultat officiel pour cette sélection.'),
          ],
        ),
      ),
    );
  }

  Widget _periodCard(
    Map<String, dynamic> period,
    Map<String, dynamic> registration, {
    String? selectedEventCode,
    bool eventOnly = false,
  }) {
    var subjects = List<Map<String, dynamic>>.from(
      (period['subjects'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    if (subjects.isEmpty) {
      final grades = List<Map<String, dynamic>>.from(
        (period['grades'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map)),
      );
      final grouped = <String, Map<String, dynamic>>{};
      for (final grade in grades) {
        final name = '${grade['subject'] ?? '—'}';
        grouped.putIfAbsent(name, () => {'subject': name, 'grades': []});
        (grouped[name]!['grades'] as List).add(grade);
      }
      subjects = grouped.values.toList();
    }
    if (_subjectFilter != null) {
      subjects = subjects
          .where((item) => item['subject']?.toString() == _subjectFilter)
          .toList();
    }
    if (_typeFilter != null &&
        const {'devoir', 'composition'}.contains(_typeFilter)) {
      subjects = subjects.where((subject) {
        final grades = (subject['grades'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map));
        return grades.any((grade) =>
            '${grade['examCode'] ?? grade['type'] ?? ''}' == _typeFilter);
      }).toList();
    }
    var exams = List<Map<String, dynamic>>.from(
      (period['exams'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    if (selectedEventCode != null) {
      exams = exams
          .where((item) => item['code']?.toString() == selectedEventCode)
          .toList();
    } else if (_typeFilter != null) {
      exams = exams
          .where((item) => item['code']?.toString() == _typeFilter)
          .toList();
    }
    final ranking = List<Map<String, dynamic>>.from(
      (period['ranking'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    final rankingCount = (period['rankingCount'] as num?)?.toInt() ??
        ranking.length;
    return Material(
      type: MaterialType.transparency,
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('${period['period'] ?? 'Période'}'),
        subtitle: Text('Moyenne : ${period['average'] ?? '—'} / '
            '${period['averageScale'] ?? 20} · Rang : ${period['rank'] ?? '—'} · '
            'Mention : ${period['mention'] ?? _mention(period)}'),
        children: [
          if (!eventOnly) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s3),
            child: ResponsiveGrid(
              desktopColumns: 3,
              tabletColumns: 3,
              children: [
                _resultMetric('Moyenne générale',
                    '${period['average'] ?? '—'} / ${period['averageScale'] ?? 20}'),
                _resultMetric('Rang', '${period['rank'] ?? '—'}'),
                _resultMetric(
                    'Mention', '${period['mention'] ?? _mention(period)}'),
              ],
            ),
          ),
          if (subjects.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.s3),
                child: Text('Aucune note publiée.'),
              ),
            )
          else
            ResponsiveDataTable(
              child: DataTable(
                columns: [
                  const DataColumn(label: Text('Matière')),
                  const DataColumn(label: Text('Devoir 1')),
                  const DataColumn(label: Text('Devoir 2')),
                  const DataColumn(label: Text('Composition')),
                  const DataColumn(label: Text('MC')),
                  const DataColumn(label: Text('Moyenne')),
                  if (_isLycee(registration))
                    const DataColumn(label: Text('Coefficient')),
                  if (_isLycee(registration))
                    const DataColumn(label: Text('Point')),
                ],
                rows: subjects
                    .map(
                      (subject) => DataRow(cells: [
                        DataCell(Text('${subject['subject'] ?? '—'}')),
                        DataCell(Text(_ordinaryGrade(subject, 'devoir_1'))),
                        DataCell(Text(_ordinaryGrade(subject, 'devoir_2'))),
                        DataCell(Text(_ordinaryGrade(subject, 'composition'))),
                        DataCell(Text('${subject['mc'] ?? '—'}')),
                        DataCell(Text('${subject['average'] ?? '—'}')),
                        if (_isLycee(registration))
                          DataCell(Text('${subject['coefficient'] ?? '—'}')),
                        if (_isLycee(registration))
                          DataCell(Text('${subject['point'] ?? '—'}')),
                      ]),
                    )
                    .toList(),
              ),
            ),
          ],
          if (eventOnly) ...exams.map((exam) => _examCard(exam, registration)),
          if (eventOnly && exams.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.s3),
                child: Text('Aucun résultat officiel pour cette évaluation.'),
              ),
            ),
          if (!eventOnly && rankingCount > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s3),
                child: Text(
                  'Classement de la classe : $rankingCount élève(s). '
                  'Les notes individuelles des autres élèves ne sont pas exposées.',
                ),
              ),
            ),
        ],
      ),
    );
  }


  String _evaluationTypeLabel(String value) => const {
        'devoir': 'Devoir',
        'devoir_1': 'Devoir 1',
        'devoir_2': 'Devoir 2',
        'composition': 'Composition',
        'cepe_test': 'CEPE Test',
        'cepe_blanc': 'CEPE Blanc',
        'bepc_test': 'BEPC Test',
        'bepc_blanc': 'BEPC Blanc',
        'bac_test': 'BAC Test',
        'bac_blanc': 'BAC Blanc',
        'devoir_departemental': 'Devoir départemental',
        'test': 'Test',
        'exam': 'Examen',
        'exam_blanc': 'Examen blanc',
      }[value] ??
      value;

  Widget _submittedNotesTable(List<Map<String, dynamic>> notes) => AppCard(
        title: 'Notes récemment soumises',
        subtitle:
            'Ces notes proviennent directement des relevés soumis/validés par les enseignants.',
        child: ResponsiveDataTable(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Période')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Matière')),
              DataColumn(label: Text('Évaluation')),
              DataColumn(label: Text('Note')),
            ],
            rows: notes.map((note) {
              final presence = '${note['presence'] ?? 'not_recorded'}';
              final value = switch (presence) {
                'absent' => 'Absent',
                'present' =>
                  '${note['value'] ?? '—'} / ${note['maxValue'] ?? '—'}',
                _ => 'Non noté',
              };
              return DataRow(cells: [
                DataCell(Text('${note['period'] ?? '—'}')),
                DataCell(Text('${note['date'] ?? '—'}')),
                DataCell(Text('${note['subject'] ?? '—'}')),
                DataCell(Text('${note['evaluation'] ?? '—'}')),
                DataCell(Text(value)),
              ]);
            }).toList(),
          ),
        ),
      );

  bool _isLycee(Map<String, dynamic> registration) =>
      '${registration['cycleCode'] ?? registration['cycle']}'
          .toUpperCase()
          .contains('LYC');

  String _mention(Map<String, dynamic> period) {
    final average = (period['average'] as num?)?.toDouble();
    final scale = (period['averageScale'] as num?)?.toDouble() ?? 20;
    if (average == null || scale <= 0) return '—';
    final ratio = average / scale;
    if (ratio >= .8) return 'Très bien';
    if (ratio >= .7) return 'Bien';
    if (ratio >= .6) return 'Assez bien';
    if (ratio >= .5) return 'Passable';
    return 'Insuffisant';
  }

  Widget _resultMetric(String title, String value) => AppCard(
        title: title,
        child: Text(value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      );

  String _ordinaryGrade(Map<String, dynamic> subject, String event) {
    final grades = List<Map<String, dynamic>>.from(
      (subject['grades'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    for (final grade in grades) {
      final label = '${grade['evaluation'] ?? ''}'.toLowerCase();
      final type = '${grade['type'] ?? ''}'.toLowerCase();
      final matches = event == 'composition'
          ? type == 'composition' || label.contains('composition')
          : event == 'devoir_1'
              ? label.contains('devoir 1') || label.contains('devoir n°1')
              : label.contains('devoir 2') || label.contains('devoir n°2');
      if (matches) {
        return '${grade['value'] ?? '—'} / ${grade['maxValue'] ?? '—'}';
      }
    }
    return '—';
  }

  Widget _examCard(
      Map<String, dynamic> exam, Map<String, dynamic> registration) {
    final subjects = List<Map<String, dynamic>>.from(
      (exam['subjects'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    return AppCard(
      title: '${exam['name'] ?? 'Examen'}',
      subtitle:
          'Moyenne : ${exam['average'] ?? '—'} · Rang : ${exam['rank'] ?? '—'}',
      child: ResponsiveDataTable(
        child: DataTable(
          columns: [
            const DataColumn(label: Text('Matière')),
            const DataColumn(label: Text('Note')),
            if (_isLycee(registration))
              const DataColumn(label: Text('Coefficient')),
            if (_isLycee(registration)) const DataColumn(label: Text('Point')),
          ],
          rows: subjects.map((subject) {
            final grades = List<Map<String, dynamic>>.from(
              (subject['grades'] as List? ?? const [])
                  .map((item) => Map<String, dynamic>.from(item as Map)),
            );
            final grade =
                grades.isEmpty ? const <String, dynamic>{} : grades.first;
            return DataRow(cells: [
              DataCell(Text('${subject['subject'] ?? '—'}')),
              DataCell(Text(
                  '${grade['value'] ?? subject['average'] ?? '—'}${grade['maxValue'] == null ? '' : ' / ${grade['maxValue']}'}')),
              if (_isLycee(registration))
                DataCell(Text('${subject['coefficient'] ?? '—'}')),
              if (_isLycee(registration))
                DataCell(Text('${subject['point'] ?? '—'}')),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}


/// Consultation parent limitée aux enfants explicitement liés à son compte.
class ParentResultsPage extends StatefulWidget {
  const ParentResultsPage({super.key});

  @override
  State<ParentResultsPage> createState() => _ParentResultsPageState();
}

class _ParentResultsPageState extends State<ParentResultsPage> {
  Future<List<Map<String, dynamic>>>? _childrenRequest;
  Future<Map<String, dynamic>>? _resultRequest;
  String? _childId;
  String? _yearId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _childrenRequest ??=
        context.read<StoreService>().myChildrenForResultsRemote();
  }

  void _selectChild(Map<String, dynamic> child, {String? yearId}) {
    final store = context.read<StoreService>();
    final years = List<Map<String, dynamic>>.from(
        (child['years'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map)));
    final selectedYear = store.getSelectedAcademicYearId();
    final requestedYearId = yearId ?? selectedYear;
    final effectiveYearId = years.any((year) => year['id'] == requestedYearId)
        ? requestedYearId
        : (years.isEmpty ? null : '${years.first['id']}');
    final childId = '${child['id']}';
    final request = effectiveYearId == null
        ? null
        : store.studentResultsRemote(childId, effectiveYearId).then((result) => {
              'studentName': child['fullName'],
              'years': [result],
            });
    setState(() {
      _childId = childId;
      _yearId = effectiveYearId;
      _resultRequest = request;
    });
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
        title: 'Notes des enfants',
        subtitle:
            'Notes soumises et résultats officiels de l’enfant sélectionné, sans mélange.',
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _childrenRequest,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const WorkspaceLoadingState(
                    label: 'Chargement des enfants…');
              }
              final children = snapshot.data ?? const <Map<String, dynamic>>[];
              if (snapshot.error is ApiException &&
                  (snapshot.error as ApiException).statusCode == 403) {
                return _planRestriction(
                    context, snapshot.error as ApiException);
              }
              if (snapshot.hasError || children.isEmpty) {
                return const AppEmptyState(
                  iconData: Icons.family_restroom_outlined,
                  title: 'Aucun enfant accessible.',
                  message:
                      'L’administration doit rattacher votre compte parent à un élève.',
                );
              }
              final selected =
                  children.where((child) => child['id'] == _childId).toList();
              final active = selected.isEmpty ? children.first : selected.first;
              final years = List<Map<String, dynamic>>.from(
                (active['years'] as List? ?? const [])
                    .map((item) => Map<String, dynamic>.from(item as Map)),
              );
              if (_childId == null) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _selectChild(active));
              }
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      key: const Key('parent-child-selector'),
                      isExpanded: true,
                      value: '${active['id']}',
                      decoration: const InputDecoration(labelText: 'Enfant'),
                      items: children
                          .map((child) => DropdownMenuItem(
                              value: '${child['id']}',
                              child: Text('${child['fullName']}',
                                  overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (id) => _selectChild(
                          children.firstWhere((child) => child['id'] == id)),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    if (years.length > 1) ...[
                      DropdownButtonFormField<String>(
                        key: const Key('parent-year-selector'),
                        isExpanded: true,
                        value: years.any((year) => '${year['id']}' == _yearId)
                            ? _yearId
                            : '${years.first['id']}',
                        decoration:
                            const InputDecoration(labelText: 'Année scolaire'),
                        items: years
                            .map((year) => DropdownMenuItem(
                                  value: '${year['id']}',
                                  child: Text(
                                    '${year['name'] ?? year['className'] ?? 'Année scolaire'}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (id) {
                          if (id != null) _selectChild(active, yearId: id);
                        },
                      ),
                      const SizedBox(height: AppSpacing.s4),
                    ],
                    if (_resultRequest != null)
                      StudentResultsPage(
                        key: ValueKey('parent-results-$_childId-$_yearId'),
                        request: _resultRequest,
                        loader: _childId == null || _yearId == null
                            ? null
                            : () => context
                                .read<StoreService>()
                                .studentResultsRemote(_childId!, _yearId!)
                                .then((result) => {
                                      'studentName': active['fullName'],
                                      'years': [result],
                                    }),
                        embedded: true,
                      ),
                  ]);
            },
          ),
        ],
      );
}
