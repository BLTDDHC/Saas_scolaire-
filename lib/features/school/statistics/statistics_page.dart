import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/pdf_download.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/responsive_grid.dart';
import '../../../shared/widgets/workspace_header.dart';
import '../documents/document_report_pdf.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  String? _cycleId;
  String? _levelId;
  String? _classId;
  String? _periodId;
  String? _subjectId;
  String? _loadedYearId;
  Future<Map<String, dynamic>>? _request;
  Map<String, dynamic>? _snapshot;
  List<Map<String, dynamic>> _periods = const [];
  bool _filtersDirty = false;
  bool _pdfBusy = false;

  void _load(StoreService store) {
    final yearId = store.getSelectedAcademicYearId();
    _loadedYearId = yearId;
    final request = store.getRemoteStatistics(
      academicYearId: yearId,
      cycle: _cycleId,
      levelId: _levelId,
      classId: _classId,
      periodId: _periodId,
      subjectId: _subjectId,
    );
    _request = request;
    _snapshot = null;
    request.then((value) {
      if (!mounted || !identical(_request, request)) return;
      setState(() => _snapshot = value);
    }).catchError((_) {
      // The async view owns the visible error state. The PDF remains disabled.
    });
    _filtersDirty = false;
  }

  void _applyFilters(StoreService store) {
    setState(() => _load(store));
  }

  String? _selectedName<T>(Iterable<T> values, String? id,
      String Function(T item) idOf, String Function(T item) nameOf) {
    if (id == null) return null;
    for (final item in values) {
      if (idOf(item) == id) return nameOf(item);
    }
    return null;
  }

  Future<void> _downloadPdf(StoreService store) async {
    final snapshot = _snapshot;
    final school = store.getCurrentSchool();
    final year = store.getSelectedAcademicYear();
    if (snapshot == null || school == null || year == null || _pdfBusy) return;
    setState(() => _pdfBusy = true);
    try {
      final report = statisticsPdfReport(
        statistics: snapshot,
        schoolName: school.name,
        schoolCity: school.city,
        academicYear: year.name,
        cycleName: _selectedName(store.getSchoolCycles(), _cycleId,
            (item) => item.id, (item) => item.name),
        levelName: _selectedName(store.getSchoolLevels(), _levelId,
            (item) => item.id, (item) => item.name),
        className: _selectedName(store.getClasses(), _classId,
            (item) => item.id, (item) => item.name),
        periodName: _selectedName(_periods, _periodId,
            (item) => '${item['id']}', (item) => '${item['name']}'),
        subjectName: _selectedName(store.getSubjects(), _subjectId,
            (item) => item.id, (item) => item.name),
      );
      final pdf = await buildSchoolReportPdf(report);
      await downloadPdfFile(await pdf.save(), schoolReportFileName(report));
      if (mounted) {
        AppToast.success(context,
            'Le PDF reprend exactement les analyses actuellement affichées.');
      }
    } catch (_) {
      if (mounted) {
        AppToast.error(context, 'Impossible de générer le PDF statistique.');
      }
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<void> _loadPeriods(StoreService store, String? yearId) async {
    if (yearId == null) return;
    try {
      final periods = await store.academicPeriodsRemote(yearId);
      if (!mounted || yearId != _loadedYearId) return;
      setState(() {
        _periods = periods
            .where((item) =>
                item['periodType'] == 'trimester' &&
                item['status'] != 'archived')
            .toList();
      });
    } catch (_) {
      // Statistics remain usable without the optional period selector.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.watch<StoreService>();
    final yearId = store.getSelectedAcademicYearId();
    if (_request == null || yearId != _loadedYearId) {
      _periodId = null;
      _load(store);
      _loadPeriods(store, yearId);
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
    final classes = store
        .getClassesByYear(store.getSelectedAcademicYearId())
        .where((item) =>
            (_cycleId == null || item.cycleId == _cycleId) &&
            (_levelId == null ||
                item.levelId == _levelId ||
                item.structuredLevelId == _levelId))
        .toList();
    final subjects =
        store.getSubjects().where((item) => item.status == 'active').toList();

    return WorkspacePage(
      title: 'Statistiques & analyses',
      subtitle:
          'Indicateurs construits à partir des derniers résultats trimestriels officiels',
      actions: [
        Wrap(
          spacing: AppSpacing.s3,
          runSpacing: AppSpacing.s3,
          children: [
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String?>(
                key: ValueKey(
                    'statistics-cycle-${_loadedYearId ?? ''}-${_cycleId ?? 'all'}'),
                initialValue: _cycleId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cycle'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Tous les cycles'),
                  ),
                  ...cycles.map(
                    (cycle) => DropdownMenuItem(
                      value: cycle.id,
                      child: Text(cycle.name, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _cycleId = value;
                    _levelId = null;
                    _classId = null;
                    _filtersDirty = true;
                  });
                },
              ),
            ),
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String?>(
                key: ValueKey(
                    'statistics-level-${_cycleId ?? 'all'}-${_levelId ?? 'all'}'),
                initialValue: _levelId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Niveau'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Tous les niveaux'),
                  ),
                  ...levels.map((level) => DropdownMenuItem(
                        value: level.id,
                        child:
                            Text(level.name, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (value) {
                  setState(() {
                    _levelId = value;
                    _classId = null;
                    _filtersDirty = true;
                  });
                },
              ),
            ),
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String?>(
                key: ValueKey(
                    'statistics-class-${_cycleId ?? 'all'}-${_levelId ?? 'all'}-${_classId ?? 'all'}'),
                initialValue: _classId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Classe'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Toutes les classes'),
                  ),
                  ...classes.map((item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(item.name, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (value) {
                  setState(() {
                    _classId = value;
                    _filtersDirty = true;
                  });
                },
              ),
            ),
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String?>(
                key: ValueKey(
                    'statistics-period-${_loadedYearId ?? ''}-${_periodId ?? 'all'}'),
                initialValue: _periodId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Période'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Dernière période officielle')),
                  ..._periods.map((item) => DropdownMenuItem<String?>(
                        value: '${item['id']}',
                        child: Text('${item['name']}',
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (value) => setState(() {
                  _periodId = value;
                  _filtersDirty = true;
                }),
              ),
            ),
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String?>(
                key: ValueKey(
                    'statistics-subject-${_loadedYearId ?? ''}-${_subjectId ?? 'all'}'),
                initialValue: _subjectId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Matière'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Toutes les matières')),
                  ...subjects.map((item) => DropdownMenuItem<String?>(
                        value: item.id,
                        child: Text(item.name, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (value) => setState(() {
                  _subjectId = value;
                  _filtersDirty = true;
                }),
              ),
            ),
            FilledButton.icon(
              onPressed: _filtersDirty ? () => _applyFilters(store) : null,
              icon: const Icon(Icons.filter_alt_outlined),
              label: const Text('Appliquer les filtres'),
            ),
            OutlinedButton.icon(
              key: const Key('statistics-download-pdf'),
              onPressed: _snapshot == null || _pdfBusy
                  ? null
                  : () => _downloadPdf(store),
              icon: _pdfBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_pdfBusy ? 'Génération…' : 'Télécharger le PDF'),
            ),
          ],
        ),
      ],
      children: [
        StatisticsSnapshotView(request: _request!),
      ],
    );
  }
}

/// Owns the async transition between two filtered snapshots. FutureBuilder can
/// retain the previous value when its future changes; checking the connection
/// state first guarantees that stale KPI values are never shown as if they
/// belonged to the newly selected filters.
class StatisticsSnapshotView extends StatelessWidget {
  const StatisticsSnapshotView({super.key, required this.request});

  final Future<Map<String, dynamic>> request;

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: request,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const WorkspaceLoadingState(
              label: 'Mise à jour des analyses…',
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const WorkspaceErrorState(
              message: 'Impossible de charger les statistiques.',
            );
          }
          return _StatisticsContent(data: snapshot.data!);
        },
      );
}

class _StatisticsContent extends StatelessWidget {
  const _StatisticsContent({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final top = List<Map<String, dynamic>>.from(
      (data['top10'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    final byClass = List<Map<String, dynamic>>.from(
      (data['byClass'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    final byCycle = List<Map<String, dynamic>>.from(
      (data['byCycle'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    final bySubject = List<Map<String, dynamic>>.from(
      (data['bySubject'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    final distribution = Map<String, dynamic>.from(
      data['distribution'] as Map? ?? const {},
    );
    final insights = List<Map<String, dynamic>>.from(
      (data['insights'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    final alerts = List<Map<String, dynamic>>.from(
      (data['alerts'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    final evolution = List<Map<String, dynamic>>.from(
      (data['evolution'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    final monthlyEvolution = List<Map<String, dynamic>>.from(
      (data['monthlyEvolution'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    final attendanceByClass = List<Map<String, dynamic>>.from(
      (data['attendanceByClass'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    final gradeCompletion = List<Map<String, dynamic>>.from(
      (data['gradeCompletion'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    final finance = data['finance'] is Map
        ? Map<String, dynamic>.from(data['finance'] as Map)
        : null;
    final decisions = Map<String, dynamic>.from(
        data['decisions'] as Map? ?? const <String, dynamic>{});
    final teacherStatistics = Map<String, dynamic>.from(
        data['teacherStatistics'] as Map? ?? const <String, dynamic>{});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveGrid(
          key: const Key('statistics-kpi-grid'),
          desktopColumns: 4,
          tabletColumns: 2,
          mobileColumns: 1,
          children: [
            _Metric(
              label: 'Élèves',
              value: '${data['studentCount'] ?? 0}',
              icon: Icons.school_outlined,
              color: AppColors.info600,
            ),
            _Metric(
              label: 'Résultats officiels analysés',
              value: '${data['officialStudentCount'] ?? 0}',
              icon: Icons.verified_outlined,
              color: AppColors.success600,
            ),
            _Metric(
              label: 'Moyenne générale',
              value: data['overallAverage'] == null
                  ? 'Non calculée'
                  : '${data['overallAverage']} / 20',
              icon: Icons.analytics_outlined,
              color: AppColors.primary600,
            ),
            _Metric(
              label: 'Taux de présence',
              value: data['attendanceRate'] == null
                  ? 'Non calculé'
                  : '${data['attendanceRate']} %',
              icon: Icons.how_to_reg_outlined,
              color: AppColors.success600,
            ),
            _Metric(
              label: 'Enseignants actifs du périmètre',
              value: '${data['teacherCount'] ?? 0}',
              icon: Icons.co_present_outlined,
              color: AppColors.info600,
            ),
            _Metric(
              label: 'Classes actives',
              value: '${data['classCount'] ?? 0}',
              icon: Icons.meeting_room_outlined,
              color: AppColors.primary600,
            ),
            _Metric(
              label: 'Créneaux de cours planifiés',
              value: '${teacherStatistics['plannedCourses'] ?? 0}',
              icon: Icons.calendar_month_outlined,
              color: AppColors.info600,
            ),
            _Metric(
              label: 'Appels de cours verrouillés',
              value: '${teacherStatistics['completedCourses'] ?? 0}',
              icon: Icons.fact_check_outlined,
              color: AppColors.success600,
            ),
            _Metric(
              label: 'Taux de réussite',
              value: data['successRate'] == null
                  ? 'Non calculé'
                  : '${data['successRate']} %',
              icon: Icons.trending_up_outlined,
              color: AppColors.success600,
            ),
            _Metric(
              label: 'Taux d’échec',
              value: data['failureRate'] == null
                  ? 'Non calculé'
                  : '${data['failureRate']} %',
              icon: Icons.trending_down_outlined,
              color: AppColors.danger600,
            ),
            _Metric(
              label: 'Moyenne maximale',
              value: data['highestAverage'] == null
                  ? 'Non calculée'
                  : '${data['highestAverage']} / 20',
              icon: Icons.arrow_upward_rounded,
              color: AppColors.success600,
            ),
            _Metric(
              label: 'Moyenne minimale',
              value: data['lowestAverage'] == null
                  ? 'Non calculée'
                  : '${data['lowestAverage']} / 20',
              icon: Icons.arrow_downward_rounded,
              color: AppColors.warning600,
            ),
            _Metric(
              label: 'Médiane',
              value: data['medianAverage'] == null
                  ? 'Non calculée'
                  : '${data['medianAverage']} / 20',
              icon: Icons.horizontal_rule_rounded,
              color: AppColors.info600,
            ),
            _Metric(
              label: 'Écart-type',
              value: data['standardDeviation'] == null
                  ? 'Non calculé'
                  : '${data['standardDeviation']}',
              icon: Icons.scatter_plot_outlined,
              color: AppColors.secondary600,
            ),
          ],
        ),
        if (evolution.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s6),
          _LineChartCard(
            key: const Key('statistics-evolution-chart'),
            title: 'Évolution trimestrielle',
            subtitle:
                'T1 → T2 → T3, uniquement à partir des résultats officiels',
            rows: evolution,
            labelKey: 'period',
            valueKey: 'average20',
          ),
        ],
        if (monthlyEvolution.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s6),
          _AverageBarsCard(
            title: 'Évolution mensuelle des notes publiées',
            subtitle:
                'Moyenne descriptive normalisée sur 20, distincte de la moyenne trimestrielle officielle',
            rows: monthlyEvolution,
            labelKey: 'month',
            valueKey: 'average20',
          ),
        ],
        if ((decisions['total'] as num? ?? 0) > 0) ...[
          const SizedBox(height: AppSpacing.s6),
          const WorkspaceSectionHeader(
            title: 'Décisions annuelles officielles',
            subtitle: 'Distinctes de la répartition descriptive des moyennes',
          ),
          ResponsiveGrid(
            desktopColumns: 3,
            tabletColumns: 3,
            mobileColumns: 1,
            children: [
              _Metric(
                  label: 'Admis',
                  value: '${decisions['admitted'] ?? 0}',
                  icon: Icons.check_circle_outline,
                  color: AppColors.success600),
              _Metric(
                  label: 'Recalés',
                  value: '${decisions['failed'] ?? 0}',
                  icon: Icons.replay_circle_filled_outlined,
                  color: AppColors.warning600),
              _Metric(
                  label: 'Exclus',
                  value: '${decisions['excluded'] ?? 0}',
                  icon: Icons.block_outlined,
                  color: AppColors.danger600),
            ],
          ),
        ],
        if (insights.isNotEmpty || alerts.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s6),
          ResponsiveGrid(
            desktopColumns: 2,
            tabletColumns: 1,
            mobileColumns: 1,
            children: [
              AppCard(
                title: 'Ce qu’il faut retenir',
                child: insights.isEmpty
                    ? const Text('Aucun insight disponible pour ce périmètre.')
                    : Column(
                        children: insights
                            .map((item) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                      Icons.auto_awesome_outlined,
                                      color: AppColors.primary600),
                                  title: Text('${item['title'] ?? 'Analyse'}'),
                                  subtitle: Text('${item['message'] ?? ''}'),
                                ))
                            .toList(),
                      ),
              ),
              AppCard(
                title: 'Points d’attention',
                child: alerts.isEmpty
                    ? const Text(
                        'Aucune alerte calculée sur les données officielles.')
                    : Column(
                        children: alerts
                            .map((item) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                      Icons.warning_amber_rounded,
                                      color: AppColors.warning600),
                                  title: Text('${item['title'] ?? 'Alerte'}'),
                                  subtitle: Text('${item['message'] ?? ''}'),
                                ))
                            .toList(),
                      ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.s6),
        const WorkspaceSectionHeader(
          title: 'Répartition des moyennes',
          subtitle:
              'Excellent 19–20 · Très bien 16–18,99 · Bien 14–15,99 · Assez bien 12–13,99 · Passable 10–11,99',
        ),
        _DistributionCard(distribution: distribution),
        const SizedBox(height: AppSpacing.s6),
        ResponsiveGrid(
          desktopColumns: 2,
          tabletColumns: 1,
          mobileColumns: 1,
          children: [
            _AverageBarsCard(
              title: 'Moyenne par cycle',
              subtitle: 'Comparaison normalisée sur 20',
              rows: byCycle,
              labelKey: 'cycle',
              valueKey: 'average20',
            ),
            _VerticalBarsCard(
              key: const Key('statistics-class-bars'),
              title: 'Moyenne par classe',
              subtitle: 'Dernier trimestre officiel disponible',
              rows: byClass,
              labelKey: 'className',
              valueKey: 'average20',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s6),
        _AverageBarsCard(
          title: 'Performance par matière',
          subtitle:
              'La moyenne de chaque matière applique MC = moyenne des devoirs, puis (MC + composition) / 2',
          rows: bySubject,
          labelKey: 'subject',
          valueKey: 'average20',
          maxRows: 12,
        ),
        const SizedBox(height: AppSpacing.s6),
        _DetailedComparisonTable(
          key: const Key('statistics-detail-table'),
          byClass: byClass,
          bySubject: bySubject,
        ),
        if (attendanceByClass.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s6),
          _AverageBarsCard(
            title: 'Présence par classe',
            subtitle:
                '${data['todayAbsenceCount'] ?? 0} absence(s) enregistrée(s) aujourd’hui',
            rows: attendanceByClass,
            labelKey: 'className',
            valueKey: 'rate',
            scale: 100,
            suffix: '%',
          ),
        ],
        if (gradeCompletion.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s6),
          _AverageBarsCard(
            title: 'Complétude de la saisie des notes',
            subtitle:
                'Par enseignant, matière et classe · taux global ${data['gradeCompletionRate'] ?? 0} %',
            rows: gradeCompletion
                .map((item) => {
                      ...item,
                      'label':
                          '${item['teacher']} · ${item['subject']} · ${item['className']}',
                    })
                .toList(),
            labelKey: 'label',
            valueKey: 'completionRate',
            scale: 100,
            suffix: '%',
          ),
        ],
        if (finance != null) ...[
          const SizedBox(height: AppSpacing.s6),
          const WorkspaceSectionHeader(
            title: 'Situation financière de l’année',
            subtitle:
                'Montants issus des affectations de frais et des paiements validés, sans double comptage',
          ),
          ResponsiveGrid(
            desktopColumns: 4,
            tabletColumns: 2,
            mobileColumns: 1,
            children: [
              _Metric(
                  label: 'Attendu',
                  value: '${finance['expected'] ?? 0} FCFA',
                  icon: Icons.receipt_long_outlined,
                  color: AppColors.primary600),
              _Metric(
                  label: 'Encaissé',
                  value: '${finance['paid'] ?? 0} FCFA',
                  icon: Icons.payments_outlined,
                  color: AppColors.success600),
              _Metric(
                  label: 'Reste à encaisser',
                  value: '${finance['remaining'] ?? 0} FCFA',
                  icon: Icons.account_balance_wallet_outlined,
                  color: AppColors.warning600),
              _Metric(
                  label: 'Taux de recouvrement',
                  value: '${finance['collectionRate'] ?? 0} %',
                  icon: Icons.donut_large_outlined,
                  color: AppColors.info600),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          ResponsiveGrid(
            desktopColumns: 3,
            tabletColumns: 1,
            mobileColumns: 1,
            children: [
              _FinanceBreakdown(
                  title: 'Par classe',
                  rows: finance['byClass'] as List? ?? const []),
              _FinanceBreakdown(
                  title: 'Par niveau',
                  rows: finance['byLevel'] as List? ?? const []),
              _FinanceBreakdown(
                  title: 'Par type de frais',
                  rows: finance['byType'] as List? ?? const []),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.s6),
        const WorkspaceSectionHeader(
          title: '10 meilleurs du cycle / périmètre',
          subtitle: 'Tous niveaux confondus selon les résultats officiels',
        ),
        if (top.isEmpty)
          const AppEmptyState(
            iconData: Icons.workspace_premium_outlined,
            title: 'Aucun classement officiel disponible.',
            message:
                'Le classement apparaîtra après le calcul officiel des résultats.',
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
            child: Column(
              children: [
                for (var index = 0; index < top.length; index++)
                  ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text('${top[index]['name'] ?? 'Élève'}'),
                    subtitle: Text(
                        '${top[index]['className'] ?? 'Classe'} · ${top[index]['mention'] ?? ''}'),
                    trailing: Text(
                      '${top[index]['average20'] ?? '—'} / 20',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({required this.distribution});

  final Map<String, dynamic> distribution;

  static const labels = [
    'Excellent',
    'Très bien',
    'Bien',
    'Assez bien',
    'Passable',
    'Insuffisant',
  ];

  @override
  Widget build(BuildContext context) {
    final total = labels.fold<int>(
      0,
      (sum, key) => sum + ((distribution[key] as num?)?.toInt() ?? 0),
    );
    return AppCard(
      child: Column(
        children: labels.map((label) {
          final value = (distribution[label] as num?)?.toInt() ?? 0;
          final ratio = total == 0 ? 0.0 : value / total;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(label,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Text('$value élève${value > 1 ? 's' : ''}'),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(value: ratio, minHeight: 10),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AverageBarsCard extends StatelessWidget {
  const _AverageBarsCard({
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.labelKey,
    required this.valueKey,
    this.maxRows = 20,
    this.scale = 20,
    this.suffix = '/ 20',
  });

  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> rows;
  final String labelKey;
  final String valueKey;
  final int maxRows;
  final double scale;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final visible = rows.take(maxRows).toList();
    return AppCard(
      title: title,
      subtitle: subtitle,
      child: visible.isEmpty
          ? const Text('Aucune donnée officielle disponible.')
          : Column(
              children: visible.map((row) {
                final value = (row[valueKey] as num?)?.toDouble() ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('${row[labelKey] ?? '—'}',
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 12),
                          Text('${value.toStringAsFixed(2)} $suffix'),
                        ],
                      ),
                      if (row['successRate'] != null ||
                          row['standardDeviation'] != null ||
                          row['attendanceRate'] != null ||
                          row['progression'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (row['successRate'] != null)
                              'Réussite ${row['successRate']} %',
                            if (row['standardDeviation'] != null)
                              'Dispersion ${row['standardDeviation']}',
                            if (row['attendanceRate'] != null)
                              'Présence ${row['attendanceRate']} %',
                            if (row['progression'] != null)
                              'Progression ${(row['progression'] as num) >= 0 ? '+' : ''}${row['progression']}',
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: LinearProgressIndicator(
                          value:
                              scale <= 0 ? 0 : (value / scale).clamp(0.0, 1.0),
                          minHeight: 10,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _LineChartCard extends StatelessWidget {
  const _LineChartCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.labelKey,
    required this.valueKey,
  });

  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> rows;
  final String labelKey;
  final String valueKey;

  @override
  Widget build(BuildContext context) {
    final values = rows
        .map((row) => (row[valueKey] as num?)?.toDouble() ?? 0)
        .toList();
    return AppCard(
      title: title,
      subtitle: subtitle,
      child: rows.isEmpty
          ? const Text('Aucune donnée officielle disponible.')
          : Column(
              children: [
                SizedBox(
                  height: 230,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _LineChartPainter(
                      values: values,
                      color: AppColors.primary600,
                      gridColor: Theme.of(context).dividerColor,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: rows
                      .map((row) => Flexible(
                            child: Text(
                              '${row[labelKey] ?? '—'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
    );
  }
}

class _VerticalBarsCard extends StatelessWidget {
  const _VerticalBarsCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.labelKey,
    required this.valueKey,
  });

  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> rows;
  final String labelKey;
  final String valueKey;

  @override
  Widget build(BuildContext context) {
    final visible = rows.take(10).toList();
    final values = visible
        .map((row) => (row[valueKey] as num?)?.toDouble() ?? 0)
        .toList();
    return AppCard(
      title: title,
      subtitle: subtitle,
      child: visible.isEmpty
          ? const Text('Aucune donnée officielle disponible.')
          : Column(
              children: [
                SizedBox(
                  height: 210,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _BarChartPainter(
                      values: values,
                      color: AppColors.info600,
                      gridColor: Theme.of(context).dividerColor,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s3),
                Row(
                  children: visible
                      .map((row) => Expanded(
                            child: Text(
                              '${row[labelKey] ?? '—'}',
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({
    required this.values,
    required this.color,
    required this.gridColor,
  });

  final List<double> values;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor.withValues(alpha: .45)
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.isEmpty) return;
    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * index / (values.length - 1);
      final y = size.height - (values[index].clamp(0, 20) / 20 * size.height);
      points.add(Offset(x, y));
    }
    final line = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, line);
    final dot = Paint()..color = color;
    for (final point in points) {
      canvas.drawCircle(point, 4.5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor;
}

class _BarChartPainter extends CustomPainter {
  const _BarChartPainter({
    required this.values,
    required this.color,
    required this.gridColor,
  });

  final List<double> values;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor.withValues(alpha: .45)
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.isEmpty) return;
    final slot = size.width / values.length;
    final barWidth = (slot * .56).clamp(8.0, 44.0);
    final paint = Paint()..color = color;
    for (var index = 0; index < values.length; index++) {
      final height = values[index].clamp(0, 20) / 20 * size.height;
      final left = slot * index + (slot - barWidth) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, size.height - height, barWidth, height),
        const Radius.circular(5),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor;
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.s1),
                  Text(value, style: AppTypography.heading3()),
                ],
              ),
            ),
          ],
        ),
      );
}

class _FinanceBreakdown extends StatelessWidget {
  const _FinanceBreakdown({required this.title, required this.rows});

  final String title;
  final List rows;

  @override
  Widget build(BuildContext context) => AppCard(
        title: title,
        child: rows.isEmpty
            ? const Text('Aucune donnée financière pour ce périmètre.')
            : Column(
                children: rows.take(8).map((raw) {
                  final item = Map<String, dynamic>.from(raw as Map);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${item['label']}',
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text('Attendu : ${item['expected'] ?? 0} FCFA'),
                    trailing: Text('${item['paid'] ?? 0} FCFA',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  );
                }).toList(),
              ),
      );
}

class _DetailedComparisonTable extends StatelessWidget {
  const _DetailedComparisonTable({
    super.key,
    required this.byClass,
    required this.bySubject,
  });

  final List<Map<String, dynamic>> byClass;
  final List<Map<String, dynamic>> bySubject;

  DataRow _row(Map<String, dynamic> item, String labelKey) => DataRow(cells: [
        DataCell(Text('${item[labelKey] ?? '—'}')),
        DataCell(Text('${item['studentCount'] ?? 0}')),
        DataCell(Text('${item['average20'] ?? '—'} / 20')),
        DataCell(Text(item['successRate'] == null
            ? '—'
            : '${item['successRate']} %')),
      ]);

  Widget _table(List<Map<String, dynamic>> rows, String labelKey) =>
      ResponsiveDataTable(
        child: DataTable(
          headingRowHeight: 46,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 56,
          columns: [
            DataColumn(
                label: Text(labelKey == 'className' ? 'Classe' : 'Matière')),
            const DataColumn(label: Text('Élèves')),
            const DataColumn(label: Text('Moyenne')),
            const DataColumn(label: Text('Réussite')),
          ],
          rows: rows.take(15).map((item) => _row(item, labelKey)).toList(),
        ),
      );

  @override
  Widget build(BuildContext context) => AppCard(
        title: 'Tableaux détaillés',
        subtitle:
            'Les valeurs correspondent exactement au périmètre actuellement appliqué.',
        child: byClass.isEmpty && bySubject.isEmpty
            ? const Text('Aucune donnée officielle disponible.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (byClass.isNotEmpty) ...[
                    Text('Comparaison des classes',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.s2),
                    _table(byClass, 'className'),
                  ],
                  if (byClass.isNotEmpty && bySubject.isNotEmpty)
                    const SizedBox(height: AppSpacing.s5),
                  if (bySubject.isNotEmpty) ...[
                    Text('Comparaison des matières',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.s2),
                    _table(bySubject, 'subject'),
                  ],
                ],
              ),
      );
}
