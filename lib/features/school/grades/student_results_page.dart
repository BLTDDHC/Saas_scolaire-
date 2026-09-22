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
            );
            if (years.isEmpty) {
              return const AppEmptyState(
                iconData: Icons.school_outlined,
                title: 'Aucun résultat disponible.',
                message:
                    'Les résultats apparaîtront après leur validation par l’administration.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ('${data['studentName'] ?? ''}'.isNotEmpty) ...[
                  Text(
                    '${data['studentName']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.s4),
                ],
                ...years.map(_yearCard),
              ],
            );
          },
        );
    if (widget.embedded) return content;
    return WorkspacePage(
      title: 'Notes et résultats',
      subtitle: 'Vos notes, moyennes et classements officiellement publiés',
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

  Widget _yearCard(Map<String, dynamic> year) {
    final registration = Map<String, dynamic>.from(
      year['registration'] as Map? ?? const <String, dynamic>{},
    );
    final periods = List<Map<String, dynamic>>.from(
      (year['periods'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
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
        child: periods.isEmpty
            ? const Text('Aucune période avec des résultats validés.')
            : Column(
                children: periods
                    .map((period) => _periodCard(period, registration))
                    .toList()),
      ),
    );
  }

  Widget _periodCard(
      Map<String, dynamic> period, Map<String, dynamic> registration) {
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
    final exams = List<Map<String, dynamic>>.from(
      (period['exams'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
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
          ...exams.map((exam) => _examCard(exam, registration)),
          if (rankingCount > 0)
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
        subtitle: 'Résultats publiés des enfants rattachés à votre compte',
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
