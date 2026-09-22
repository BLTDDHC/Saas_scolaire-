import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../data/models/subject_model.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_toast.dart';

/// Configuration des matières dans un contexte année/niveau/série.
class PedagogicalCoefficientsCard extends StatefulWidget {
  const PedagogicalCoefficientsCard({super.key});

  @override
  State<PedagogicalCoefficientsCard> createState() =>
      _PedagogicalCoefficientsCardState();
}

class _PedagogicalCoefficientsCardState
    extends State<PedagogicalCoefficientsCard> {
  bool _loading = false;
  bool _editingSubjects = true;
  String? _error;
  String? _loadedYearId;
  String? _cycleId;
  String? _levelId;
  String? _seriesId;
  List<Map<String, dynamic>> _series = const [];
  final Map<String, String> _coefficients = {};
  final Map<String, String> _gradingScales = {};
  final Map<String, bool> _contributions = {};
  final Map<String, bool> _enabled = {};
  final Set<String> _savingSubjects = {};

  void _scheduleLoad(StoreService store) {
    final yearId = store.getSelectedAcademicYearId();
    if (!_loading && yearId != null && yearId != _loadedYearId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(store);
      });
    }
  }

  bool _isLycee(StoreService store, String? cycleId) {
    final matches =
        store.getSchoolCycles().where((cycle) => cycle.id == cycleId).toList();
    if (matches.isEmpty) return false;
    final value = '${matches.first.code} ${matches.first.name}'
        .toUpperCase()
        .replaceAll('É', 'E');
    return value.contains('LYCEE');
  }

  bool _usesConfigurableScale(StoreService store, String? cycleId) {
    final matches =
        store.getSchoolCycles().where((cycle) => cycle.id == cycleId).toList();
    if (matches.isEmpty) return false;
    final value = '${matches.first.code} ${matches.first.name}'
        .toUpperCase()
        .replaceAll('É', 'E');
    return value.contains('MATERNELLE') || value.contains('PRIMAIRE');
  }

  List<Map<String, dynamic>> _seriesForCycle(String? cycleId) =>
      _series.where((item) => item['cycleId']?.toString() == cycleId).toList();

  void _normalizeContext(StoreService store) {
    final cycles =
        store.getSchoolCycles().where((cycle) => cycle.isActive).toList();
    if (cycles.isEmpty) {
      _cycleId = null;
      _levelId = null;
      _seriesId = null;
      return;
    }
    if (!cycles.any((cycle) => cycle.id == _cycleId)) {
      final lycee = cycles.where((cycle) => _isLycee(store, cycle.id)).toList();
      _cycleId = (lycee.isEmpty ? cycles.first : lycee.first).id;
    }
    final levels = store
        .getSchoolLevelsByCycleId(_cycleId!)
        .where((level) => level.status == 'active')
        .toList();
    if (!levels.any((level) => level.id == _levelId)) {
      _levelId = levels.isEmpty ? null : levels.first.id;
    }
    if (!_isLycee(store, _cycleId)) {
      _seriesId = null;
    } else {
      final choices = _seriesForCycle(_cycleId);
      if (_seriesId != null &&
          !choices.any((item) => item['id']?.toString() == _seriesId)) {
        _seriesId = null;
      }
    }
  }

  Map<String, dynamic>? _settingFor(SubjectModel subject) {
    final matches = subject.levelSettings.where((setting) {
      final settingSeries = setting['seriesId']?.toString();
      return setting['academicYearId']?.toString() == _loadedYearId &&
          setting['schoolLevelId']?.toString() == _levelId &&
          settingSeries == _seriesId;
    }).toList();
    return matches.isEmpty ? null : matches.first;
  }

  Map<String, dynamic>? _seriesCoefficientSettingFor(SubjectModel subject) {
    if (_seriesId == null) return null;
    final matches = subject.levelSettings.where((setting) {
      return setting['academicYearId']?.toString() == _loadedYearId &&
          setting['seriesId']?.toString() == _seriesId &&
          setting['status'] == 'active' &&
          setting['coefficient'] != null;
    }).toList();
    return matches.isEmpty ? null : matches.first;
  }

  String _formatCoefficient(Object? value) {
    final number = value is num ? value.toDouble() : null;
    if (number == null) return '';
    return number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toString();
  }

  void _syncDrafts(StoreService store, {bool resetEditingMode = false}) {
    _coefficients.clear();
    _gradingScales.clear();
    _contributions.clear();
    _enabled.clear();
    for (final subject in store.getSubjects()) {
      final setting = _settingFor(subject);
      final coefficientSetting = setting?['coefficient'] != null
          ? setting
          : _seriesCoefficientSettingFor(subject);
      _coefficients[subject.id] =
          _formatCoefficient(coefficientSetting?['coefficient']);
      _gradingScales[subject.id] = _formatCoefficient(
          setting?['gradingScale'] ??
              (_usesConfigurableScale(store, _cycleId) ? 10 : 20));
      _contributions[subject.id] = setting?['contributesToAverage'] != false;
      _enabled[subject.id] = setting?['status'] == 'active';
    }
    if (resetEditingMode) {
      _editingSubjects =
          !store.getSubjects().any((subject) => _settingFor(subject) != null);
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
      await store.refreshSubjectsRemote();
      final series = await store.schoolSeriesRemote();
      if (!mounted) return;
      setState(() {
        _loadedYearId = yearId;
        _series = series;
        _normalizeContext(store);
        _syncDrafts(store, resetEditingMode: true);
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeContext(StoreService store, VoidCallback change) {
    setState(() {
      change();
      _normalizeContext(store);
      _syncDrafts(store, resetEditingMode: true);
    });
  }

  // Compatibilité technique : la sauvegarde UX utilise désormais _saveAll.
  // ignore: unused_element
  Future<void> _saveSubject(StoreService store, SubjectModel subject,
      bool isLycee, bool usesConfigurableScale) async {
    if (_loadedYearId == null || _levelId == null) {
      AppToast.warning(context, 'Sélectionnez un niveau.');
      return;
    }
    if (isLycee && _seriesId == null) {
      AppToast.warning(context, 'Sélectionnez une série.');
      return;
    }
    final raw = (_coefficients[subject.id] ?? '').trim().replaceAll(',', '.');
    final coefficient = raw.isEmpty ? null : double.tryParse(raw);
    final rawScale =
        (_gradingScales[subject.id] ?? '').trim().replaceAll(',', '.');
    final gradingScale =
        usesConfigurableScale ? double.tryParse(rawScale) : 20.0;
    final enabled = _enabled[subject.id] == true;
    if (enabled &&
        isLycee &&
        raw.isNotEmpty &&
        (coefficient == null || coefficient <= 0)) {
      AppToast.error(context, 'Le coefficient doit être un nombre positif.');
      return;
    }
    if (enabled && (gradingScale == null || gradingScale <= 0)) {
      AppToast.error(context, 'Le barème doit être un nombre positif.');
      return;
    }
    setState(() => _savingSubjects.add(subject.id));
    try {
      await store.saveSubjectLevelSettingRemote(subject.id, {
        'academicYearId': _loadedYearId,
        'schoolLevelId': _levelId,
        if (_seriesId != null) 'seriesId': _seriesId,
        'coefficient': isLycee ? coefficient : null,
        'gradingScale': gradingScale,
        'contributesToAverage': _contributions[subject.id] ?? true,
        'enabled': enabled,
      });
      if (!mounted) return;
      setState(() => _syncDrafts(store));
      AppToast.success(context, 'Matière mise à jour.');
    } catch (error) {
      if (mounted) AppToast.error(context, error.toString());
    } finally {
      if (mounted) setState(() => _savingSubjects.remove(subject.id));
    }
  }

  Future<void> _saveAll(StoreService store, List<SubjectModel> subjects,
      bool isLycee, bool usesConfigurableScale) async {
    if (_loadedYearId == null || _levelId == null) {
      AppToast.warning(context, 'Sélectionnez un niveau.');
      return;
    }
    if (isLycee && _seriesId == null) {
      AppToast.warning(context, 'Sélectionnez une série.');
      return;
    }
    final parsed = <String, double?>{};
    final parsedScales = <String, double>{};
    for (final subject in subjects) {
      final raw = (_coefficients[subject.id] ?? '').trim().replaceAll(',', '.');
      final coefficient = raw.isEmpty ? null : double.tryParse(raw);
      if (_enabled[subject.id] == true &&
          isLycee &&
          (coefficient == null || coefficient <= 0)) {
        AppToast.error(
            context, 'Coefficient manquant ou invalide pour ${subject.name}.');
        return;
      }
      parsed[subject.id] = coefficient;
      final rawScale =
          (_gradingScales[subject.id] ?? '').trim().replaceAll(',', '.');
      final gradingScale =
          usesConfigurableScale ? double.tryParse(rawScale) : 20.0;
      if (_enabled[subject.id] == true &&
          (gradingScale == null || gradingScale <= 0)) {
        AppToast.error(
            context, 'Barème manquant ou invalide pour ${subject.name}.');
        return;
      }
      parsedScales[subject.id] =
          gradingScale ?? (usesConfigurableScale ? 10 : 20);
    }
    setState(() => _savingSubjects.addAll(subjects.map((item) => item.id)));
    try {
      for (final subject in subjects) {
        await store.saveSubjectLevelSettingRemote(subject.id, {
          'academicYearId': _loadedYearId,
          'schoolLevelId': _levelId,
          if (_seriesId != null) 'seriesId': _seriesId,
          'coefficient': isLycee ? parsed[subject.id] : null,
          'gradingScale': parsedScales[subject.id],
          'contributesToAverage': _contributions[subject.id] ?? true,
          'enabled': _enabled[subject.id] == true,
        });
      }
      if (!mounted) return;
      setState(() {
        _syncDrafts(store);
        _editingSubjects = false;
      });
      AppToast.success(context, 'Coefficients enregistrés.');
    } catch (error) {
      if (mounted) {
        AppToast.error(
          context,
          error.toString().trim().isEmpty
              ? 'Impossible d’enregistrer les coefficients.'
              : error.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _savingSubjects.clear());
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    _scheduleLoad(store);
    final modules =
        store.getCurrentSchool()?.enabledModules ?? const <String>[];
    if (!modules.contains('subjects')) {
      return const SizedBox.shrink();
    }
    final cycles =
        store.getSchoolCycles().where((cycle) => cycle.isActive).toList();
    final levels = _cycleId == null
        ? const <dynamic>[]
        : store
            .getSchoolLevelsByCycleId(_cycleId!)
            .where((level) => level.status == 'active')
            .toList();
    final series = _seriesForCycle(_cycleId);
    final subjects = store.getSubjects();
    final isLycee = _isLycee(store, _cycleId);
    final usesConfigurableScale = _usesConfigurableScale(store, _cycleId);
    final configuredSubjects =
        subjects.where((subject) => _enabled[subject.id] == true).toList();

    return AppCard(
      title: 'Matières et coefficients',
      subtitle: usesConfigurableScale
          ? 'Choisissez les matières enseignées et leur barème pour ce niveau.'
          : 'Choisissez les matières enseignées pour ce niveau${isLycee ? ' et cette série. Le coefficient appartient à la série sélectionnée' : ''}.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Row(children: [
            Expanded(
                child:
                    Text(_error!, style: const TextStyle(color: Colors.red))),
            TextButton(
                onPressed: () => _load(store), child: const Text('Réessayer')),
          ]),
        Wrap(spacing: AppSpacing.s3, runSpacing: AppSpacing.s3, children: [
          SizedBox(
            width: 230,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              key: const Key('pedagogy-cycle'),
              initialValue: _cycleId,
              decoration: const InputDecoration(labelText: 'Cycle'),
              items: cycles
                  .map((cycle) => DropdownMenuItem(
                      value: cycle.id, child: Text(cycle.name)))
                  .toList(),
              onChanged: _loading
                  ? null
                  : (value) => _changeContext(store, () {
                        _cycleId = value;
                        _levelId = null;
                        _seriesId = null;
                      }),
            ),
          ),
          SizedBox(
            width: 230,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              key: const Key('pedagogy-level'),
              initialValue: _levelId,
              decoration: const InputDecoration(labelText: 'Niveau'),
              items: levels
                  .map((level) => DropdownMenuItem<String>(
                      value: level.id, child: Text(level.name)))
                  .toList(),
              onChanged: _loading
                  ? null
                  : (value) => _changeContext(store, () => _levelId = value),
            ),
          ),
          if (isLycee)
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                key: const Key('pedagogy-series'),
                initialValue: _seriesId,
                decoration: const InputDecoration(labelText: 'Série *'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Choisir')),
                  ...series.map((item) => DropdownMenuItem<String?>(
                      value: item['id']?.toString(),
                      child: Text('${item['name']}'))),
                ],
                onChanged: _loading
                    ? null
                    : (value) => _changeContext(store, () => _seriesId = value),
              ),
            ),
        ]),
        const SizedBox(height: AppSpacing.s4),
        if (_levelId == null)
          const Text('Aucun niveau disponible pour ce cycle.')
        else if (subjects.isEmpty)
          const Text('Créez d’abord les matières à configurer.')
        else ...[
          Row(
            children: [
              const Expanded(
                child: Text('Matières enseignées',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              if (!_editingSubjects)
                TextButton.icon(
                  key: const Key('edit-subject-selection'),
                  onPressed: _savingSubjects.isEmpty
                      ? () => setState(() => _editingSubjects = true)
                      : null,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifier les matières'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          if (_editingSubjects)
            Wrap(
              spacing: AppSpacing.s3,
              runSpacing: AppSpacing.s2,
              children: subjects
                  .map((subject) => SizedBox(
                        width: 260,
                        child: CheckboxListTile(
                          key: ValueKey('enabled-${subject.id}'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(subject.name),
                          value: _enabled[subject.id] == true,
                          onChanged: _savingSubjects.contains(subject.id)
                              ? null
                              : (value) => setState(() {
                                    _enabled[subject.id] = value == true;
                                  }),
                        ),
                      ))
                  .toList(),
            )
          else
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${configuredSubjects.length} matière(s) configurée(s)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  ...configuredSubjects.indexed.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s1),
                      child: Text(
                        usesConfigurableScale
                            ? '${entry.$1 + 1}. ${entry.$2.name} — sur ${_gradingScales[entry.$2.id] ?? '10'}'
                            : '${entry.$1 + 1}. ${entry.$2.name}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.s4),
          if (configuredSubjects.isEmpty)
            const Text('Sélectionnez au moins une matière pour ce contexte.')
          else ...[
            Text(
                isLycee
                    ? 'Coefficients de la série'
                    : usesConfigurableScale
                        ? 'Barèmes par matière'
                        : 'Matières retenues',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.s2),
            ...configuredSubjects.map((subject) {
              final saving = _savingSubjects.contains(subject.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                child: AppCard(
                  child: Wrap(
                    spacing: AppSpacing.s3,
                    runSpacing: AppSpacing.s2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 220,
                        child: Text(subject.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(
                        width: 170,
                        child: isLycee
                            ? TextFormField(
                                key: ValueKey(
                                    'coefficient-${subject.id}-$_levelId-$_seriesId'),
                                initialValue: _coefficients[subject.id],
                                enabled: !saving,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Coefficient',
                                  hintText: 'Non configuré',
                                ),
                                onChanged: (value) =>
                                    _coefficients[subject.id] = value,
                              )
                            : usesConfigurableScale
                                ? TextFormField(
                                    key: ValueKey(
                                        'grading-scale-${subject.id}-$_levelId-$_seriesId'),
                                    initialValue: _gradingScales[subject.id],
                                    enabled: !saving,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: const InputDecoration(
                                      labelText: 'Barème',
                                      hintText: 'Ex. 10',
                                    ),
                                    onChanged: (value) =>
                                        _gradingScales[subject.id] = value,
                                  )
                                : const Text('Note sur 20'),
                      ),
                      SizedBox(
                        width: 250,
                        child: Row(children: [
                          Checkbox(
                            key: ValueKey('contribution-${subject.id}'),
                            value: _contributions[subject.id] ?? true,
                            onChanged: saving
                                ? null
                                : (value) => setState(() =>
                                    _contributions[subject.id] = value ?? true),
                          ),
                          const Expanded(
                              child: Text('Compte dans la moyenne générale')),
                        ]),
                      ),
                      AppButton(
                        key: ValueKey('save-subject-setting-${subject.id}'),
                        label: saving ? 'Enregistrement…' : 'Valider',
                        icon: Icons.check,
                        variant: AppButtonVariant.secondary,
                        onPressed: saving
                            ? null
                            : () => _saveSubject(
                                  store,
                                  subject,
                                  isLycee,
                                  usesConfigurableScale,
                                ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
        if (subjects.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s4),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              key: const Key('save-all-subject-settings'),
              label: _savingSubjects.isEmpty
                  ? (_editingSubjects
                      ? 'Enregistrer les modifications'
                      : 'Tout enregistrer')
                  : 'Enregistrement…',
              icon: Icons.save_outlined,
              onPressed: _savingSubjects.isEmpty
                  ? () => _saveAll(
                        store,
                        subjects,
                        isLycee,
                        usesConfigurableScale,
                      )
                  : null,
            ),
          ),
        ],
      ]),
    );
  }
}
