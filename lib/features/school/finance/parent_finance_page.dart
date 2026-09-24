import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../data/datasources/api_client.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/responsive_grid.dart';
import '../../../shared/widgets/workspace_header.dart';

String _money(Object? value) {
  final amount = (value as num?)?.toInt() ?? 0;
  final raw = amount.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < raw.length; index++) {
    if (index > 0 && (raw.length - index) % 3 == 0) buffer.write(' ');
    buffer.write(raw[index]);
  }
  return '${buffer.toString()} FCFA';
}

String _regimeLabel(Object? value) => switch (value?.toString()) {
      'part_time' => 'Mi-temps',
      'full_time' => 'Plein temps',
      _ => 'Non applicable',
    };

String _statusLabel(Object? value) => switch (value?.toString()) {
      'paid' => 'Payé',
      'partial' => 'Partiellement payé',
      'overdue' => 'Paiement en retard',
      'no_tariff' => 'Tarif à configurer',
      'not_applicable' => 'Non applicable',
      _ => 'Impayé',
    };

class ParentFinancePage extends StatefulWidget {
  const ParentFinancePage({super.key});

  @override
  State<ParentFinancePage> createState() => _ParentFinancePageState();
}

class _ParentFinancePageState extends State<ParentFinancePage> {
  Future<List<Map<String, dynamic>>>? _childrenRequest;
  Future<Map<String, dynamic>>? _financeRequest;
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
          .map((item) => Map<String, dynamic>.from(item as Map)),
    );
    final preferredYear = yearId ?? store.getSelectedAcademicYearId();
    final selectedYearId = years.any((item) => item['id'] == preferredYear)
        ? preferredYear
        : (years.isEmpty ? null : '${years.first['id']}');
    final childId = '${child['id']}';
    setState(() {
      _childId = childId;
      _yearId = selectedYearId;
      _financeRequest = selectedYearId == null
          ? null
          : store.parentFinanceSituationRemote(childId, selectedYearId);
    });
  }

  void _retry() {
    if (_childId == null || _yearId == null) return;
    setState(() {
      _financeRequest = context
          .read<StoreService>()
          .parentFinanceSituationRemote(_childId!, _yearId!);
    });
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
        title: 'Paiements / Situation financière',
        subtitle:
            'Consultez les paiements, mois impayés, retards et avances de chaque enfant.',
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _childrenRequest,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.s8),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              final children = snapshot.data ?? const <Map<String, dynamic>>[];
              if (snapshot.hasError || children.isEmpty) {
                return const AppEmptyState(
                  iconData: Icons.family_restroom_outlined,
                  title: 'Aucun enfant accessible',
                  message:
                      'L’administration doit rattacher votre compte parent à un élève.',
                );
              }
              final selected =
                  children.where((item) => '${item['id']}' == _childId).toList();
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
                        items: children
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
                          _selectChild(children.firstWhere(
                              (item) => '${item['id']}' == value));
                        },
                      ),
                      DropdownButtonFormField<String>(
                        key: const Key('parent-finance-year'),
                        isExpanded: true,
                        initialValue: years.any((item) => '${item['id']}' == _yearId)
                            ? _yearId
                            : (years.isEmpty ? null : '${years.first['id']}'),
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
                        onChanged: (value) {
                          if (value != null) _selectChild(active, yearId: value);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s5),
                  if (_financeRequest != null)
                    FutureBuilder<Map<String, dynamic>>(
                      key: ValueKey('parent-finance-$_childId-$_yearId'),
                      future: _financeRequest,
                      builder: (context, finance) {
                        if (finance.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(AppSpacing.s8),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        if (finance.hasError) {
                          final message = finance.error is ApiException
                              ? (finance.error as ApiException).message
                              : 'Impossible de charger la situation financière.';
                          return AppCard(
                            child: Column(
                              children: [
                                Text(message),
                                const SizedBox(height: AppSpacing.s3),
                                FilledButton.icon(
                                  onPressed: _retry,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Réessayer'),
                                ),
                              ],
                            ),
                          );
                        }
                        return _FinanceContent(
                            data: finance.data ?? const <String, dynamic>{});
                      },
                    ),
                ],
              );
            },
          ),
        ],
      );
}

class _FinanceContent extends StatelessWidget {
  const _FinanceContent({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final summary = Map<String, dynamic>.from(
        data['summary'] as Map? ?? const <String, dynamic>{});
    final months = (data['months'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final regime = data['schoolRegime'];
    final history = (data['regimeHistory'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          title: data['studentName']?.toString() ?? 'Situation financière',
          subtitle: data['className']?.toString(),
          child: Wrap(
            spacing: AppSpacing.s3,
            runSpacing: AppSpacing.s2,
            children: [
              if (regime != null)
                AppBadge(
                  label: 'Régime actuel : ${_regimeLabel(regime)}',
                  variant: AppBadgeVariant.primary,
                ),
              AppBadge(
                label: '${summary['unpaidMonths'] ?? 0} mois à solder',
                variant: (summary['unpaidMonths'] as num? ?? 0) > 0
                    ? AppBadgeVariant.warning
                    : AppBadgeVariant.success,
              ),
              if ((summary['overdueMonths'] as num? ?? 0) > 0)
                AppBadge(
                  label: '${summary['overdueMonths']} paiement(s) en retard',
                  variant: AppBadgeVariant.danger,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        ResponsiveGrid(
          desktopColumns: 4,
          tabletColumns: 2,
          mobileColumns: 1,
          children: [
            _metric(
              context,
              'Montant attendu',
              _money(summary['expected']),
              Icons.receipt_long_outlined,
            ),
            _metric(
              context,
              'Montant payé',
              _money(summary['paid']),
              Icons.check_circle_outline,
            ),
            _metric(
              context,
              'Reste à payer',
              _money(summary['remaining']),
              Icons.account_balance_wallet_outlined,
            ),
            _metric(
              context,
              'Avance',
              (summary['advanceMonths'] as num? ?? 0) > 0
                  ? '${summary['advanceMonths']} mois déjà payé(s)'
                  : _money(summary['credit']),
              Icons.fast_forward_rounded,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s5),
        AppCard(
          title: 'Situation par mois',
          subtitle:
              'Chaque mois utilise le tarif réellement applicable à cette période.',
          child: months.isEmpty
              ? const Text('Aucune échéance mensuelle disponible.')
              : Column(
                  children: months.map((month) {
                    final monthKey = month['month']?.toString() ?? '';
                    final date = DateTime.tryParse('$monthKey-01');
                    const monthNames = [
                      'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
                      'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'
                    ];
                    final label = date == null
                        ? monthKey
                        : '${monthNames[date.month - 1]} ${date.year}';
                    final status = month['displayStatus'] ?? month['status'];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 620;
                          final details = [
                            'Tarif : ${_money(month['expected'])}',
                            'Payé : ${_money(month['paid'])}',
                            'Reste : ${_money(month['remaining'])}',
                            if (month['schoolRegime'] != null)
                              'Régime : ${_regimeLabel(month['schoolRegime'])}',
                          ];
                          if (narrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(label,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700)),
                                    ),
                                    _statusBadge(status),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(details.join(' · '), softWrap: true),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              SizedBox(
                                width: 150,
                                child: Text(label,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                              ),
                              Expanded(child: Text(details.join(' · '))),
                              const SizedBox(width: AppSpacing.s3),
                              _statusBadge(status),
                            ],
                          );
                        },
                      ),
                    );
                  }).toList(),
                ),
        ),
        if (regime != null && history.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s4),
          AppCard(
            title: 'Historique du régime',
            child: Column(
              children: history
                  .map((item) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history_rounded),
                        title: Text(_regimeLabel(item['schoolRegime'])),
                        subtitle: Text(
                          'À partir du ${item['effectiveDate']}'
                          '${item['endDate'] == null ? '' : ' · jusqu’au ${item['endDate']}'}',
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _metric(
          BuildContext context, String title, String value, IconData icon) =>
      AppCard(
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
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

  Widget _statusBadge(Object? status) {
    final value = status?.toString();
    return AppBadge(
      label: _statusLabel(value),
      variant: switch (value) {
        'paid' => AppBadgeVariant.success,
        'partial' => AppBadgeVariant.warning,
        'overdue' => AppBadgeVariant.danger,
        'no_tariff' => AppBadgeVariant.danger,
        _ => AppBadgeVariant.secondary,
      },
    );
  }
}
