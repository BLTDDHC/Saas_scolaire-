import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/responsive_utils.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/responsive_grid.dart';
import '../../../shared/widgets/workspace_header.dart';
import '../../../core/utils/school_module_access.dart';

class SchoolDashboard extends StatefulWidget {
  final ValueChanged<String>? onNavigate;
  final Future<Map<String, dynamic>> Function()? statisticsLoader;

  const SchoolDashboard({super.key, this.onNavigate, this.statisticsLoader});
  @override
  State<SchoolDashboard> createState() => _SchoolDashboardState();
}

class _SchoolDashboardState extends State<SchoolDashboard> {
  Future<Map<String, dynamic>>? _summary;
  String? _loadedYearId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.watch<StoreService>();
    if (store.currentUser?.role == UserRole.teacher ||
        store.currentUser?.role == UserRole.student ||
        store.currentUser?.role == UserRole.parent) return;
    final yearId = store.getSelectedAcademicYearId();
    if (_summary == null || yearId != _loadedYearId) {
      _loadedYearId = yearId;
      _summary = _loadSummary();
    }
  }

  Future<Map<String, dynamic>> _loadSummary() async {
    final data = await (widget.statisticsLoader?.call() ??
        context.read<StoreService>().getSchoolOrganizationSummary());
    if (widget.statisticsLoader != null &&
        data['studentCount'] is num &&
        data['teacherCount'] is num &&
        data['classCount'] is num) {
      return {...data, '__legacyTestContract': true};
    }
    if (data['activeCycleCount'] is! num || data['classCount'] is! num) {
      throw const FormatException('Réponse organisation académique invalide');
    }
    return data;
  }

  void _retry() => setState(() => _summary = _loadSummary());

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    if (store.currentUser?.role == UserRole.teacher) {
      return _TeacherDashboard(onNavigate: widget.onNavigate);
    }
    if (store.currentUser?.role == UserRole.student) {
      return _StudentDashboard(onNavigate: widget.onNavigate);
    }
    if (store.currentUser?.role == UserRole.parent) {
      return _ParentDashboard(onNavigate: widget.onNavigate);
    }
    final selectedYear = store.getSelectedAcademicYear();
    final classes = store.getClassesByYear(selectedYear?.id);
    final directionCycleIds =
        store.currentUser?.directionCycleIds.toSet() ?? {};
    final directionCycles = store
        .getSchoolCycles()
        .where((cycle) => directionCycleIds.contains(cycle.id))
        .toList();
    final usesTenPointScale = directionCycles.isNotEmpty &&
        directionCycles.every((cycle) {
          final value =
              '${cycle.code} ${cycle.name}'.toUpperCase().replaceAll('É', 'E');
          return value.contains('MATERNELLE') || value.contains('PRIMAIRE');
        });
    final averageScale = usesTenPointScale ? 10 : 20;
    final recentClasses = List.of(classes)
      ..sort((left, right) {
        final leftDate =
            DateTime.tryParse(left.createdAt ?? '') ?? DateTime(1970);
        final rightDate =
            DateTime.tryParse(right.createdAt ?? '') ?? DateTime(1970);
        return rightDate.compareTo(leftDate);
      });
    final isMobile = ContextUtils.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.s4 : AppSpacing.s6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        WorkspaceHeader(
            title: 'Tableau de bord',
            subtitle: 'Indicateurs de l’année scolaire sélectionnée',
            actions: [
              OutlinedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualiser'))
            ]),
        const SizedBox(height: AppSpacing.s6),
        FutureBuilder<Map<String, dynamic>>(
          future: _summary,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                  height: 130,
                  child: Center(
                      child: CircularProgressIndicator(
                          key: Key('dashboard-statistics-loading'))));
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return AppCard(
                  child: Column(children: [
                const Text('Impossible de charger les statistiques.'),
                const SizedBox(height: AppSpacing.s3),
                AppButton(label: 'Réessayer', onPressed: _retry),
              ]));
            }
            final data = snapshot.data!;
            if (data['__legacyTestContract'] == true) {
              final attendance = data['attendanceRate'] as num?;
              return ResponsiveGrid(
                desktopColumns: 4,
                tabletColumns: 2,
                mobileColumns: 1,
                children: [
                  _OrganizationCard(
                      title: 'Élèves inscrits',
                      value: '${data['studentCount']}',
                      icon: Icons.people,
                      color: AppColors.primary600),
                  _OrganizationCard(
                      title: 'Enseignants',
                      value: '${data['teacherCount']}',
                      icon: Icons.school,
                      color: AppColors.success500),
                  _OrganizationCard(
                      title: 'Classes ouvertes',
                      value: '${data['classCount']}',
                      icon: Icons.meeting_room,
                      color: AppColors.secondary600),
                  _OrganizationCard(
                    title: 'Taux de présence',
                    value: attendance == null
                        ? 'Aucune donnée'
                        : '${attendance.toStringAsFixed(1)}%',
                    subtitle:
                        attendance == null ? 'Aucun relevé enregistré' : null,
                    icon: Icons.check_circle,
                    color: AppColors.warning500,
                  ),
                ],
              );
            }
            final selected =
                data['selectedAcademicYear'] as Map<String, dynamic>?;
            final readyResults = List<Map<String, dynamic>>.from(
                (data['readyResults'] as List? ?? const [])
                    .map((item) => Map<String, dynamic>.from(item)));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (readyResults.isNotEmpty) ...[
                  AppCard(
                    title: 'Résultats prêts à être calculés',
                    subtitle:
                        'Tous les relevés requis sont arrivés pour ces contextes.',
                    child: Column(
                      children: readyResults
                          .map((item) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.check_circle_outline,
                                    color: AppColors.success500),
                                title: Text(
                                    '${item['class'] ?? 'Classe'} — ${item['period'] ?? 'Période'}'),
                                subtitle: Text(
                                    '${item['received'] ?? item['expected'] ?? 0}/${item['expected'] ?? 0} relevés reçus'),
                                trailing: TextButton(
                                  onPressed: () =>
                                      widget.onNavigate?.call('grades'),
                                  child: const Text('Calculer'),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                ],
                ResponsiveGrid(
                    desktopColumns: 4,
                    tabletColumns: 2,
                    mobileColumns: 1,
                    children: [
                      _OrganizationCard(
                          title: 'Cycles / classes',
                          value:
                              '${(data['activeCycleCount'] as num).toInt()} / ${(data['classCount'] as num).toInt()}',
                          subtitle: 'classes de l’année sélectionnée',
                          icon: Icons.account_tree_rounded,
                          color: AppColors.warning500),
                      _OrganizationCard(
                          title: 'Élèves inscrits',
                          value:
                              '${(data['studentCount'] as num? ?? 0).toInt()}',
                          subtitle: selected?['name']?.toString(),
                          icon: Icons.people_alt_rounded,
                          color: AppColors.primary600),
                      _OrganizationCard(
                          title: 'Enseignants actifs',
                          value:
                              '${(data['teacherCount'] as num? ?? 0).toInt()}',
                          icon: Icons.school_rounded,
                          color: AppColors.success500),
                      _OrganizationCard(
                          title: 'Taux de présence',
                          value: data['attendanceRate'] is num
                              ? '${(data['attendanceRate'] as num).toStringAsFixed(1)}%'
                              : 'Aucune donnée',
                          icon: Icons.fact_check_rounded,
                          color: AppColors.secondary600),
                      _OrganizationCard(
                          title: 'Moyenne validée',
                          value: data['overallAverage'] is num
                              ? '${((data['overallAverage'] as num) * averageScale / 20).toStringAsFixed(2)}/$averageScale'
                              : 'Non calculable',
                          icon: Icons.analytics_rounded,
                          color: AppColors.warning500),
                    ]),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.s6),
        AppCard(
            title: '5 dernières classes créées',
            child: classes.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.s3),
                    child: Text('Aucune classe pour ce contexte.'))
                : Column(children: [
                    ...recentClasses.take(5).map((item) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            '${item.cycle ?? "Cycle"} · ${item.level ?? "Niveau"}'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => widget.onNavigate?.call('classes'))),
                    if (classes.length > 5)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => widget.onNavigate?.call('classes'),
                          icon: const Icon(Icons.list_alt_rounded),
                          label: const Text('Voir toutes les classes'),
                        ),
                      ),
                  ])),
      ]),
    );
  }
}

class _StudentDashboard extends StatefulWidget {
  const _StudentDashboard({this.onNavigate});

  final ValueChanged<String>? onNavigate;

  @override
  State<_StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<_StudentDashboard> {
  Future<Map<String, dynamic>>? _tracking;
  String? _yearId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final yearId = context.read<StoreService>().getSelectedAcademicYearId();
    if (yearId != null && (_tracking == null || yearId != _yearId)) {
      _yearId = yearId;
      _tracking = context.read<StoreService>().myStudentTrackingRemote(yearId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final students = store.getStudents();
    final ownStudents = students
        .where((item) => item.id == store.getCurrentStudentId())
        .toList();
    final student = ownStudents.isEmpty ? null : ownStudents.first;
    final isMobile = ContextUtils.isMobile(context);
    return ListView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.s4 : AppSpacing.s6),
      children: [
        WorkspaceHeader(
          title: 'Mon espace scolaire',
          subtitle: student == null
              ? 'Vos informations scolaires'
              : 'Bienvenue ${student.firstName}',
        ),
        const SizedBox(height: AppSpacing.s6),
        ResponsiveGrid(
          desktopColumns: 3,
          tabletColumns: 2,
          mobileColumns: 1,
          children: [
            _OrganizationCard(
              title: 'Matricule',
              value: student?.matricule ?? 'Non attribué',
              icon: Icons.badge_outlined,
              color: AppColors.primary600,
            ),
            _OrganizationCard(
              title: 'Classe',
              value: student?.className ?? 'Non inscrit',
              subtitle: [student?.cycle, student?.level, student?.series]
                  .whereType<String>()
                  .where((value) => value.isNotEmpty)
                  .join(' · '),
              icon: Icons.school_outlined,
              color: AppColors.secondary600,
            ),
            _OrganizationCard(
              title: 'Année scolaire',
              value: store.getSelectedAcademicYear()?.name ?? 'Non définie',
              icon: Icons.calendar_month_outlined,
              color: AppColors.success500,
            ),
          ],
        ),
        if (_tracking != null) ...[
          const SizedBox(height: AppSpacing.s5),
          FutureBuilder<Map<String, dynamic>>(
            future: _tracking,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AppCard(
                    child: Center(child: CircularProgressIndicator()));
              }
              if (!snapshot.hasData) {
                return const AppCard(
                  child: Text(
                      'Votre synthèse sera disponible dès la publication des données scolaires.'),
                );
              }
              final data = snapshot.data!;
              final results = data['results'] as Map?;
              final periods = (results?['periods'] as List? ?? const [])
                  .map((item) => Map<String, dynamic>.from(item as Map))
                  .toList();
              final latest = periods.isEmpty ? null : periods.last;
              final recentGrades = latest == null
                  ? const <Map<String, dynamic>>[]
                  : (latest['subjects'] as List? ?? const [])
                      .expand((subject) =>
                          (Map<String, dynamic>.from(subject as Map)['grades']
                                  as List? ??
                              const []))
                      .map((grade) => Map<String, dynamic>.from(grade as Map))
                      .take(4)
                      .toList();
              final attendance = data['attendance'] as Map?;
              final behaviorPeriods =
                  ((data['behavior'] as Map?)?['periods'] as List? ?? const [])
                      .map((item) => Map<String, dynamic>.from(item as Map))
                      .toList();
              final behavior =
                  behaviorPeriods.isEmpty ? null : behaviorPeriods.last;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ma situation actuelle',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.s3),
                  ResponsiveGrid(
                    desktopColumns: 4,
                    tabletColumns: 2,
                    mobileColumns: 1,
                    children: [
                      _OrganizationCard(
                        title: 'Moyenne',
                        value: latest == null
                            ? 'Non publiée'
                            : '${latest['average'] ?? '—'} / ${latest['averageScale'] ?? 20}',
                        subtitle: latest?['period']?.toString(),
                        icon: Icons.trending_up_rounded,
                        color: AppColors.primary600,
                      ),
                      _OrganizationCard(
                        title: 'Rang',
                        value: latest == null
                            ? 'Non publié'
                            : '${latest['rank'] ?? '—'}',
                        icon: Icons.emoji_events_outlined,
                        color: AppColors.warning500,
                      ),
                      _OrganizationCard(
                        title: 'Présences / absences',
                        value: attendance?['available'] == true
                            ? '${attendance?['present'] ?? 0} / ${attendance?['absent'] ?? 0}'
                            : 'Non disponible',
                        icon: Icons.how_to_reg_outlined,
                        color: AppColors.success500,
                      ),
                      _OrganizationCard(
                        title: 'Comportement',
                        value: behavior == null
                            ? 'Non publié'
                            : '${behavior['average'] ?? '—'} / 5',
                        subtitle: behavior?['period']?.toString(),
                        icon: Icons.stars_outlined,
                        color: AppColors.secondary600,
                      ),
                    ],
                  ),
                  if (periods.length > 1) ...[
                    const SizedBox(height: AppSpacing.s4),
                    AppCard(
                      title: 'Mon évolution',
                      child: Wrap(
                        spacing: AppSpacing.s4,
                        runSpacing: AppSpacing.s3,
                        children: periods
                            .map((period) => Text(
                                '${period['period']} : ${period['average'] ?? '—'} / ${period['averageScale'] ?? 20}'))
                            .toList(),
                      ),
                    ),
                  ],
                  if (recentGrades.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s4),
                    AppCard(
                      title: 'Dernières évaluations publiées',
                      child: Column(
                        children: recentGrades
                            .map((grade) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.task_alt_outlined),
                                  title: Text(
                                      '${grade['title'] ?? grade['evaluation'] ?? grade['type'] ?? 'Évaluation'}'),
                                  subtitle: Text('${grade['subject'] ?? ''}'),
                                  trailing: Text(
                                    '${grade['value'] ?? '—'} / ${grade['maxValue'] ?? grade['max'] ?? 20}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
        const SizedBox(height: AppSpacing.s6),
        AppCard(
          title: 'Accès rapide',
          child: Wrap(
            spacing: AppSpacing.s3,
            runSpacing: AppSpacing.s3,
            children: [
              AppButton(
                label: 'Voir mes résultats',
                icon: Icons.grade_outlined,
                onPressed: () => widget.onNavigate?.call('grades'),
              ),
              AppButton(
                label: 'Voir mon emploi du temps',
                icon: Icons.calendar_today_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: () => widget.onNavigate?.call('schedule'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ParentDashboard extends StatefulWidget {
  const _ParentDashboard({this.onNavigate});

  final ValueChanged<String>? onNavigate;

  @override
  State<_ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends State<_ParentDashboard> {
  Future<List<Map<String, dynamic>>>? _request;
  Future<Map<String, dynamic>>? _primaryTracking;
  String? _primaryTrackingKey;
  String? _selectedChildId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _request ??= context.read<StoreService>().parentDashboardChildrenRemote();
  }

  void _reload() => setState(() {
        _request = context.read<StoreService>().parentDashboardChildrenRemote();
        _primaryTracking = null;
        _primaryTrackingKey = null;
      });

  Future<Map<String, dynamic>> _trackingFor(
      Map<String, dynamic> child, Map<String, dynamic> year) {
    final key = '${child['id']}::${year['id']}';
    if (_primaryTracking == null || _primaryTrackingKey != key) {
      _primaryTrackingKey = key;
      _primaryTracking = context
          .read<StoreService>()
          .myChildTrackingRemote('${child['id']}', '${year['id']}');
    }
    return _primaryTracking!;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ContextUtils.isMobile(context);
    return ListView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.s4 : AppSpacing.s6),
      children: [
        WorkspaceHeader(
          title: 'Mon espace parent',
          subtitle: 'Une vue claire de la situation scolaire de vos enfants',
          actions: [
            IconButton.filledTonal(
              onPressed: _reload,
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s5),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _request,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return AppCard(
                title: 'Enfants liés',
                child: TextButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Impossible de charger. Réessayer'),
                ),
              );
            }
            final children = snapshot.data ?? const <Map<String, dynamic>>[];
            if (children.isEmpty) {
              return const AppCard(
                title: 'Enfants liés',
                child: Text(
                    'Aucun enfant n’est actuellement rattaché à votre compte.'),
              );
            }
            final selectedChildren = children
                .where((child) => '${child['id']}' == _selectedChildId)
                .toList();
            final primaryChild = selectedChildren.isEmpty
                ? children.first
                : selectedChildren.first;
            final primaryYears = (primaryChild['years'] as List? ?? const [])
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
            final selectedYearId =
                context.read<StoreService>().getSelectedAcademicYearId();
            final matchingYears = primaryYears
                .where((item) => item['id'] == selectedYearId)
                .toList();
            final primaryYear = matchingYears.isNotEmpty
                ? matchingYears.first
                : (primaryYears.isEmpty ? null : primaryYears.first);
            final primaryTracking = primaryYear == null
                ? null
                : _trackingFor(primaryChild, primaryYear);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (primaryYear != null) ...[
                  FutureBuilder<Map<String, dynamic>>(
                    future: primaryTracking,
                    builder: (context, tracking) {
                      if (tracking.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (tracking.hasError) {
                        return const AppCard(
                          title: 'Situation scolaire',
                          child: Text(
                              'Les données détaillées ne sont pas disponibles pour le moment.'),
                        );
                      }
                      if (!tracking.hasData) return const SizedBox.shrink();
                      final data = tracking.data!;
                      final results = data['results'] as Map?;
                      final periods = (results?['periods'] as List? ?? const [])
                          .map((item) => Map<String, dynamic>.from(item as Map))
                          .toList();
                      final latest = periods.isEmpty ? null : periods.last;
                      final attendance = data['attendance'] as Map?;
                      final behaviorPeriods = ((data['behavior']
                                  as Map?)?['periods'] as List? ??
                              const [])
                          .map((item) => Map<String, dynamic>.from(item as Map))
                          .toList();
                      final behavior =
                          behaviorPeriods.isEmpty ? null : behaviorPeriods.last;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.s5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Situation de ${primaryChild['fullName']}',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: AppSpacing.s3),
                            ResponsiveGrid(
                              desktopColumns: 4,
                              tabletColumns: 2,
                              mobileColumns: 1,
                              children: [
                                _OrganizationCard(
                                  title: 'Moyenne',
                                  value: latest == null
                                      ? 'Non publiée'
                                      : '${latest['average'] ?? '—'} / ${latest['averageScale'] ?? 20}',
                                  subtitle: latest?['period']?.toString(),
                                  icon: Icons.trending_up_rounded,
                                  color: AppColors.primary600,
                                ),
                                _OrganizationCard(
                                  title: 'Rang',
                                  value: latest == null
                                      ? 'Non publié'
                                      : '${latest['rank'] ?? '—'}',
                                  icon: Icons.emoji_events_outlined,
                                  color: AppColors.warning500,
                                ),
                                _OrganizationCard(
                                  title: 'Absences / retards',
                                  value: attendance?['available'] == true
                                      ? '${attendance?['absent'] ?? 0} / ${attendance?['late'] ?? 0}'
                                      : 'Non disponible',
                                  icon: Icons.event_busy_outlined,
                                  color: AppColors.danger500,
                                ),
                                _OrganizationCard(
                                  title: 'Comportement',
                                  value: behavior == null
                                      ? 'Non publié'
                                      : '${behavior['average'] ?? '—'} / 5',
                                  subtitle: behavior?['period']?.toString(),
                                  icon: Icons.stars_outlined,
                                  color: AppColors.success500,
                                ),
                              ],
                            ),
                            if (periods.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.s4),
                              AppCard(
                                title: 'Évolution des résultats',
                                child: Wrap(
                                  spacing: AppSpacing.s4,
                                  runSpacing: AppSpacing.s3,
                                  children: periods
                                      .map((period) => Text(
                                          '${period['period']} : ${period['average'] ?? '—'} / ${period['averageScale'] ?? 20}'))
                                      .toList(),
                                ),
                              ),
                            ],
                            if (behaviorPeriods.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.s4),
                              AppCard(
                                title: 'Comportement T1 / T2 / T3',
                                child: Wrap(
                                  spacing: AppSpacing.s4,
                                  runSpacing: AppSpacing.s3,
                                  children: behaviorPeriods
                                      .map((period) => Text(
                                          '${period['period']} : ${period['average'] ?? '—'} / 5'))
                                      .toList(),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ],
                ResponsiveGrid(
                  desktopColumns: 3,
                  tabletColumns: 2,
                  mobileColumns: 1,
                  children: children.map((child) {
                    final years = (child['years'] as List? ?? const [])
                        .map((item) => Map<String, dynamic>.from(item as Map))
                        .toList();
                    final currentYear = years.where((item) =>
                        item['id'] ==
                        context
                            .read<StoreService>()
                            .getSelectedAcademicYearId());
                    final year = currentYear.isNotEmpty
                        ? currentYear.first
                        : (years.isEmpty ? null : years.first);
                    return AppCard(
                      title: '${child['fullName']}',
                      subtitle: year == null
                          ? 'Aucune inscription active'
                          : '${year['className'] ?? 'Classe non précisée'} · ${year['name'] ?? 'Année scolaire'}',
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            if ('${child['id']}' != '${primaryChild['id']}') {
                              setState(() {
                                _selectedChildId = '${child['id']}';
                                _primaryTracking = null;
                                _primaryTrackingKey = null;
                              });
                            } else {
                              widget.onNavigate?.call('tracking');
                            }
                          },
                          icon: const Icon(Icons.insights_rounded),
                          label: Text(
                              '${child['id']}' == '${primaryChild['id']}'
                                  ? 'Ouvrir le suivi complet'
                                  : 'Afficher sur le tableau'),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.s5),
                AppCard(
                  title: 'Accès rapide',
                  child: Wrap(
                    spacing: AppSpacing.s3,
                    runSpacing: AppSpacing.s3,
                    children: [
                      AppButton(
                        label: 'Suivi des enfants',
                        icon: Icons.insights_rounded,
                        onPressed: () => widget.onNavigate?.call('tracking'),
                      ),
                      AppButton(
                        label: 'Résultats détaillés',
                        icon: Icons.grade_outlined,
                        variant: AppButtonVariant.secondary,
                        onPressed: () => widget.onNavigate?.call('grades'),
                      ),
                      AppButton(
                        label: 'Emplois du temps',
                        icon: Icons.calendar_today_outlined,
                        variant: AppButtonVariant.secondary,
                        onPressed: () => widget.onNavigate?.call('schedule'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TeacherDashboard extends StatelessWidget {
  const _TeacherDashboard({this.onNavigate});

  final ValueChanged<String>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final yearId = store.getSelectedAcademicYearId();
    final modules = store.getCurrentSchool()?.enabledModules ?? <String>[];
    bool available(String page) =>
        !store.isCurrentSchoolSuspended() && isSchoolPageEnabled(page, modules);
    final teachers = store
        .getTeachers()
        .where((t) => t.id == store.getCurrentTeacherId())
        .toList();
    final teacher = teachers.isEmpty ? null : teachers.first;
    final affectations = store
        .getAffectations()
        .where((item) =>
            yearId == null ||
            item.academicYearId == null ||
            item.academicYearId == yearId)
        .toList();
    final classNames = affectations
        .map((item) => item.className)
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toSet();
    final subjectNames = affectations
        .map((item) => item.subject)
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toSet();
    final evaluations = store
        .getEvaluations()
        .where((item) => yearId == null || item.academicYearId == yearId)
        .toList();
    final pending = evaluations
        .where((item) => item.status == 'draft' || item.status == 'rejected')
        .length;
    final submitted = evaluations
        .where(
            (item) => item.status == 'submitted' || item.status == 'validated')
        .length;
    final isMobile = ContextUtils.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.s4 : AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkspaceHeader(
              title: 'Mon espace enseignant',
              subtitle:
                  '${store.currentUser?.name ?? "Enseignant"} · ${store.getSelectedAcademicYear()?.name ?? "Année non sélectionnée"}'),
          const SizedBox(height: AppSpacing.s6),
          ResponsiveGrid(
            desktopColumns: 4,
            tabletColumns: 2,
            mobileColumns: 1,
            children: [
              _OrganizationCard(
                title: 'Matricule',
                value: teacher?.employeeNumber ?? 'Non attribué',
                icon: Icons.badge_outlined,
                color: AppColors.primary600,
              ),
              _OrganizationCard(
                title: 'Classes affectées',
                value: '${classNames.length}',
                icon: Icons.meeting_room_outlined,
                color: AppColors.secondary600,
              ),
              _OrganizationCard(
                title: 'Matières',
                value: '${subjectNames.length}',
                icon: Icons.menu_book_outlined,
                color: AppColors.success500,
              ),
              _OrganizationCard(
                title: 'Évaluations à traiter',
                value: '$pending',
                subtitle: '$submitted soumise(s) ou validée(s)',
                icon: Icons.fact_check_outlined,
                color: AppColors.warning500,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          AppCard(
            title: 'Actions pédagogiques',
            child: Wrap(
              spacing: AppSpacing.s3,
              runSpacing: AppSpacing.s3,
              children: [
                if (available('grades'))
                  AppButton(
                    label: 'Saisir les notes',
                    icon: Icons.grade_outlined,
                    onPressed: () => onNavigate?.call('grades'),
                  ),
                if (available('attendance'))
                  AppButton(
                    label: 'Faire l’appel',
                    icon: Icons.how_to_reg_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => onNavigate?.call('attendance'),
                  ),
                if (available('behavior'))
                  AppButton(
                    label: 'Comportement',
                    icon: Icons.stars_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => onNavigate?.call('behavior'),
                  ),
                if (available('grades'))
                  AppButton(
                      label: 'Consulter les résultats',
                      icon: Icons.leaderboard_outlined,
                      variant: AppButtonVariant.secondary,
                      onPressed: () => onNavigate?.call('grades')),
                if (available('schedule'))
                  AppButton(
                    label: 'Mon emploi du temps',
                    icon: Icons.calendar_month_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => onNavigate?.call('schedule'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s5),
          AppCard(
            title: 'Mes affectations',
            subtitle: 'Classes et matières qui vous sont affectées',
            child: affectations.isEmpty
                ? const Text('Aucune affectation active pour cette année.')
                : Column(
                    children: affectations
                        .map((item) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading:
                                  const Icon(Icons.assignment_ind_outlined),
                              title: Text(item.className ?? 'Classe'),
                              subtitle: Text(item.subject ?? 'Matière'),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: available('grades')
                                  ? () => onNavigate?.call('grades')
                                  : null,
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _OrganizationCard extends StatelessWidget {
  const _OrganizationCard(
      {required this.title,
      required this.value,
      required this.icon,
      required this.color,
      this.subtitle});
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => AppCard(
          child: Row(children: [
        Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: Icon(icon, color: color)),
        const SizedBox(width: AppSpacing.s3),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTypography.caption(color: AppColors.gray500)),
          Text(value,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis),
          if (subtitle != null)
            Text(subtitle!, style: const TextStyle(fontSize: 11)),
        ])),
      ]));
}
