import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  String? _studentId;
  String? _yearId;
  Map<String, dynamic>? _data;
  bool _loading = false;
  String? _error;
  int _requestToken = 0;

  String _money(Object? value) {
    final amount = (value as num?)?.toInt();
    if (amount == null) return '—';
    return '${NumberFormat('#,##0', 'fr_FR').format(amount)} FCFA';
  }

  String _monthLabel(String raw) {
    final parts = raw.split('-');
    if (parts.length != 2) return raw;
    final month = int.tryParse(parts[1]);
    if (month == null || month < 1 || month > 12) return raw;
    const labels = [
      'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
      'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'
    ];
    return '${labels[month - 1]} ${parts[0]}';
  }

  String _statusLabel(Map<String, dynamic> row) {
    if (row['overdue'] == true) return 'En retard';
    return const {
          'paid': 'Payé',
          'partial': 'Partiellement payé',
          'unpaid': 'Impayé',
          'no_tariff': 'Tarif à configurer',
          'not_applicable': 'Non concerné',
        }[row['status']] ??
        'À vérifier';
  }

  String _regimeLabel(Object? value) => switch ('$value') {
        'part_time' => 'Mi-temps',
        'full_time' => 'Plein temps',
        _ => '—',
      };

  Future<void> _load() async {
    final studentId = _studentId;
    final yearId = _yearId;
    if (studentId == null || yearId == null) return;
    final token = ++_requestToken;
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
    });
    try {
      final value = await context
          .read<StoreService>()
          .parentFinanceSituationRemote(studentId, yearId);
      if (!mounted || token != _requestToken) return;
      setState(() {
        _data = value;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _error = 'Impossible de charger la situation financière.';
        _loading = false;
      });
    }
  }

  void _ensureSelection(StoreService store) {
    final students = store.getStudents();
    if (students.isEmpty) return;
    final validStudent =
        _studentId != null && students.any((item) => item.id == _studentId);
    if (!validStudent) {
      final first = students.first;
      _studentId = first.id;
      _yearId = first.academicYearId ?? store.getSelectedAcademicYearId();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    } else if (_yearId == null) {
      _yearId = students
              .firstWhere((item) => item.id == _studentId)
              .academicYearId ??
          store.getSelectedAcademicYearId();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    _ensureSelection(store);
    final students = store.getStudents();
    final selectedStudent =
        students.where((item) => item.id == _studentId).firstOrNull;
    final years = store.getAcademicYears().where((year) {
      if (selectedStudent == null || selectedStudent.academicYearId == null) {
        return true;
      }
      return year.id == selectedStudent.academicYearId;
    }).toList();

    return WorkspacePage(
      title: 'Paiements / Situation financière',
      subtitle:
          'Consultez les paiements, mois impayés, retards, avances et le reste à payer de chaque enfant.',
      children: [
        if (students.isEmpty)
          const AppEmptyState(
            iconData: Icons.account_balance_wallet_outlined,
            title: 'Aucun enfant rattaché',
            message:
                'L’administration doit rattacher votre compte parent à un élève.',
          )
        else ...[
          ResponsiveGrid(
            desktopColumns: 2,
            tabletColumns: 2,
            mobileColumns: 1,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('parent-finance-child'),
                isExpanded: true,
                initialValue: _studentId,
                decoration: const InputDecoration(labelText: 'Enfant'),
                items: students
                    .map((item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.fullName,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  final student =
                      students.firstWhere((item) => item.id == value);
                  setState(() {
                    _studentId = value;
                    _yearId = student.academicYearId ??
                        store.getSelectedAcademicYearId();
                    _data = null;
                    _error = null;
                  });
                  _load();
                },
              ),
              DropdownButtonFormField<String>(
                key: const Key('parent-finance-year'),
                isExpanded: true,
                initialValue:
                    years.any((item) => item.id == _yearId) ? _yearId : null,
                decoration:
                    const InputDecoration(labelText: 'Année scolaire'),
                items: years
                    .map((item) => DropdownMenuItem(
                          value: item.id,
                          child:
                              Text(item.name, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _yearId = value;
                    _data = null;
                    _error = null;
                  });
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s5),
          if (_loading)
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
                  Expanded(child: Text(_error!)),
                  TextButton(onPressed: _load, child: const Text('Réessayer')),
                ],
              ),
            )
          else if (_data != null)
            _content(_data!),
        ],
      ],
    );
  }

  Widget _content(Map<String, dynamic> data) {
    final months = (data['months'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final overdue = (data['overdueMonths'] as List? ?? const []).length;
    final unpaid = (data['unpaidMonths'] as List? ?? const []).length;
    final advanceMonths = (data['advanceMonths'] as List? ?? const []).length;
    final regime = data['schoolRegime'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WorkspaceHeader(
          title: '${data['studentName'] ?? 'Enfant'}',
          subtitle:
              '${data['className'] ?? 'Classe non renseignée'} · ${data['academicYearName'] ?? ''}',
        ),
        ResponsiveGrid(
          desktopColumns: regime == null ? 4 : 5,
          tabletColumns: 2,
          mobileColumns: 1,
          children: [
            _metric('Montant payé', _money(data['totalPaid']),
                Icons.payments_outlined, AppColors.success600),
            _metric('Reste à payer', _money(data['totalRemaining']),
                Icons.account_balance_wallet_outlined, AppColors.warning600),
            _metric('Mois impayés', '$unpaid', Icons.event_busy_outlined,
                AppColors.danger500),
            _metric('Paiements en retard', '$overdue',
                Icons.warning_amber_rounded, AppColors.danger500),
            if (regime != null)
              _metric('Régime actuel', _regimeLabel(regime),
                  Icons.schedule_outlined, AppColors.info600),
          ],
        ),
        const SizedBox(height: AppSpacing.s5),
        if (advanceMonths > 0 || (data['advanceAmount'] as num? ?? 0) > 0)
          AppCard(
            title: 'Avance',
            child: Text(
              '$advanceMonths mois payé(s) en avance · ${_money(data['advanceAmount'])}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        if (advanceMonths > 0 || (data['advanceAmount'] as num? ?? 0) > 0)
          const SizedBox(height: AppSpacing.s5),
        AppCard(
          title: 'Situation mensuelle',
          subtitle:
              'Chaque mois utilise le tarif applicable à sa période, sans modifier les paiements déjà validés.',
          child: months.isEmpty
              ? const Text('Aucune échéance mensuelle disponible.')
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 760) {
                      return Column(
                        children: months
                            .map((row) => Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: AppSpacing.s3),
                                  child: _monthCard(row),
                                ))
                            .toList(),
                      );
                    }
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Mois')),
                          DataColumn(label: Text('Régime')),
                          DataColumn(label: Text('Tarif applicable')),
                          DataColumn(label: Text('Déjà payé')),
                          DataColumn(label: Text('Reste')),
                          DataColumn(label: Text('Statut')),
                        ],
                        rows: months
                            .map((row) => DataRow(cells: [
                                  DataCell(Text(_monthLabel('${row['month']}'))),
                                  DataCell(
                                      Text(_regimeLabel(row['schoolRegime']))),
                                  DataCell(Text(_money(row['expected']))),
                                  DataCell(Text(_money(row['paid']))),
                                  DataCell(Text(_money(row['remaining']))),
                                  DataCell(Text(_statusLabel(row))),
                                ]))
                            .toList(),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _monthCard(Map<String, dynamic> row) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _monthLabel('${row['month']}'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.s2),
            if (row['schoolRegime'] != null)
              Text('Régime : ${_regimeLabel(row['schoolRegime'])}'),
            Text('Tarif applicable : ${_money(row['expected'])}'),
            Text('Déjà payé : ${_money(row['paid'])}'),
            Text('Reste : ${_money(row['remaining'])}'),
            Text('Statut : ${_statusLabel(row)}'),
          ],
        ),
      );

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
                          fontSize: 20, fontWeight: FontWeight.w800)),
                  Text(title),
                ],
              ),
            ),
          ],
        ),
      );
}
