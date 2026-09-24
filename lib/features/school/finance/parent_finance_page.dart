import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/datasources/api_client.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_badge.dart';
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

  static const _months = [
    'Janvier',
    'Février',
    'Mars',
    'Avril',
    'Mai',
    'Juin',
    'Juillet',
    'Août',
    'Septembre',
    'Octobre',
    'Novembre',
    'Décembre',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _childrenRequest ??= _loadChildren();
  }

  Future<List<Map<String, dynamic>>> _loadChildren() async {
    final store = context.read<StoreService>();
    final children = await store.myChildrenForResultsRemote();
    if (children.isNotEmpty && mounted) {
      _children = children;
      final active = children.first;
      final years = _years(active);
      final preferred = store.getSelectedAcademicYearId();
      final selected = years.where((item) => '${item['id']}' == preferred);
      _select(
        active,
        yearId: years.isEmpty
            ? null
            : '${(selected.isEmpty ? years.first : selected.first)['id']}',
      );
    }
    return children;
  }

  List<Map<String, dynamic>> _years(Map<String, dynamic> child) =>
      (child['years'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

  void _select(Map<String, dynamic> child, {String? yearId}) {
    final years = _years(child);
    final effective = years.any((item) => '${item['id']}' == yearId)
        ? yearId
        : (years.isEmpty ? null : '${years.first['id']}');
    final childId = '${child['id']}';
    setState(() {
      _childId = childId;
      _yearId = effective;
      _financeRequest = effective == null
          ? null
          : context
              .read<StoreService>()
              .parentFinancialSituationRemote(childId, effective);
    });
  }

  void _retry() {
    final child = _children.where((item) => '${item['id']}' == _childId);
    if (child.isNotEmpty) _select(child.first, yearId: _yearId);
  }

  String _money(Object? value) {
    final amount = (value as num?)?.toInt() ?? 0;
    final raw = amount.abs().toString();
    final chunks = <String>[];
    for (var end = raw.length; end > 0; end -= 3) {
      chunks.insert(0, raw.substring(end < 3 ? 0 : end - 3, end));
    }
    return '${amount < 0 ? '-' : ''}${chunks.join(' ')} FCFA';
  }

  String _monthLabel(String value) {
    final parts = value.split('-');
    if (parts.length != 2) return value;
    final index = int.tryParse(parts[1]);
    if (index == null || index < 1 || index > 12) return value;
    return '${_months[index - 1]} ${parts[0]}';
  }

  String _statusLabel(String status) => switch (status) {
        'paid' => 'Payé',
        'partial' => 'Partiellement payé',
        'unpaid' => 'Impayé',
        'no_tariff' => 'Tarif non configuré',
        _ => 'Non applicable',
      };

  AppBadgeVariant _statusVariant(String status) => switch (status) {
        'paid' => AppBadgeVariant.success,
        'partial' => AppBadgeVariant.warning,
        'unpaid' => AppBadgeVariant.danger,
        _ => AppBadgeVariant.secondary,
      };

  String _regimeLabel(Object? value) => switch (value) {
        'part_time' => 'Mi-temps',
        'full_time' => 'Plein temps',
        _ => '—',
      };

  @override
  Widget build(BuildContext context) => WorkspacePage(
        title: 'Paiements / Situation financière',
        subtitle:
            'Suivez les paiements, les mois impayés, les retards et les avances de chaque enfant.',
        actions: [
          IconButton.filledTonal(
            onPressed: _financeRequest == null ? null : _retry,
            tooltip: 'Actualiser',
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
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (value) => _select(active, yearId: value),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  if (_financeRequest != null)
                    FutureBuilder<Map<String, dynamic>>(
                      key: ValueKey('parent-finance-$_childId-$_yearId'),
                      future: _financeRequest,
                      builder: (context, finance) {
                        if (finance.connectionState ==
                            ConnectionState.waiting) {
                          return const WorkspaceLoadingState(
                              label: 'Chargement de la situation financière…');
                        }
                        if (finance.hasError) {
                          final message = finance.error is ApiException
                              ? (finance.error as ApiException).message
                              : 'Impossible de charger la situation financière.';
                          return WorkspaceErrorState(
                              message: message, onRetry: _retry);
                        }
                        return _content(
                            finance.data ?? const <String, dynamic>{});
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
    final overdue = (data['overdueMonths'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final advance = (data['advanceMonths'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          title: '${data['studentName'] ?? 'Enfant'}',
          subtitle: '${data['className'] ?? 'Classe non renseignée'}',
          child: Wrap(
            spacing: AppSpacing.s4,
            runSpacing: AppSpacing.s3,
            children: [
              if (data['currentRegime'] != null)
                _info('Régime actuel',
                    _regimeLabel(data['currentRegime'])),
              _info('Mois impayés', '${summary['unpaidMonths'] ?? 0}'),
              _info('Paiements en retard', '${summary['overdueMonths'] ?? 0}'),
              _info('Mois payés en avance', '${advance.length}'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        ResponsiveGrid(
          desktopColumns: 3,
          tabletColumns: 3,
          mobileColumns: 1,
          children: [
            _amountCard(
                'Montant attendu',
                _money(summary['expected']),
                Icons.receipt_long_outlined,
                AppColors.primary600),
            _amountCard(
                'Montant payé',
                _money(summary['paid']),
                Icons.check_circle_outline,
                AppColors.success600),
            _amountCard(
                'Reste à payer',
                _money(summary['remaining']),
                Icons.account_balance_wallet_outlined,
                AppColors.warning600),
          ],
        ),
        if (overdue.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s5),
          AppCard(
            title: 'Paiements en retard',
            subtitle: 'Échéances passées qui ne sont pas entièrement réglées.',
            child: Column(
              children: overdue.map(_monthRow).toList(),
            ),
          ),
        ],
        if (advance.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s5),
          AppCard(
            title: 'Avances',
            subtitle: 'Mois futurs déjà payés en tout ou partie.',
            child: Column(
              children: advance.map(_monthRow).toList(),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.s5),
        AppCard(
          title: 'Détail mensuel',
          subtitle: 'Chaque mois utilise le tarif réellement applicable.',
          child: months.isEmpty
              ? const Text('Aucune échéance mensuelle disponible.')
              : Column(children: months.map(_monthRow).toList()),
        ),
      ],
    );
  }

  Widget _monthRow(Map<String, dynamic> row) {
    final status = '${row['status'] ?? 'unpaid'}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_monthLabel('${row['month'] ?? ''}'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  'Attendu : ${_money(row['expected'])} · Payé : ${_money(row['paid'])} · Reste : ${_money(row['remaining'])}',
                ),
                if (row['regime'] != null)
                  Text('Régime : ${_regimeLabel(row['regime'])}'),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          AppBadge(label: _statusLabel(status), variant: _statusVariant(status)),
        ],
      ),
    );
  }

  Widget _info(String label, String value) => SizedBox(
        width: 190,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(value),
          ],
        ),
      );

  Widget _amountCard(
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
                          fontSize: 20, fontWeight: FontWeight.w800)),
                  Text(title),
                ],
              ),
            ),
          ],
        ),
      );
}
