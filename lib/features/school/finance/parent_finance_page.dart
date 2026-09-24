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

const _months = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

String _money(Object? value) {
  final amount = (value as num?)?.toInt() ?? 0;
  final raw = amount.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(raw[i]);
  }
  return '${buffer.toString()} FCFA';
}

String _monthLabel(String value) {
  final parts = value.split('-');
  if (parts.length != 2) return value;
  final month = int.tryParse(parts[1]);
  if (month == null || month < 1 || month > 12) return value;
  return '${_months[month - 1][0].toUpperCase()}${_months[month - 1].substring(1)} ${parts[0]}';
}

class ParentFinancePage extends StatefulWidget {
  const ParentFinancePage({super.key});

  @override
  State<ParentFinancePage> createState() => _ParentFinancePageState();
}

class _ParentFinancePageState extends State<ParentFinancePage> {
  bool _loadingChildren = true;
  bool _loadingSituation = false;
  String? _error;
  List<Map<String, dynamic>> _children = const [];
  String? _childId;
  String? _yearId;
  Map<String, dynamic>? _situation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadChildren());
  }

  List<Map<String, dynamic>> _years(Map<String, dynamic> child) =>
      (child['years'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

  Future<void> _loadChildren() async {
    setState(() {
      _loadingChildren = true;
      _error = null;
    });
    try {
      final rows =
          await context.read<StoreService>().parentDashboardChildrenRemote();
      if (!mounted) return;
      _children = rows;
      if (rows.isNotEmpty) {
        final selectedYear =
            context.read<StoreService>().getSelectedAcademicYearId();
        final years = _years(rows.first);
        final matching = years
            .where((item) => '${item['id']}' == selectedYear)
            .toList();
        _childId = '${rows.first['id']}';
        _yearId = years.isEmpty
            ? null
            : '${(matching.isEmpty ? years.first : matching.first)['id']}';
      }
      setState(() => _loadingChildren = false);
      if (_childId != null && _yearId != null) await _loadSituation();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingChildren = false;
        _error = error is ApiException
            ? error.message
            : 'Impossible de charger la situation financière.';
      });
    }
  }

  Future<void> _loadSituation() async {
    final childId = _childId;
    final yearId = _yearId;
    if (childId == null || yearId == null) return;
    setState(() {
      _loadingSituation = true;
      _situation = null;
      _error = null;
    });
    try {
      final value = await context
          .read<StoreService>()
          .parentFinanceSituationRemote(childId, yearId);
      if (!mounted || childId != _childId || yearId != _yearId) return;
      setState(() => _situation = value);
    } catch (error) {
      if (!mounted || childId != _childId || yearId != _yearId) return;
      setState(() => _error = error is ApiException
          ? error.message
          : 'Impossible de charger la situation financière.');
    } finally {
      if (mounted && childId == _childId && yearId == _yearId) {
        setState(() => _loadingSituation = false);
      }
    }
  }

  void _selectChild(String id) {
    final child = _children.firstWhere((item) => '${item['id']}' == id);
    final years = _years(child);
    setState(() {
      _childId = id;
      _yearId = years.isEmpty ? null : '${years.first['id']}';
      _situation = null;
      _error = null;
    });
    if (_yearId != null) _loadSituation();
  }

  void _selectYear(String? id) {
    setState(() {
      _yearId = id;
      _situation = null;
      _error = null;
    });
    if (id != null) _loadSituation();
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
        title: 'Paiements / Situation financière',
        subtitle:
            'Consultez les paiements, les mois impayés, les retards et les avances de chaque enfant.',
        actions: [
          IconButton.filledTonal(
            onPressed: _loadingSituation || _childId == null || _yearId == null
                ? null
                : _loadSituation,
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        children: [
          if (_loadingChildren)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.s8),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_children.isEmpty)
            const AppEmptyState(
              iconData: Icons.family_restroom_outlined,
              title: 'Aucun enfant accessible',
              message:
                  'L’administration doit rattacher votre compte parent à un élève.',
            )
          else ...[
            _filters(),
            const SizedBox(height: AppSpacing.s4),
            if (_loadingSituation)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.s8),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              AppCard(
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.danger500),
                    const SizedBox(width: AppSpacing.s3),
                    Expanded(child: Text(_error!)),
                    TextButton(
                        onPressed: _loadSituation,
                        child: const Text('Réessayer')),
                  ],
                ),
              )
            else if (_situation != null)
              _content(_situation!),
          ],
        ],
      );

  Widget _filters() {
    final child = _children.firstWhere(
      (item) => '${item['id']}' == _childId,
      orElse: () => _children.first,
    );
    final years = _years(child);
    return ResponsiveGrid(
      desktopColumns: 2,
      tabletColumns: 2,
      mobileColumns: 1,
      children: [
        DropdownButtonFormField<String>(
          key: const Key('parent-finance-child'),
          isExpanded: true,
          initialValue: _childId,
          decoration: const InputDecoration(labelText: 'Enfant'),
          items: _children
              .map((item) => DropdownMenuItem(
                    value: '${item['id']}',
                    child: Text('${item['fullName']}',
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (value) {
            if (value != null) _selectChild(value);
          },
        ),
        DropdownButtonFormField<String>(
          key: const Key('parent-finance-year'),
          isExpanded: true,
          initialValue:
              years.any((item) => '${item['id']}' == _yearId) ? _yearId : null,
          decoration: const InputDecoration(labelText: 'Année scolaire'),
          items: years
              .map((item) => DropdownMenuItem(
                    value: '${item['id']}',
                    child: Text(
                      '${item['name'] ?? item['className'] ?? 'Année scolaire'}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: _selectYear,
        ),
      ],
    );
  }

  Widget _content(Map<String, dynamic> data) {
    final summary = Map<String, dynamic>.from(
        data['summary'] as Map? ?? const <String, dynamic>{});
    final months = (data['months'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final currentRegime = data['currentRegimeLabel']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          title: data['studentName']?.toString() ?? 'Situation financière',
          subtitle:
              '${data['className'] ?? 'Classe non renseignée'} · ${data['matricule'] ?? 'Matricule non renseigné'}',
          child: currentRegime == null
              ? const Text(
                  'Les montants affichés proviennent du système financier de l’établissement.')
              : Row(
                  children: [
                    const Icon(Icons.schedule_rounded,
                        color: AppColors.primary600),
                    const SizedBox(width: AppSpacing.s2),
                    Expanded(
                      child: Text('Régime actuel : $currentRegime',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
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
            _metric('Montant payé', _money(summary['paid']),
                Icons.payments_outlined, AppColors.success600),
            _metric('Reste à payer', _money(summary['remaining']),
                Icons.account_balance_wallet_outlined, AppColors.warning600),
            _metric('Avance', _money(summary['credit']),
                Icons.savings_outlined, AppColors.info600),
            _metric(
                'Mois impayés',
                '${summary['unpaidMonths'] ?? 0}',
                Icons.calendar_month_outlined,
                AppColors.danger500),
          ],
        ),
        const SizedBox(height: AppSpacing.s5),
        AppCard(
          title: 'Échéances mensuelles',
          subtitle:
              '${summary['overdueMonths'] ?? 0} paiement(s) en retard',
          child: months.isEmpty
              ? const Text('Aucune échéance mensuelle configurée.')
              : Column(
                  children: months.map((row) => _monthRow(row)).toList(),
                ),
        ),
      ],
    );
  }

  Widget _monthRow(Map<String, dynamic> row) {
    final status = '${row['displayStatus'] ?? row['status'] ?? 'unpaid'}';
    final label = switch (status) {
      'paid' => 'Payé',
      'partial' => 'Partiellement payé',
      'overdue' => 'En retard',
      'no_tariff' => 'Tarif à configurer',
      'not_applicable' => 'Non applicable',
      _ => 'Impayé',
    };
    final color = switch (status) {
      'paid' => AppColors.success600,
      'partial' => AppColors.warning600,
      'overdue' => AppColors.danger500,
      'no_tariff' => AppColors.warning600,
      'not_applicable' => AppColors.info600,
      _ => AppColors.danger500,
    };
    final regime = row['schoolRegimeLabel']?.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_monthLabel('${row['month']}'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                'Attendu : ${_money(row['expected'])} · Payé : ${_money(row['paid'])} · Reste : ${_money(row['remaining'])}',
              ),
              if (regime != null)
                Text('Régime applicable : $regime',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          );
          final badge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(label,
                style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                details,
                const SizedBox(height: AppSpacing.s2),
                badge,
                const Divider(height: AppSpacing.s5),
              ],
            );
          }
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: details),
                  const SizedBox(width: AppSpacing.s3),
                  badge,
                ],
              ),
              const Divider(height: AppSpacing.s5),
            ],
          );
        },
      ),
    );
  }

  Widget _metric(
    String title,
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
