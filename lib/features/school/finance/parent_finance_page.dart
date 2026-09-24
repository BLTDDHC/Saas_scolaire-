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

class ParentFinancePage extends StatefulWidget {
  const ParentFinancePage({super.key});

  @override
  State<ParentFinancePage> createState() => _ParentFinancePageState();
}

class _ParentFinancePageState extends State<ParentFinancePage> {
  Future<List<Map<String, dynamic>>>? _childrenRequest;
  Future<Map<String, dynamic>>? _financeRequest;
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
    if (!mounted) return children;
    _children = children;
    if (children.isNotEmpty) {
      final activeYear = context.read<StoreService>().getSelectedAcademicYearId();
      _select(children.first, preferredYearId: activeYear);
    }
    return children;
  }

  List<Map<String, dynamic>> _years(Map<String, dynamic> child) =>
      (child['years'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

  void _select(Map<String, dynamic> child, {String? preferredYearId}) {
    final years = _years(child);
    final nextYear = years.any((item) => '${item['id']}' == preferredYearId)
        ? preferredYearId
        : (years.isEmpty ? null : '${years.first['id']}');
    setState(() {
      _childId = '${child['id']}';
      _yearId = nextYear;
      // Replacing the Future removes any possibility of displaying the
      // previous child's financial snapshot while the new one is loading.
      _financeRequest = nextYear == null
          ? null
          : context
              .read<StoreService>()
              .parentFinancialSituationRemote(_childId!, nextYear);
    });
  }

  void _reload() {
    final current = _children.where((item) => '${item['id']}' == _childId);
    if (current.isNotEmpty) {
      _select(current.first, preferredYearId: _yearId);
    }
  }

  String _money(Object? raw) {
    final value = (raw as num?)?.toInt() ?? 0;
    final chars = value.toString().split('').reversed.toList();
    final groups = <String>[];
    for (var i = 0; i < chars.length; i += 3) {
      groups.add(chars.skip(i).take(3).toList().reversed.join());
    }
    return '${groups.reversed.join(' ')} FCFA';
  }

  String _month(String? raw) {
    if (raw == null || raw.length < 7) return raw ?? 'Mois';
    const months = [
      'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
      'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
    ];
    final number = int.tryParse(raw.substring(5, 7));
    if (number == null || number < 1 || number > 12) return raw;
    return '${months[number - 1]} ${raw.substring(0, 4)}';
  }

  String _regime(Object? raw) => switch (raw?.toString()) {
        'part_time' => 'Mi-temps',
        'full_time' => 'Plein temps',
        _ => '—',
      };

  String _status(Map<String, dynamic> row) {
    if (row['status'] == 'paid') return 'Payé';
    if (row['status'] == 'partial') return 'Partiellement payé';
    if (row['status'] == 'no_tariff') return 'Tarif à configurer';
    if (row['isOverdue'] == true) return 'En retard';
    return 'Impayé';
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
        title: 'Paiements / Situation financière',
        subtitle:
            'Consultez les échéances et paiements de l’enfant sélectionné.',
        actions: [
          IconButton.filledTonal(
            tooltip: 'Actualiser',
            onPressed: _financeRequest == null ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _childrenRequest,
            builder: (context, childrenSnapshot) {
              if (childrenSnapshot.connectionState == ConnectionState.waiting) {
                return const WorkspaceLoadingState(
                    label: 'Chargement des enfants…');
              }
              if (childrenSnapshot.hasError ||
                  (childrenSnapshot.data ?? const []).isEmpty) {
                return const AppEmptyState(
                  iconData: Icons.family_restroom_outlined,
                  title: 'Aucun enfant accessible',
                  message:
                      'L’administration doit rattacher votre compte à un enfant.',
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
                        key: const Key('parent-finance-child'),
                        isExpanded: true,
                        initialValue: '${active['id']}',
                        decoration: const InputDecoration(labelText: 'Enfant'),
                        items: _children
                            .map((child) => DropdownMenuItem(
                                  value: '${child['id']}',
                                  child: Text(
                                    '${child['fullName']}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          _select(_children.firstWhere(
                              (child) => '${child['id']}' == value));
                        },
                      ),
                      DropdownButtonFormField<String>(
                        key: const Key('parent-finance-year'),
                        isExpanded: true,
                        initialValue: years.any(
                                (item) => '${item['id']}' == _yearId)
                            ? _yearId
                            : null,
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
                        onChanged: (value) =>
                            _select(active, preferredYearId: value),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  if (_financeRequest != null)
                    FutureBuilder<Map<String, dynamic>>(
                      key: ValueKey('parent-finance-$_childId-$_yearId'),
                      future: _financeRequest,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const WorkspaceLoadingState(
                              label: 'Chargement de la situation financière…');
                        }
                        if (snapshot.hasError) {
                          final message = snapshot.error is ApiException
                              ? (snapshot.error as ApiException).message
                              : 'Impossible de charger la situation financière.';
                          return WorkspaceErrorState(
                            message: message,
                            onRetry: _reload,
                          );
                        }
                        return _content(
                            snapshot.data ?? const <String, dynamic>{});
                      },
                    ),
                ],
              );
            },
          ),
        ],
      );

  Widget _content(Map<String, dynamic> data) {
    final summary = Map<String, dynamic>.from(
        data['summary'] as Map? ?? const <String, dynamic>{});
    final months = (data['months'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final regime = data['currentRegime'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          title: '${data['studentName'] ?? 'Enfant'}',
          subtitle: '${data['className'] ?? 'Classe non renseignée'}',
          child: regime == null
              ? const Text('Situation financière de l’année sélectionnée.')
              : Text(
                  'Régime actuel : ${_regime(regime)}',
                  key: const Key('parent-current-regime'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
        ),
        const SizedBox(height: AppSpacing.s4),
        ResponsiveGrid(
          desktopColumns: 4,
          tabletColumns: 2,
          mobileColumns: 1,
          children: [
            _metric(
              'Montant payé',
              _money(summary['paid']),
              Icons.check_circle_outline,
              AppColors.success600,
            ),
            _metric(
              'Reste à payer',
              _money(summary['remaining']),
              Icons.account_balance_wallet_outlined,
              AppColors.warning600,
            ),
            _metric(
              'Mois impayés',
              '${summary['unpaidMonths'] ?? 0}',
              Icons.calendar_month_outlined,
              AppColors.danger600,
            ),
            _metric(
              'Paiements en retard',
              '${summary['overdueMonths'] ?? 0}',
              Icons.schedule_outlined,
              AppColors.danger500,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        if ((summary['advanceMonths'] as num? ?? 0) > 0 ||
            (summary['credit'] as num? ?? 0) > 0)
          AppCard(
            title: 'Avance',
            child: Text(
              '${summary['advanceMonths'] ?? 0} mois payé(s) en avance'
              '${(summary['credit'] as num? ?? 0) > 0 ? ' · Crédit : ${_money(summary['credit'])}' : ''}.',
            ),
          ),
        if ((summary['advanceMonths'] as num? ?? 0) > 0 ||
            (summary['credit'] as num? ?? 0) > 0)
          const SizedBox(height: AppSpacing.s4),
        AppCard(
          title: 'Échéances mensuelles',
          subtitle:
              'Chaque mois utilise le tarif réellement applicable à cette période.',
          child: months.isEmpty
              ? const Text('Aucune échéance mensuelle pour cette année.')
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 760) {
                      return Column(
                        children: months.map((row) {
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(_month(row['month']?.toString())),
                            subtitle: Text(
                              'Tarif : ${_money(row['expected'])}'
                              ' · Payé : ${_money(row['paid'])}'
                              ' · Reste : ${_money(row['remaining'])}'
                              '${row['schoolRegime'] == null ? '' : ' · ${_regime(row['schoolRegime'])}'}',
                            ),
                            trailing: Text(
                              _status(row),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          );
                        }).toList(),
                      );
                    }
                    final showRegime = regime != null;
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: [
                          const DataColumn(label: Text('Mois')),
                          if (showRegime)
                            const DataColumn(label: Text('Régime')),
                          const DataColumn(label: Text('Tarif applicable')),
                          const DataColumn(label: Text('Déjà payé')),
                          const DataColumn(label: Text('Reste')),
                          const DataColumn(label: Text('Statut')),
                        ],
                        rows: months
                            .map(
                              (row) => DataRow(
                                cells: [
                                  DataCell(
                                      Text(_month(row['month']?.toString()))),
                                  if (showRegime)
                                    DataCell(Text(_regime(row['schoolRegime']))),
                                  DataCell(Text(_money(row['expected']))),
                                  DataCell(Text(_money(row['paid']))),
                                  DataCell(Text(_money(row['remaining']))),
                                  DataCell(Text(_status(row))),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _metric(
    String label,
    String value,
    IconData icon,
    Color color,
  ) =>
      AppCard(
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(label),
                ],
              ),
            ),
          ],
        ),
      );
}
