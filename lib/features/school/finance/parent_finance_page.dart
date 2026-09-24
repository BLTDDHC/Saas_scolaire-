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
  List<Map<String, dynamic>> _children = const [];
  String? _childId;
  String? _yearId;
  Future<Map<String, dynamic>>? _request;
  bool _loadingChildren = true;
  String? _childrenError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadChildren());
  }

  Future<void> _loadChildren() async {
    setState(() {
      _loadingChildren = true;
      _childrenError = null;
    });
    try {
      final children =
          await context.read<StoreService>().myChildrenForResultsRemote();
      if (!mounted) return;
      _children = children;
      if (children.isNotEmpty) {
        _selectChild(children.first);
      }
    } on Exception {
      if (mounted) {
        setState(() => _childrenError =
            'Impossible de charger les enfants liés à ce compte.');
      }
    } finally {
      if (mounted) setState(() => _loadingChildren = false);
    }
  }

  List<Map<String, dynamic>> _years(Map<String, dynamic> child) =>
      (child['years'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

  void _selectChild(Map<String, dynamic> child, {String? yearId}) {
    final years = _years(child);
    final selectedYear = years.any((item) => '${item['id']}' == yearId)
        ? yearId
        : (years.isEmpty ? null : '${years.first['id']}');
    setState(() {
      _childId = '${child['id']}';
      _yearId = selectedYear;
      _request = selectedYear == null
          ? null
          : context
              .read<StoreService>()
              .loadParentFinanceSituation(_childId!, selectedYear);
    });
  }

  String _money(Object? value) {
    final amount = (value as num?)?.toInt() ?? 0;
    final text = amount.toString();
    final parts = <String>[];
    for (var end = text.length; end > 0; end -= 3) {
      parts.add(text.substring(end - 3 < 0 ? 0 : end - 3, end));
    }
    return '${parts.reversed.join(' ')} FCFA';
  }

  String _monthLabel(String raw) {
    const months = [
      'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
      'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'
    ];
    final parts = raw.split('-');
    if (parts.length != 2) return raw;
    final month = int.tryParse(parts[1]);
    return month == null || month < 1 || month > 12
        ? raw
        : '${months[month - 1]} ${parts[0]}';
  }

  String _statusLabel(String status) => switch (status) {
        'paid' => 'Payé',
        'partial' => 'Partiellement payé',
        'unpaid' => 'Non payé',
        'no_tariff' => 'Tarif non configuré',
        _ => 'Non applicable',
      };

  @override
  Widget build(BuildContext context) => WorkspacePage(
        title: 'Paiements / Situation financière',
        subtitle:
            'Consultez les paiements, mois impayés, retards, avances et reste à payer de chaque enfant.',
        actions: [
          IconButton.filledTonal(
            onPressed: _childId == null || _yearId == null
                ? null
                : () => _selectChild(
                    _children.firstWhere((item) => '${item['id']}' == _childId),
                    yearId: _yearId),
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        children: [
          if (_loadingChildren)
            const Center(child: CircularProgressIndicator())
          else if (_childrenError != null)
            AppCard(child: Text(_childrenError!))
          else if (_children.isEmpty)
            const AppEmptyState(
              iconData: Icons.family_restroom_outlined,
              title: 'Aucun enfant accessible',
              message:
                  'L’administration doit rattacher votre compte parent à un élève.',
            )
          else ...[
            Builder(builder: (context) {
              final active = _children.firstWhere(
                (item) => '${item['id']}' == _childId,
                orElse: () => _children.first,
              );
              final years = _years(active);
              return ResponsiveGrid(
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
                        .map((item) => DropdownMenuItem(
                              value: '${item['id']}',
                              child: Text(
                                '${item['fullName']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      _selectChild(_children
                          .firstWhere((item) => '${item['id']}' == value));
                    },
                  ),
                  DropdownButtonFormField<String>(
                    key: const Key('parent-finance-year'),
                    isExpanded: true,
                    initialValue: years.any((item) => '${item['id']}' == _yearId)
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
                    onChanged: (value) => _selectChild(active, yearId: value),
                  ),
                ],
              );
            }),
            const SizedBox(height: AppSpacing.s4),
            if (_request != null)
              FutureBuilder<Map<String, dynamic>>(
                key: ValueKey('parent-finance-$_childId-$_yearId'),
                future: _request,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    final message = snapshot.error is ApiException
                        ? (snapshot.error as ApiException).message
                        : 'Impossible de charger la situation financière.';
                    return AppCard(child: Text(message));
                  }
                  return _content(snapshot.data ?? const {});
                },
              ),
          ],
        ],
      );

  Widget _content(Map<String, dynamic> data) {
    final summary = Map<String, dynamic>.from(
        data['summary'] as Map? ?? const <String, dynamic>{});
    final months = (data['months'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final overdue = (data['overdueMonths'] as List? ?? const []).length;
    final advance = (data['advanceMonths'] as List? ?? const []).length;
    final regime = data['regime']?.toString();
    final regimeLabel = regime == 'part_time'
        ? 'Mi-temps'
        : regime == 'full_time'
            ? 'Plein temps'
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          title: '${data['studentName'] ?? 'Enfant'}',
          subtitle: '${data['className'] ?? 'Classe non renseignée'}',
          child: Wrap(
            spacing: AppSpacing.s5,
            runSpacing: AppSpacing.s2,
            children: [
              if (regimeLabel != null)
                Text('Régime actuel : $regimeLabel',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('Retards : $overdue'),
              Text('Avances : $advance mois'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        ResponsiveGrid(
          desktopColumns: 3,
          tabletColumns: 3,
          mobileColumns: 1,
          children: [
            _metric('Montant prévu', _money(summary['expected']),
                Icons.receipt_long_outlined, AppColors.primary600),
            _metric('Montant payé', _money(summary['paid']),
                Icons.check_circle_outline, AppColors.success500),
            _metric('Reste à payer', _money(summary['remaining']),
                Icons.account_balance_wallet_outlined, AppColors.warning500),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        AppCard(
          title: 'Situation par mois',
          child: months.isEmpty
              ? const Text('Aucune échéance mensuelle disponible.')
              : Column(
                  children: months.map((row) {
                    final status = '${row['status'] ?? 'unpaid'}';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_monthLabel('${row['month'] ?? ''}')),
                      subtitle: Text(
                        'Tarif ${_money(row['expected'])} · Payé ${_money(row['paid'])} · Reste ${_money(row['remaining'])}',
                      ),
                      trailing: Text(
                        _statusLabel(status),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: status == 'paid'
                              ? AppColors.success500
                              : status == 'partial'
                                  ? AppColors.warning500
                                  : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _metric(String label, String value, IconData icon, Color color) =>
      AppCard(
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 20)),
                ],
              ),
            ),
          ],
        ),
      );
}
