import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/datasources/api_client.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_form_field.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../core/theme/app_spacing.dart';

class CalendarSettingsCard extends StatefulWidget {
  const CalendarSettingsCard({super.key});

  @override
  State<CalendarSettingsCard> createState() => _CalendarSettingsCardState();
}

class _CalendarSettingsCardState extends State<CalendarSettingsCard> {
  final _start = TextEditingController(text: '07:00');
  final _end = TextEditingController(text: '17:00');
  final _duration = TextEditingController(text: '60');
  final _pause = TextEditingController(text: '15');
  final _frequency = TextEditingController(text: '2');
  final Set<int> _days = {1, 2, 3, 4, 5};
  String? _loadedYearId;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  Future<void> _load(StoreService store, String yearId) async {
    if (_loadedYearId == yearId) return;
    _loadedYearId = yearId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await store.calendarSettingsRemote(yearId);
      if (!mounted) return;
      if (value != null) {
        _start.text = value['dayStart']?.toString() ?? '07:00';
        _end.text = value['dayEnd']?.toString() ?? '17:00';
        _duration.text = value['courseDurationMinutes']?.toString() ?? '60';
        _pause.text = value['pauseDurationMinutes']?.toString() ?? '15';
        _frequency.text = value['pauseFrequency']?.toString() ?? '2';
        _days
          ..clear()
          ..addAll((value['teachingDays'] as List? ?? const [1, 2, 3, 4, 5])
              .map((item) => int.parse(item.toString())));
      }
    } on Exception catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(StoreService store, String yearId) async {
    final duration = int.tryParse(_duration.text.trim());
    final pause = int.tryParse(_pause.text.trim());
    final frequency = int.tryParse(_frequency.text.trim());
    if (_days.isEmpty ||
        duration == null ||
        duration <= 0 ||
        pause == null ||
        pause < 0 ||
        frequency == null ||
        frequency <= 0 ||
        !RegExp(r'^\d{2}:\d{2}$').hasMatch(_start.text.trim()) ||
        !RegExp(r'^\d{2}:\d{2}$').hasMatch(_end.text.trim())) {
      AppToast.warning(context, 'Configuration horaire invalide.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await store.saveCalendarSettingsRemote({
        'academicYearId': yearId,
        'teachingDays': _days.toList()..sort(),
        'dayStart': _start.text.trim(),
        'dayEnd': _end.text.trim(),
        'courseDurationMinutes': duration,
        'pauseDurationMinutes': pause,
        'pauseFrequency': frequency,
      });
      if (mounted) AppToast.success(context, 'Calendrier scolaire enregistré.');
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = AppToast.humanErrorMessage(
              error.message,
              fallback: 'Impossible d’enregistrer cet horaire.',
            ));
      }
    } on Exception {
      if (mounted) setState(() => _error = 'Serveur indisponible.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    _duration.dispose();
    _pause.dispose();
    _frequency.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final yearId = store.getSelectedAcademicYearId();
    if (yearId != null && _loadedYearId != yearId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(store, yearId));
    }
    return AppCard(
      title: 'Calendrier et horaires scolaires',
      child: yearId == null
          ? const Text('Sélectionnez une année scolaire.')
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(
                      spacing: AppSpacing.s2,
                      children: List.generate(6, (index) {
                        final day = index + 1;
                        const labels = [
                          'Lun',
                          'Mar',
                          'Mer',
                          'Jeu',
                          'Ven',
                          'Sam'
                        ];
                        return FilterChip(
                          label: Text(labels[index]),
                          selected: _days.contains(day),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _days.add(day);
                            } else {
                              _days.remove(day);
                            }
                          }),
                        );
                      })),
                  const SizedBox(height: AppSpacing.s3),
                  Wrap(
                      spacing: AppSpacing.s3,
                      runSpacing: AppSpacing.s3,
                      children: [
                        SizedBox(
                            width: 180,
                            child: AppFormField(
                                label: 'Début', controller: _start)),
                        SizedBox(
                            width: 180,
                            child:
                                AppFormField(label: 'Fin', controller: _end)),
                        SizedBox(
                            width: 180,
                            child: AppFormField(
                                label: 'Durée cours (min)',
                                controller: _duration)),
                        SizedBox(
                            width: 180,
                            child: AppFormField(
                                label: 'Durée pause (min)',
                                controller: _pause)),
                        SizedBox(
                            width: 210,
                            child: AppFormField(
                                label: 'Pause tous les N cours',
                                controller: _frequency)),
                      ]),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.s3),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: AppSpacing.s3),
                  AppButton(
                      label: 'Enregistrer le calendrier',
                      isLoading: _saving,
                      onPressed: _saving ? null : () => _save(store, yearId)),
                ]),
    );
  }
}
