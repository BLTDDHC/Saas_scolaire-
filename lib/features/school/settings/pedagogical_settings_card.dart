import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/date_utils.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_date_field.dart';
import '../../../shared/widgets/app_toast.dart';

/// Configuration relationnelle des périodes pédagogiques.
class PedagogicalSettingsCard extends StatefulWidget {
  const PedagogicalSettingsCard({super.key});

  @override
  State<PedagogicalSettingsCard> createState() =>
      _PedagogicalSettingsCardState();
}

class _PedagogicalSettingsCardState extends State<PedagogicalSettingsCard> {
  bool _loading = false;
  String? _error;
  String? _loadedYearId;
  List<Map<String, dynamic>> _periods = const [];

  void _scheduleLoad(StoreService store) {
    final yearId = store.getSelectedAcademicYearId();
    if (!_loading && yearId != null && yearId != _loadedYearId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(store);
      });
    }
  }

  Future<void> _load(StoreService store) async {
    final yearId = store.getSelectedAcademicYearId();
    if (yearId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final periods = await store.academicPeriodsRemote(yearId);
      if (!mounted) return;
      setState(() {
        _loadedYearId = yearId;
        _periods = periods;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editPeriod(
    StoreService store, [
    Map<String, dynamic>? existing,
  ]) async {
    const canonicalPeriods = <({String code, String name, int order})>[
      (code: 'T1', name: '1er trimestre', order: 1),
      (code: 'T2', name: '2e trimestre', order: 2),
      (code: 'T3', name: '3e trimestre', order: 3),
    ];
    final existingCode = existing?['code']?.toString().toUpperCase();
    var selectedCode = canonicalPeriods
        .where((item) => item.code == existingCode)
        .map((item) => item.code)
        .firstOrNull;
    selectedCode ??= canonicalPeriods
        .where((candidate) => !_periods.any((item) =>
            item['id'] != existing?['id'] &&
            item['code']?.toString().toUpperCase() == candidate.code))
        .map((item) => item.code)
        .firstOrNull;
    if (selectedCode == null) {
      AppToast.warning(context, 'Les trois trimestres sont déjà configurés.');
      return;
    }

    DateTime? startDate =
        AppDateUtils.parse(existing?['startDate']?.toString());
    DateTime? endDate = AppDateUtils.parse(existing?['endDate']?.toString());
    var saving = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final selected = canonicalPeriods
              .firstWhere((item) => item.code == selectedCode);
          final available = canonicalPeriods.where((candidate) =>
              candidate.code == selectedCode ||
              !_periods.any((item) =>
                  item['id'] != existing?['id'] &&
                  item['code']?.toString().toUpperCase() == candidate.code));
          return AlertDialog(
            title: Text(
              existing == null ? 'Ajouter un trimestre' : 'Modifier le trimestre',
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: selectedCode,
                      decoration:
                          const InputDecoration(labelText: 'Trimestre *'),
                      items: available
                          .map((item) => DropdownMenuItem(
                                value: item.code,
                                child: Text(item.name),
                              ))
                          .toList(),
                      onChanged: existing != null
                          ? null
                          : (value) => setDialogState(
                                () => selectedCode = value ?? selectedCode,
                              ),
                    ),
                    const SizedBox(height: 12),
                    AppDateField(
                      label: 'Début',
                      value: startDate,
                      onChanged: (value) =>
                          setDialogState(() => startDate = value),
                    ),
                    const SizedBox(height: 12),
                    AppDateField(
                      label: 'Fin',
                      value: endDate,
                      onChanged: (value) =>
                          setDialogState(() => endDate = value),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Les compositions mensuelles sont des évaluations du trimestre, pas des périodes scolaires.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (startDate != null &&
                            endDate != null &&
                            endDate!.isBefore(startDate!)) {
                          AppToast.error(
                            context,
                            'La date de fin doit suivre la date de début.',
                          );
                          return;
                        }
                        setDialogState(() => saving = true);
                        final payload = <String, dynamic>{
                          'academicYearId': _loadedYearId,
                          'code': selected.code,
                          'name': selected.name,
                          'periodType': 'trimester',
                          'sortOrder': selected.order,
                          if (startDate != null)
                            'startDate': AppDateUtils.toIso(startDate!),
                          if (endDate != null)
                            'endDate': AppDateUtils.toIso(endDate!),
                        };
                        try {
                          if (existing == null) {
                            await store.createAcademicPeriodRemote(payload);
                          } else {
                            await store.updateAcademicPeriodRemote(
                              existing['id'].toString(),
                              payload,
                            );
                          }
                          if (context.mounted) Navigator.pop(context, true);
                        } catch (error) {
                          if (context.mounted) {
                            AppToast.error(
                              context,
                              'Sauvegarde refusée : $error',
                            );
                            setDialogState(() => saving = false);
                          }
                        }
                      },
                child: Text(saving ? 'Sauvegarde…' : 'Sauvegarder'),
              ),
            ],
          );
        },
      ),
    );
    if (saved == true && mounted) await _load(store);
  }

  Future<void> _archive(
    StoreService store,
    Map<String, dynamic> item,
  ) async {
    try {
      await store.archiveAcademicPeriodRemote(item['id'].toString());
      if (mounted) {
        AppToast.success(context, 'Période archivée.');
        await _load(store);
      }
    } catch (error) {
      if (mounted) AppToast.error(context, 'Archivage refusé : $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    _scheduleLoad(store);
    final modules =
        store.getCurrentSchool()?.enabledModules ?? const <String>[];
    if (!modules.contains('grades')) return const SizedBox.shrink();

    return AppCard(
      title: 'Paramétrage pédagogique',
      subtitle: 'Uniquement les 1er, 2e et 3e trimestres de l’année scolaire.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                TextButton(
                  onPressed: () => _load(store),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Périodes scolaires',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              AppButton(
                label: 'Ajouter un trimestre',
                icon: Icons.add,
                size: AppButtonSize.small,
                onPressed: () => _editPeriod(store),
              ),
            ],
          ),
          if (_periods.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Aucune période configurée.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ..._periods.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${item['name']}'),
              subtitle: Text(
                '${AppDateUtils.formatNumeric(item['startDate']?.toString())} '
                '→ ${AppDateUtils.formatNumeric(item['endDate']?.toString())}',
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Modifier',
                    onPressed: () => _editPeriod(store, item),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Archiver',
                    onPressed: () => _archive(store, item),
                    icon: const Icon(Icons.archive_outlined),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
