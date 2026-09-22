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
    final name = TextEditingController(text: existing?['name']?.toString());
    DateTime? startDate =
        AppDateUtils.parse(existing?['startDate']?.toString());
    DateTime? endDate = AppDateUtils.parse(existing?['endDate']?.toString());
    var type = existing?['periodType']?.toString() ?? 'trimester';
    String? parentPeriodId = existing?['parentPeriodId']?.toString();
    var sortOrder =
        (existing?['sortOrder'] as num?)?.toInt() ?? _periods.length;
    var saving = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            existing == null ? 'Nouvelle période' : 'Modifier la période',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nom *'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Type *'),
                    items: const [
                      DropdownMenuItem(
                        value: 'trimester',
                        child: Text('Trimestre'),
                      ),
                      DropdownMenuItem(
                        value: 'month',
                        child: Text('Mois / période mensuelle'),
                      ),
                      DropdownMenuItem(
                        value: 'custom',
                        child: Text('Période personnalisée'),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() {
                      type = value ?? type;
                      if (type == 'trimester') parentPeriodId = null;
                    }),
                  ),
                  if (type != 'trimester') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: parentPeriodId,
                      decoration: const InputDecoration(
                        labelText: 'Trimestre de rattachement *',
                      ),
                      items: _periods
                          .where(
                            (item) =>
                                item['periodType'] == 'trimester' &&
                                item['id'] != existing?['id'],
                          )
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item['id']?.toString(),
                              child: Text('${item['name']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => parentPeriodId = value),
                    ),
                  ],
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
                    onChanged: (value) => setDialogState(() => endDate = value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: '$sortOrder',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Ordre'),
                    onChanged: (value) =>
                        sortOrder = int.tryParse(value) ?? sortOrder,
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
                      if (name.text.trim().isEmpty ||
                          (type != 'trimester' && parentPeriodId == null)) {
                        AppToast.error(
                            context, 'Veuillez compléter les champs requis.');
                        return;
                      }
                      if (startDate != null &&
                          endDate != null &&
                          endDate!.isBefore(startDate!)) {
                        AppToast.error(context,
                            'La date de fin doit suivre la date de début.');
                        return;
                      }
                      setDialogState(() => saving = true);
                      final payload = <String, dynamic>{
                        'academicYearId': _loadedYearId,
                        if (existing?['code'] != null)
                          'code': existing!['code'],
                        'name': name.text.trim(),
                        'periodType': type,
                        if (parentPeriodId != null)
                          'parentPeriodId': parentPeriodId,
                        'sortOrder': sortOrder,
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
        ),
      ),
    );
    name.dispose();
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
      subtitle: 'Périodes pédagogiques de l’année scolaire sélectionnée.',
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
                label: 'Ajouter',
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
                '${item['periodType']} · '
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
