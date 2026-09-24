import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/datasources/api_client.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/responsive_grid.dart';
import '../../../shared/widgets/workspace_header.dart';

class ParentTrackingPage extends StatefulWidget {
  const ParentTrackingPage({super.key});

  @override
  State<ParentTrackingPage> createState() => _ParentTrackingPageState();
}

class _ParentTrackingPageState extends State<ParentTrackingPage> {
  Future<List<Map<String, dynamic>>>? _childrenRequest;
  Future<Map<String, dynamic>>? _trackingRequest;
  List<Map<String, dynamic>> _children = const [];
  String? _childId;
  String? _yearId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _childrenRequest ??= _loadChildren();
  }

  Future<List<Map<String, dynamic>>> _loadChildren() async {
    final children =
        await context.read<StoreService>().myChildrenForResultsRemote();
    if (children.isNotEmpty && mounted) {
      final child = children.first;
      final years = _years(child);
      final selectedYearId = context.read<StoreService>().getSelectedAcademicYearId();
      final year = years.where((item) => item['id'] == selectedYearId).toList();
      _children = children;
      _select(child,
          yearId: years.isEmpty
              ? null
              : '${(year.isEmpty ? years.first : year.first)['id']}');
    }
    return children;
  }

  List<Map<String, dynamic>> _years(Map<String, dynamic> child) =>
      (child['years'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

  void _select(Map<String, dynamic> child, {String? yearId}) {
    final years = _years(child);
    final effectiveYearId = years.any((item) => '${item['id']}' == yearId)
        ? yearId
        : (years.isEmpty ? null : '${years.first['id']}');
    setState(() {
      _childId = '${child['id']}';
      _yearId = effectiveYearId;
      _trackingRequest = effectiveYearId == null
          ? null
          : context
              .read<StoreService>()
              .myChildTrackingRemote(_childId!, effectiveYearId);
    });
  }

  void _retry() {
    final selected = _children.where((item) => '${item['id']}' == _childId);
    if (selected.isNotEmpty) _select(selected.first, yearId: _yearId);
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
        title: 'Suivi de mes enfants',
        subtitle:
            'Présence, comportement et évolution générale de chaque enfant',
        actions: [
          IconButton.filledTonal(
            onPressed: _trackingRequest == null ? null : _retry,
            tooltip: 'Actualiser le suivi',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _childrenRequest,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const WorkspaceLoadingState(
                    label: 'Chargement des enfants…');
              }
              if (snapshot.hasError || (snapshot.data ?? const []).isEmpty) {
                return const AppEmptyState(
                  iconData: Icons.family_restroom_outlined,
                  title: 'Aucun enfant accessible',
                  message:
                      'L’administration doit rattacher votre compte parent à un élève.',
                );
              }
              final active = _children.firstWhere(
                (item) => '${item['id']}' == _childId,
                orElse: () => _children.first,
              );
              final years = _years(active);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ResponsiveGrid(
                    desktopColumns: 2,
                    tabletColumns: 2,
                    mobileColumns: 1,
                    children: [
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: '${active['id']}',
                        decoration: const InputDecoration(labelText: 'Enfant'),
                        items: _children
                            .map((item) => DropdownMenuItem(
                                  value: '${item['id']}',
                                  child: Text('${item['fullName']}',
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          _select(_children.firstWhere(
                              (item) => '${item['id']}' == value));
                        },
                      ),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: years.any((item) => '${item['id']}' == _yearId)
                            ? _yearId
                            : null,
                        decoration:
                            const InputDecoration(labelText: 'Année scolaire'),
                        items: years
                            .map((item) => DropdownMenuItem(
                                  value: '${item['id']}',
                                  child: Text(
                                      '${item['name'] ?? item['className'] ?? 'Année scolaire'}',
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (value) => _select(active, yearId: value),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  if (_trackingRequest != null)
                    FutureBuilder<Map<String, dynamic>>(
                      future: _trackingRequest,
                      builder: (context, tracking) {
                        if (tracking.connectionState ==
                            ConnectionState.waiting) {
                          return const WorkspaceLoadingState(
                              label: 'Chargement du suivi…');
                        }
                        if (tracking.hasError) {
                          final message = tracking.error is ApiException
                              ? (tracking.error as ApiException).message
                              : 'Impossible de charger le suivi.';
                          return WorkspaceErrorState(
                              message: message, onRetry: _retry);
                        }
                        return _trackingContent(
                            tracking.data ?? const <String, dynamic>{});
                      },
                    ),
                ],
              );
            },
          ),
        ],
      );

  Widget _trackingContent(Map<String, dynamic> data) {
    final results = Map<String, dynamic>.from(
        data['results'] as Map? ?? const <String, dynamic>{});
    final attendance = Map<String, dynamic>.from(
        data['attendance'] as Map? ?? const <String, dynamic>{});
    final behavior = Map<String, dynamic>.from(
        data['behavior'] as Map? ?? const <String, dynamic>{});
    final periods = (results['periods'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          title: 'Évolution académique',
          subtitle: 'Comparaison des périodes de résultats publiées',
          child: periods.isEmpty
              ? const Text('Aucun résultat officiel publié pour cette année.')
              : Wrap(
                  spacing: AppSpacing.s3,
                  runSpacing: AppSpacing.s3,
                  children: periods.map((period) {
                    final average = (period['average'] as num?)?.toDouble();
                    final scale =
                        (period['averageScale'] as num?)?.toDouble() ?? 20;
                    return SizedBox(
                      width: 210,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${period['period']}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                              '${average?.toStringAsFixed(2) ?? '—'} / ${scale.toStringAsFixed(0)} · Rang ${period['rank'] ?? '—'}'),
                          const SizedBox(height: AppSpacing.s2),
                          LinearProgressIndicator(
                            value: average == null || scale <= 0
                                ? 0
                                : (average / scale).clamp(0, 1),
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: AppSpacing.s4),
        if (attendance['available'] == true) ...[
          ResponsiveGrid(
            desktopColumns: 4,
            tabletColumns: 2,
            mobileColumns: 1,
            children: [
              _metric('Présences', '${attendance['present'] ?? 0}',
                  Icons.check_circle_outline, AppColors.success500),
              _metric('Absences', '${attendance['absent'] ?? 0}',
                  Icons.person_off_outlined, AppColors.danger500),
              _metric('Retards', '${attendance['late'] ?? 0}',
                  Icons.schedule_outlined, AppColors.warning500),
              _metric('Appels officiels', '${attendance['total'] ?? 0}',
                  Icons.fact_check_outlined, AppColors.primary600),
            ],
          ),
          if ((attendance['byPeriod'] as List? ?? const []).isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s4),
            AppCard(
              title: 'Évolution de la présence',
              child: Wrap(
                spacing: AppSpacing.s4,
                runSpacing: AppSpacing.s3,
                children: (attendance['byPeriod'] as List)
                    .map((item) => Map<String, dynamic>.from(item as Map))
                    .map((period) => SizedBox(
                          width: 210,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${period['period']}'),
                            subtitle: Text(
                                '${period['absent'] ?? 0} absence(s) · ${period['late'] ?? 0} retard(s)'),
                            trailing:
                                Text('${period['present'] ?? 0} présent(s)'),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s4),
        ],
        if (behavior['available'] == true) ...[
          AppCard(
            title: 'Comportement trimestriel',
            child: _behaviorContent(behavior),
          ),
          const SizedBox(height: AppSpacing.s4),
        ],
        AppCard(
          title: 'Notes et résultats',
          child: const Text(
            'Le détail des matières, devoirs, compositions et examens se trouve dans « Notes et résultats ».',
          ),
        ),
      ],
    );
  }

  Widget _behaviorContent(Map<String, dynamic> behavior) {
    final periods = (behavior['periods'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    if (periods.isEmpty) {
      return const Text('Aucun rapport comportemental disponible.');
    }
    return Column(
      children: periods.map((period) {
        final comments = (period['comments'] as List? ?? const [])
            .map((item) => '$item')
            .where((item) => item.isNotEmpty)
            .toList();
        final contributions = (period['contributions'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        final details = contributions
            .map((item) => [
                  item['teacher'],
                  item['score'] == null ? null : '${item['score']} / 5',
                  item['comment'],
                ]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join(' · '))
            .where((value) => value.isNotEmpty)
            .toList();
        final status = '${period['status'] ?? 'waiting'}';
        final statusLabel = switch (status) {
          'official' => 'Officiel et verrouillé',
          'stale' => 'À recalculer',
          'ready' => 'Prêt à calculer',
          _ => 'En attente',
        };
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
              child: Text('${period['average'] ?? '—'}')),
          title: Text('${period['period']} · $statusLabel'),
          subtitle: Text(details.isNotEmpty
              ? details.join('\n')
              : comments.isEmpty
                  ? '${period['contributionCount'] ?? 0} contribution(s)'
                  : comments.join(' · ')),
        );
      }).toList(),
    );
  }

  Widget _metric(
          String title, String value, IconData icon, Color color) =>
      AppCard(
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800)),
                Text(title),
              ],
            )),
          ],
        ),
      );
}
