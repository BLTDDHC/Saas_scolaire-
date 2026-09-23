import 'package:flutter/material.dart';
import '../../../shared/widgets/workspace_header.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../data/datasources/api_client.dart';
import '../../../data/models/evaluation_model.dart';
import '../../../data/models/grade_model.dart';
import '../../../data/models/student_model.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/responsive_grid.dart';

/// Écran canonique des évaluations : aucune génération locale et aucun T1 en dur.
class CanonicalGradesPage extends StatefulWidget {
  const CanonicalGradesPage({super.key});

  @override
  State<CanonicalGradesPage> createState() => _CanonicalGradesPageState();
}

class _CanonicalGradesPageState extends State<CanonicalGradesPage> {
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _loadedYearId;
  String? _classId;
  String? _cycleId;
  String? _levelId;
  String? _seriesId;
  String? _subjectId;
  String? _periodId;
  String? _resultEventCode;
  String? _evaluationId;
  List<Map<String, dynamic>> _periods = const [];
  List<Map<String, dynamic>> _series = const [];
  Map<String, dynamic>? _submissionStatus;
  Map<String, dynamic>? _officialResults;
  bool _showSubmissionTracking = false;
  bool _showOfficialRanking = true;
  bool _checkingBatchAvailability = false;
  bool _calculatingBatch = false;
  Map<String, String> _readyClassesForBatch = const {};
  final Map<String, TextEditingController> _gradeControllers = {};
  final Map<String, String> _presence = {};
  final Map<String, TextEditingController> _combinedGradeControllers = {};
  final Map<String, String> _combinedPresence = {};
  bool _combinedEntry = false;

  void _disposeControllersAfterFrame(
      Iterable<TextEditingController> controllers) {
    final pending = List<TextEditingController>.of(controllers);
    if (pending.isEmpty) return;
    // Une fenêtre de dialogue reste brièvement montée pendant son animation de
    // fermeture. Attendre sa sortie évite qu'un champ réutilise un contrôleur
    // déjà libéré lors de programmations successives.
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      for (final controller in pending) {
        controller.dispose();
      }
    });
  }

  @override
  void dispose() {
    for (final controller in _gradeControllers.values) {
      controller.dispose();
    }
    for (final controller in _combinedGradeControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _scheduleReloadIfNeeded(StoreService store) {
    final yearId = store.getSelectedAcademicYearId();
    if (!_loading && yearId != null && yearId != _loadedYearId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(store);
      });
    }
  }

  Future<void> _load(StoreService store) async {
    final yearId = store.getSelectedAcademicYearId();
    if (yearId == null || yearId.isEmpty) {
      setState(() {
        _error = 'Sélectionnez une année scolaire.';
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final periods = await store.academicPeriodsRemote(yearId);
      final series = store.currentUser?.role == UserRole.teacher
          ? const <Map<String, dynamic>>[]
          : await store.schoolSeriesRemote();
      await store.refreshEvaluationsRemote(academicYearId: yearId);
      if (!mounted) return;
      setState(() {
        _periods = periods;
        _series = series;
        _loadedYearId = yearId;
        _periodId = periods.any((item) => item['id'] == _periodId)
            ? _periodId
            : (periods.isEmpty ? null : periods.first['id']?.toString());
        _evaluationId = null;
        _readyClassesForBatch = const {};
        _clearGradeEditors();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error =
          'Impossible de charger les informations. Vous pouvez réessayer.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clearGradeEditors() {
    final previous = [
      ..._gradeControllers.values,
      ..._combinedGradeControllers.values,
    ];
    _gradeControllers.clear();
    _presence.clear();
    _combinedGradeControllers.clear();
    _combinedPresence.clear();
    _combinedEntry = false;
    // The previous TextFields remain mounted until the current frame is
    // committed. Disposing synchronously here makes Flutter Web reuse a
    // controller that has already been disposed when the context changes.
    _disposeControllersAfterFrame(previous);
  }

  List<({String value, String label})> _availableEvaluationKinds(
      StoreService store,
      {String? classId}) {
    final selectedClass = store
        .getClasses()
        .where((item) => item.id == (classId ?? _classId))
        .firstOrNull;
    if (selectedClass == null) return const [];
    final cycle = store
        .getSchoolCycles()
        .where((item) => item.id == selectedClass.cycleId)
        .firstOrNull;
    final levelId = selectedClass.structuredLevelId ?? selectedClass.levelId;
    final level =
        store.getSchoolLevels().where((item) => item.id == levelId).firstOrNull;
    final cycleCode = (cycle?.code ?? '').trim().toUpperCase();
    final levelCode = (level?.code ?? '').trim().toUpperCase();

    final options = <({String value, String label})>[];
    if (cycleCode == 'MATERNELLE' || cycleCode == 'PRIMAIRE') {
      options.add((value: 'composition', label: 'Composition'));
    } else {
      options
        ..add((value: 'devoir_1', label: 'Devoir 1'))
        ..add((value: 'devoir_2', label: 'Devoir 2'))
        ..add((value: 'composition', label: 'Composition'));
    }
    if (cycleCode == 'PRIMAIRE' && levelCode == 'CM2') {
      options
        ..add((value: 'cepe_test', label: 'CEPE test'))
        ..add((value: 'cepe_blanc', label: 'CEPE blanc'));
    } else if (cycleCode == 'COLLEGE' && levelCode == '3E') {
      options
        ..add((value: 'bepc_test', label: 'BEPC test'))
        ..add((value: 'bepc_blanc', label: 'BEPC blanc'));
    } else if (cycleCode == 'LYCEE' && levelCode == 'TERMINALE') {
      options
        ..add((value: 'bac_test', label: 'BAC test'))
        ..add((value: 'bac_blanc', label: 'BAC blanc'));
    }
    return options;
  }

  List<EvaluationModel> _contextEvaluations(StoreService store) {
    if (_classId == null || _subjectId == null || _periodId == null) {
      return const [];
    }
    return store.getEvaluationsForContext(
      classId: _classId!,
      subjectId: _subjectId!,
      periodId: _periodId,
      academicYearId: _loadedYearId ?? '',
    );
  }

  EvaluationModel? _selectedEvaluation(StoreService store) {
    final matches = _contextEvaluations(store)
        .where((item) => item.id == _evaluationId)
        .toList();
    return matches.isEmpty ? null : matches.first;
  }

  void _selectEvaluation(EvaluationModel evaluation, StoreService store) {
    _clearGradeEditors();
    final schoolClass = store
        .getClasses()
        .where((item) => item.id == evaluation.classId)
        .firstOrNull;
    final grades = store.getGradesByEvaluation(evaluation.id);
    for (final student in store
        .getStudents()
        .where((item) => item.classId == evaluation.classId)) {
      final matches =
          grades.where((item) => item.studentId == student.id).toList();
      final grade = matches.isEmpty ? null : matches.first;
      _gradeControllers[student.id] = TextEditingController(
        text: grade?.grade == null ? '' : _formatNumber(grade!.grade!),
      );
      _presence[student.id] = grade?.presence ?? 'not_recorded';
    }
    setState(() {
      _evaluationId = evaluation.id;
      _classId = evaluation.classId;
      _subjectId = evaluation.subjectId;
      _periodId = evaluation.periodId;
      if (schoolClass != null) {
        _cycleId = schoolClass.cycleId;
        _levelId = schoolClass.structuredLevelId ?? schoolClass.levelId;
      }
    });
  }

  String _formatNumber(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  String _readableError(Object error, String fallback) {
    if (error is ApiException && error.message.trim().isNotEmpty) {
      return AppToast.humanErrorMessage(error.message, fallback: fallback);
    }
    return fallback;
  }

  String? _eventCode(EvaluationModel evaluation) {
    if (evaluation.examCode != null && evaluation.examCode!.isNotEmpty) {
      return evaluation.examCode;
    }
    if (evaluation.type == 'composition') return 'composition';
    if (evaluation.type == 'devoir') {
      return evaluation.title.contains('2') ? 'devoir_2' : 'devoir_1';
    }
    return null;
  }

  String _eventLabel(String code) =>
      const {
        'devoir_1': 'Devoir 1',
        'devoir_2': 'Devoir 2',
        'composition': 'Composition',
        'cepe_test': 'CEPE test',
        'cepe_blanc': 'CEPE blanc',
        'bepc_test': 'BEPC test',
        'bepc_blanc': 'BEPC blanc',
        'bac_test': 'BAC test',
        'bac_blanc': 'BAC blanc',
      }[code] ??
      code;


  List<EvaluationModel> _ordinaryEvaluations(StoreService store) {
    const ordinary = {'devoir_1', 'devoir_2', 'composition'};
    final rows = _contextEvaluations(store)
        .where((item) => ordinary.contains(_eventCode(item)))
        .toList();
    const order = {'devoir_1': 1, 'devoir_2': 2, 'composition': 3};
    rows.sort((left, right) =>
        (order[_eventCode(left)] ?? 99).compareTo(order[_eventCode(right)] ?? 99));
    return rows;
  }

  String _combinedKey(String evaluationId, String studentId) =>
      '${evaluationId}|${studentId}';

  void _prepareCombinedEditors(StoreService store) {
    final previous = _combinedGradeControllers.values.toList();
    _combinedGradeControllers.clear();
    _combinedPresence.clear();
    final students = store.getStudents()
        .where((item) => item.classId == _classId)
        .toList()
      ..sort((a, b) {
        final byLast = a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
        if (byLast != 0) return byLast;
        final byFirst =
            a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
        return byFirst != 0 ? byFirst : a.id.compareTo(b.id);
      });
    for (final evaluation in _ordinaryEvaluations(store)) {
      final grades = store.getGradesByEvaluation(evaluation.id);
      for (final student in students) {
        final grade =
            grades.where((item) => item.studentId == student.id).firstOrNull;
        final key = _combinedKey(evaluation.id, student.id);
        _combinedGradeControllers[key] = TextEditingController(
          text: grade?.grade == null ? '' : _formatNumber(grade!.grade!),
        );
        _combinedPresence[key] = grade?.presence ?? 'not_recorded';
      }
    }
    _disposeControllersAfterFrame(previous);
  }

  GradeModel? _combinedGradeFor(
    EvaluationModel evaluation,
    StudentModel student,
  ) {
    final key = _combinedKey(evaluation.id, student.id);
    final raw = _combinedGradeControllers[key]?.text.trim() ?? '';
    final previousState = _combinedPresence[key] ?? 'not_recorded';
    final value = raw.isEmpty ? null : double.tryParse(raw.replaceAll(',', '.'));
    final state = raw.isEmpty
        ? (previousState == 'absent' ? 'absent' : 'not_recorded')
        : 'present';
    if (raw.isNotEmpty &&
        (value == null || value < 0 || value > evaluation.maxScore)) {
      return null;
    }
    return GradeModel(
      id: '',
      studentId: student.id,
      subjectId: evaluation.subjectId,
      eval: evaluation.title,
      grade: state == 'present' ? value : null,
      evaluationId: evaluation.id,
      presence: state,
      academicYearId: evaluation.academicYearId,
    );
  }

  Future<void> _saveCombinedGrades(
    StoreService store, {
    required bool submit,
  }) async {
    final evaluations = _ordinaryEvaluations(store)
        .where((item) => const {'draft', 'rejected'}.contains(item.status))
        .toList();
    if (evaluations.isEmpty || _classId == null) return;
    final students = store.getStudents()
        .where((item) => item.classId == _classId)
        .toList()
      ..sort((a, b) {
        final byLast = a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
        if (byLast != 0) return byLast;
        final byFirst =
            a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
        return byFirst != 0 ? byFirst : a.id.compareTo(b.id);
      });
    if (students.isEmpty) {
      AppToast.warning(context, 'Aucun élève inscrit dans cette classe.');
      return;
    }

    final sheets = <EvaluationModel, List<GradeModel>>{};
    for (final evaluation in evaluations) {
      final entries = <GradeModel>[];
      for (final student in students) {
        final key = _combinedKey(evaluation.id, student.id);
        final raw = _combinedGradeControllers[key]?.text.trim() ?? '';
        final value =
            raw.isEmpty ? null : double.tryParse(raw.replaceAll(',', '.'));
        if (raw.isNotEmpty &&
            (value == null || value < 0 || value > evaluation.maxScore)) {
          AppToast.error(
            context,
            'Note invalide pour ${student.fullName} — ${evaluation.title}.',
          );
          return;
        }
        final grade = _combinedGradeFor(evaluation, student)!;
        if (submit && grade.presence == 'not_recorded') {
          AppToast.warning(
            context,
            'Complétez ${evaluation.title} pour ${student.fullName} ou marquez l’élève absent.',
          );
          return;
        }
        entries.add(grade);
      }
      sheets[evaluation] = entries;
    }

    setState(() => _saving = true);
    try {
      for (final entry in sheets.entries) {
        await store.saveEvaluationGradesRemote(entry.key.id, entry.value);
      }
      if (submit) {
        for (final evaluation in evaluations) {
          await store.changeEvaluationStatusRemote(
            evaluation.id,
            'submitted',
          );
        }
        await store.refreshEvaluationsRemote(
          academicYearId: _loadedYearId,
          classId: _classId,
          subjectId: _subjectId,
          periodId: _periodId,
        );
      }
      if (!mounted) return;
      _prepareCombinedEditors(store);
      setState(() {});
      AppToast.success(
        context,
        submit
            ? 'Les notes programmées ont été enregistrées et soumises.'
            : 'Brouillon combiné enregistré.',
      );
    } catch (error) {
      if (mounted) {
        AppToast.error(
          context,
          _readableError(
            error,
            submit
                ? 'La validation combinée a échoué. Vérifiez les relevés avant de réessayer.'
                : 'Impossible d’enregistrer le brouillon combiné.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _separatePresenceField(
    StudentModel student, {
    required bool enabled,
  }) {
    final value = _presence[student.id] ?? 'not_recorded';
    return DropdownButtonFormField<String>(
      key: ValueKey('grade-presence-${student.id}'),
      isExpanded: true,
      initialValue: value,
      decoration: const InputDecoration(labelText: 'État', isDense: true),
      items: const [
        DropdownMenuItem(value: 'present', child: Text('Note')),
        DropdownMenuItem(value: 'absent', child: Text('Absent')),
        DropdownMenuItem(value: 'not_recorded', child: Text('Non noté')),
      ],
      onChanged: !enabled
          ? null
          : (next) => setState(() {
                final state = next ?? 'not_recorded';
                _presence[student.id] = state;
                if (state != 'present') {
                  _gradeControllers[student.id]?.clear();
                }
              }),
    );
  }

  Widget _combinedPresenceField(
    EvaluationModel evaluation,
    StudentModel student,
  ) {
    final key = _combinedKey(evaluation.id, student.id);
    final value = _combinedPresence[key] ?? 'not_recorded';
    return DropdownButtonFormField<String>(
      key: ValueKey('combined-presence-$key'),
      isExpanded: true,
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'État',
        isDense: true,
      ),
      items: const [
        DropdownMenuItem(value: 'present', child: Text('Note')),
        DropdownMenuItem(value: 'absent', child: Text('Absent')),
        DropdownMenuItem(value: 'not_recorded', child: Text('Non noté')),
      ],
      onChanged: _saving
          ? null
          : (next) => setState(() {
                final state = next ?? 'not_recorded';
                _combinedPresence[key] = state;
                if (state != 'present') {
                  _combinedGradeControllers[key]?.clear();
                }
              }),
    );
  }

  Widget _combinedGradeCell(
    EvaluationModel evaluation,
    StudentModel student, {
    required bool compact,
  }) {
    final key = _combinedKey(evaluation.id, student.id);
    final editable = const {'draft', 'rejected'}.contains(evaluation.status);
    return SizedBox(
      width: compact ? double.infinity : 185,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: ValueKey('combined-grade-$key'),
            controller: _combinedGradeControllers[key],
            enabled: editable && !_saving,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText:
                  '${_eventLabel(_eventCode(evaluation) ?? evaluation.type)} /${_formatNumber(evaluation.maxScore)}',
              isDense: true,
            ),
            onChanged: (value) {
              if (value.trim().isNotEmpty) {
                _combinedPresence[key] = 'present';
              }
            },
          ),
          const SizedBox(height: 6),
          _combinedPresenceField(evaluation, student),
        ],
      ),
    );
  }

  Widget _combinedEntryCard(
    StoreService store,
    List<StudentModel> students,
    List<EvaluationModel> evaluations,
  ) {
    return AppCard(
      key: const Key('combined-grade-entry-card'),
      title: 'Saisie combinée',
      subtitle:
          'Une seule vue pour les évaluations ordinaires réellement programmées dans ce contexte.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;
            if (compact) {
              return Column(
                children: students.map((student) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${student.lastName} ${student.firstName}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: AppSpacing.s3),
                        ...evaluations.map((evaluation) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                          child: _combinedGradeCell(
                            evaluation,
                            student,
                            compact: true,
                          ),
                        )),
                      ],
                    ),
                  ),
                )).toList(),
              );
            }
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  const DataColumn(label: Text('Nom et prénom')),
                  ...evaluations.map((evaluation) => DataColumn(
                    label: Text(_eventLabel(
                        _eventCode(evaluation) ?? evaluation.type)),
                  )),
                ],
                rows: students.map((student) => DataRow(cells: [
                  DataCell(SizedBox(
                    width: 210,
                    child: Text('${student.lastName} ${student.firstName}'),
                  )),
                  ...evaluations.map((evaluation) => DataCell(
                    _combinedGradeCell(
                      evaluation,
                      student,
                      compact: false,
                    ),
                  )),
                ])).toList(),
              ),
            );
          }),
          const SizedBox(height: AppSpacing.s4),
          Wrap(
            spacing: AppSpacing.s3,
            runSpacing: AppSpacing.s3,
            children: [
              AppButton(
                label: _saving ? 'Enregistrement…' : 'Enregistrer le brouillon',
                icon: Icons.save_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: _saving
                    ? null
                    : () => _saveCombinedGrades(store, submit: false),
              ),
              AppButton(
                key: const Key('submit-combined-grades'),
                label: _saving ? 'Validation…' : 'Valider les notes',
                icon: Icons.send_rounded,
                onPressed: _saving
                    ? null
                    : () => _saveCombinedGrades(store, submit: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _refreshBatchAvailability(StoreService store) async {
    final yearId = store.getSelectedAcademicYearId();
    final periodId = _periodId;
    if (yearId == null || periodId == null || _resultEventCode != null) {
      if (mounted) setState(() => _readyClassesForBatch = const {});
      return;
    }
    final candidates = store.getClassesByYear(yearId).where((schoolClass) {
      if (_cycleId != null && schoolClass.cycleId != _cycleId) return false;
      final levelId = schoolClass.structuredLevelId ?? schoolClass.levelId;
      if (_levelId != null && levelId != _levelId) return false;
      return true;
    }).toList();
    if (candidates.length < 2) {
      if (mounted) setState(() => _readyClassesForBatch = const {});
      return;
    }
    if (mounted) setState(() => _checkingBatchAvailability = true);
    final ready = <String, String>{};
    for (final schoolClass in candidates) {
      try {
        final responses = await Future.wait([
          store.submissionStatusRemote(schoolClass.id, periodId),
          store.schoolResultsRemote(schoolClass.id, periodId),
        ]);
        final submissions = responses[0];
        final results = responses[1];
        if (submissions['readyForCalculation'] == true &&
            results['calculationStatus']?.toString() != 'official') {
          ready[schoolClass.id] = schoolClass.name;
        }
      } catch (_) {
        // Une classe inaccessible ou incomplète ne bloque pas les autres.
      }
    }
    if (!mounted) return;
    setState(() {
      _readyClassesForBatch = ready;
      _checkingBatchAvailability = false;
    });
  }

  Future<void> _calculateAllReadyClasses(StoreService store) async {
    final periodId = _periodId;
    final classes = Map<String, String>.from(_readyClassesForBatch);
    if (periodId == null || classes.length < 2) return;
    setState(() {
      _calculatingBatch = true;
      _loading = true;
    });
    var calculatedCount = 0;
    final failures = <String>[];
    for (final entry in classes.entries) {
      try {
        await store.calculateSchoolResultsRemote(entry.key, periodId);
        calculatedCount++;
      } catch (error) {
        failures.add(
          '${entry.value} : ${_readableError(error, 'calcul impossible')}',
        );
      }
    }
    if (!mounted) return;
    if (_classId != null && classes.containsKey(_classId)) {
      try {
        final responses = await Future.wait([
          store.schoolResultsRemote(_classId!, periodId),
          store.submissionStatusRemote(_classId!, periodId),
        ]);
        if (mounted) {
          setState(() {
            _officialResults = responses[0];
            _submissionStatus = responses[1];
            _showSubmissionTracking = false;
            _showOfficialRanking =
                responses[0]['calculationStatus']?.toString() == 'official';
          });
        }
      } catch (_) {
        // Le bilan groupé ci-dessous conserve l'information utile.
      }
    }
    await _refreshBatchAvailability(store);
    if (!mounted) return;
    setState(() {
      _calculatingBatch = false;
      _loading = false;
    });
    if (failures.isEmpty) {
      AppToast.success(
        context,
        '$calculatedCount classes calculées. Les classements sont disponibles.',
      );
    } else if (calculatedCount > 0) {
      AppToast.warning(
        context,
        '$calculatedCount classe(s) calculée(s). ${failures.first}',
      );
    } else {
      AppToast.error(context, failures.first);
    }
  }

  String _formatSubmittedAt(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (parsed == null) return '—';
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${twoDigits(parsed.day)}/${twoDigits(parsed.month)}/${parsed.year} '
        '${twoDigits(parsed.hour)}:${twoDigits(parsed.minute)}';
  }

  List<Map<String, dynamic>> _groupSubmissionRows(Map<String, dynamic> status) {
    final serverGroups = status['teacherSubmissions'] as List?;
    if (serverGroups != null) {
      return serverGroups
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    }
    final groups = <String, Map<String, dynamic>>{};
    final rows = List<Map<String, dynamic>>.from(
        (status['submissions'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map)));
    for (final row in rows) {
      final key = row['teacherId']?.toString() ?? row['teacher'].toString();
      final group = groups.putIfAbsent(
          key,
          () => {
                'teacherId': row['teacherId'],
                'teacher': row['teacher'],
                'class': row['class'],
                'subjects': <String>[],
                'submittedElements': <String>[],
                'status': 'submitted',
                'submittedAt': null,
              });
      final subjects = group['subjects'] as List<String>;
      final subject = row['subject']?.toString();
      if (subject != null &&
          subject.isNotEmpty &&
          !subjects.contains(subject)) {
        subjects.add(subject);
      }
      if (row['status'] != 'submitted') group['status'] = 'pending';
      final names = group['submittedElements'] as List<String>;
      for (final raw in row['elements'] as List? ?? const []) {
        final element = Map<String, dynamic>.from(raw as Map);
        if (!const {'submitted', 'validated', 'locked'}
            .contains(element['status'])) {
          continue;
        }
        final name = element['name']?.toString();
        if (name != null && name.isNotEmpty && !names.contains(name)) {
          names.add(name);
        }
        final timestamp = element['submittedAt']?.toString();
        final current = group['submittedAt']?.toString();
        if (timestamp != null &&
            (current == null || timestamp.compareTo(current) > 0)) {
          group['submittedAt'] = timestamp;
        }
      }
    }
    return groups.values.toList();
  }

  Future<void> _programEvaluation(StoreService store) async {
    if (_periodId == null) {
      AppToast.warning(
          context, 'Sélectionnez d’abord une période pédagogique.');
      return;
    }
    final classOptions = store.getClassesByYear(_loadedYearId).toList()
      ..sort((left, right) => left.name.compareTo(right.name));
    if (classOptions.isEmpty) {
      AppToast.warning(context, 'Aucune classe disponible pour cette année.');
      return;
    }
    final cycleOptions = store
        .getSchoolCycles()
        .where((cycle) =>
            cycle.isActive &&
            classOptions.any((schoolClass) => schoolClass.cycleId == cycle.id))
        .toList()
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    if (cycleOptions.isEmpty) {
      AppToast.warning(
          context, 'Aucun cycle ne possède de classe cette année.');
      return;
    }
    var selectedCycleId = cycleOptions.any((cycle) => cycle.id == _cycleId)
        ? _cycleId!
        : cycleOptions.first.id;
    var levelScope = 'all';
    if (_levelId != null &&
        classOptions.any((schoolClass) =>
            schoolClass.cycleId == selectedCycleId &&
            (schoolClass.structuredLevelId ?? schoolClass.levelId) ==
                _levelId)) {
      levelScope = _levelId!;
    }
    String? excludedExamLevelId;

    List<dynamic> levelsForCycle() {
      final classLevelIds = classOptions
          .where((item) => item.cycleId == selectedCycleId)
          .map((item) => item.structuredLevelId ?? item.levelId)
          .whereType<String>()
          .toSet();
      final levels = store
          .getSchoolLevelsByCycleId(selectedCycleId)
          .where((level) =>
              level.status == 'active' && classLevelIds.contains(level.id))
          .toList();
      levels.sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
      return levels;
    }

    dynamic examLevel() {
      final cycle =
          cycleOptions.where((item) => item.id == selectedCycleId).firstOrNull;
      final expectedCode = switch ((cycle?.code ?? '').toUpperCase()) {
        'PRIMAIRE' => 'CM2',
        'COLLEGE' => '3E',
        'LYCEE' => 'TERMINALE',
        _ => null,
      };
      if (expectedCode == null) return null;
      return levelsForCycle()
          .where((level) => level.code.toUpperCase() == expectedCode)
          .firstOrNull;
    }

    List<dynamic> targetClasses() {
      return classOptions.where((schoolClass) {
        if (schoolClass.cycleId != selectedCycleId) return false;
        final classLevelId =
            schoolClass.structuredLevelId ?? schoolClass.levelId;
        if (levelScope != 'all' && classLevelId != levelScope) return false;
        if (levelScope == 'all' &&
            excludedExamLevelId != null &&
            classLevelId == excludedExamLevelId) {
          return false;
        }
        return true;
      }).toList();
    }

    List<({String value, String label})> commonKinds() {
      final targets = targetClasses();
      if (targets.isEmpty) return const [];
      var common = _availableEvaluationKinds(store, classId: targets.first.id);
      for (final schoolClass in targets.skip(1)) {
        final allowed =
            _availableEvaluationKinds(store, classId: schoolClass.id)
                .map((item) => item.value)
                .toSet();
        common = common.where((item) => allowed.contains(item.value)).toList();
      }
      return common;
    }

    String? evaluationKind = commonKinds().firstOrNull?.value;
    var submitting = false;
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final levels = levelsForCycle();
          final excludedLevel = examLevel();
          final targets = targetClasses();
          final kindOptions = commonKinds();
          return AlertDialog(
            title: const Text('Programmer une évaluation'),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Période : ${_periods.where((item) => item['id'] == _periodId).firstOrNull?['name'] ?? '—'}'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: const Key('program-cycle'),
                      initialValue: selectedCycleId,
                      decoration: const InputDecoration(labelText: 'Cycle *'),
                      items: cycleOptions
                          .map((cycle) => DropdownMenuItem(
                              value: cycle.id, child: Text(cycle.name)))
                          .toList(),
                      onChanged: submitting
                          ? null
                          : (value) => setDialogState(() {
                                if (value == null) return;
                                selectedCycleId = value;
                                levelScope = 'all';
                                excludedExamLevelId = null;
                                evaluationKind =
                                    commonKinds().firstOrNull?.value;
                              }),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const Key('program-level-scope'),
                      initialValue: levelScope,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Niveaux concernés *'),
                      items: [
                        const DropdownMenuItem(
                            value: 'all', child: Text('Tous les niveaux')),
                        ...levels.map((level) => DropdownMenuItem(
                            value: level.id, child: Text(level.name))),
                      ],
                      onChanged: submitting
                          ? null
                          : (value) => setDialogState(() {
                                levelScope = value ?? 'all';
                                excludedExamLevelId = null;
                                evaluationKind =
                                    commonKinds().firstOrNull?.value;
                              }),
                    ),
                    if (levelScope == 'all' && excludedLevel != null) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        key: const Key('program-excluded-exam-level'),
                        initialValue: excludedExamLevelId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Exclure un niveau d’examen'),
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null, child: Text('Aucun')),
                          DropdownMenuItem<String?>(
                            value: excludedLevel.id,
                            child: Text(excludedLevel.name),
                          ),
                        ],
                        onChanged: submitting
                            ? null
                            : (value) => setDialogState(() {
                                  excludedExamLevelId = value;
                                  evaluationKind =
                                      commonKinds().firstOrNull?.value;
                                }),
                      ),
                    ],
                    const SizedBox(height: 12),
                    AppCard(
                      child: Text(
                        targets.isEmpty
                            ? 'Aucune classe ne correspond à cette sélection.'
                            : '${targets.length} classe(s) concernée(s) : '
                                '${targets.map((item) => item.name).join(', ')}',
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (targets.isEmpty)
                      const Text('Choisissez un niveau possédant une classe.')
                    else if (kindOptions.isEmpty)
                      const Text(
                          'Les classes sélectionnées n’ont aucun type d’évaluation commun.')
                    else
                      SizedBox(
                        key: const Key('program-evaluation-kind'),
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          key: ValueKey(
                              'evaluation-$selectedCycleId-$levelScope-$excludedExamLevelId'),
                          initialValue: evaluationKind,
                          decoration:
                              const InputDecoration(labelText: 'Évaluation *'),
                          items: kindOptions
                              .map((item) => DropdownMenuItem(
                                  value: item.value, child: Text(item.label)))
                              .toList(),
                          onChanged: submitting
                              ? null
                              : (value) =>
                                  setDialogState(() => evaluationKind = value),
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'La matière et l’enseignant seront déterminés automatiquement par les affectations actives.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    submitting ? null : () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                key: const Key('create-evaluation-program'),
                onPressed: submitting
                    ? null
                    : () async {
                        if (evaluationKind == null || targetClasses().isEmpty) {
                          AppToast.error(context,
                              'Choisissez un cycle, un niveau et une évaluation.');
                          return;
                        }
                        setDialogState(() => submitting = true);
                        try {
                          final code = evaluationKind!;
                          final examCode = code;
                          final type = code.startsWith('devoir_')
                              ? 'devoir'
                              : code == 'composition'
                                  ? 'composition'
                                  : (code.endsWith('_test')
                                      ? 'test'
                                      : 'exam_blanc');
                          final label = kindOptions
                              .where((item) => item.value == code)
                              .first
                              .label;
                          final evaluations =
                              await store.createEvaluationProgramRemote({
                            'title': label,
                            'type': type,
                            'examCode': examCode,
                            'classIds':
                                targetClasses().map((item) => item.id).toList(),
                            'periodId': _periodId,
                          });
                          if (!context.mounted) return;
                          _evaluationId = null;
                          Navigator.pop(context, true);
                          AppToast.success(context,
                              'Événement programmé : ${evaluations.length} relevé(s) généré(s) depuis les affectations.');
                        } catch (error) {
                          if (context.mounted) {
                            AppToast.error(
                                context,
                                _readableError(error,
                                    'Impossible de programmer cette évaluation.'));
                            setDialogState(() => submitting = false);
                          }
                        }
                      },
                child: Text(submitting ? 'Création…' : 'Créer'),
              ),
            ],
          );
        },
      ),
    );
    if (created == true && mounted) {
      await store.refreshEvaluationsRemote(academicYearId: _loadedYearId);
      if (mounted) {
        AppToast.info(context,
            'Les enseignants concernés ont été avertis dans leur espace.');
      }
    }
  }

  Future<void> _saveGrades(
      StoreService store, EvaluationModel evaluation) async {
    String? correctionReason;
    final administrativeCorrection =
        (store.isSuperAdmin() || store.currentUser?.role == UserRole.admin) &&
            const {'submitted', 'validated'}.contains(evaluation.status);
    if (administrativeCorrection) {
      final controller = TextEditingController();
      correctionReason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Motif de la correction'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Motif obligatoire (3 caractères minimum)'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.length >= 3) Navigator.pop(dialogContext, value);
              },
              child: const Text('Confirmer la correction'),
            ),
          ],
        ),
      );
      _disposeControllersAfterFrame([controller]);
      if (correctionReason == null) return;
    }
    if (!mounted) return;
    final students = store
        .getStudents()
        .where((item) => item.classId == evaluation.classId)
        .toList();
    if (students.isEmpty) {
      AppToast.warning(context, 'Aucun élève inscrit dans cette classe.');
      return;
    }
    final entries = <GradeModel>[];
    for (final student in students) {
      final previousState = _presence[student.id] ?? 'not_recorded';
      final raw = _gradeControllers[student.id]?.text.trim() ?? '';
      final value =
          raw.isEmpty ? null : double.tryParse(raw.replaceAll(',', '.'));
      final state = raw.isEmpty
          ? (previousState == 'absent' ? 'absent' : 'not_recorded')
          : 'present';
      if (raw.isNotEmpty &&
          (value == null || value < 0 || value > evaluation.maxScore)) {
        AppToast.error(
          context,
          'Note invalide pour ${student.fullName} (0 à ${_formatNumber(evaluation.maxScore)}).',
        );
        return;
      }
      entries.add(GradeModel(
        id: '',
        studentId: student.id,
        subjectId: evaluation.subjectId,
        eval: evaluation.title,
        grade: state == 'present' ? value : null,
        evaluationId: evaluation.id,
        presence: state,
        academicYearId: evaluation.academicYearId,
      ));
    }
    setState(() => _saving = true);
    try {
      await store.saveEvaluationGradesRemote(evaluation.id, entries,
          correctionReason: correctionReason);
      if (administrativeCorrection && _classId != null && _periodId != null) {
        _officialResults =
            await store.schoolResultsRemote(_classId!, _periodId!);
      }
      if (mounted) {
        AppToast.success(
            context,
            administrativeCorrection
                ? 'Correction enregistrée. Un nouveau calcul est requis.'
                : 'Notes enregistrées.');
      }
    } catch (error) {
      if (mounted) {
        AppToast.error(
          context,
          _readableError(
            error,
            'Impossible d’enregistrer les notes. Vérifiez les valeurs saisies.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeStatus(
      StoreService store, EvaluationModel evaluation, String status) async {
    String? reason;
    if (status == 'rejected') {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Motif du rejet'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Motif obligatoire'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.pop(context, value);
              },
              child: const Text('Rejeter'),
            ),
          ],
        ),
      );
      _disposeControllersAfterFrame([controller]);
      if (reason == null) return;
    }
    setState(() => _saving = true);
    try {
      final updated = await store.changeEvaluationStatusRemote(
        evaluation.id,
        status,
        reason: reason,
      );
      if (!mounted) return;
      _selectEvaluation(updated, store);
      AppToast.success(context, 'Statut mis à jour.');
    } catch (error) {
      if (mounted) {
        AppToast.error(
          context,
          _readableError(error, 'Impossible de modifier ce statut.'),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showResults(StoreService store) async {
    if (_classId == null || _periodId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final responses = await Future.wait([
        store.submissionStatusRemote(_classId!, _periodId!,
            eventCode: _resultEventCode),
        store.schoolResultsRemote(_classId!, _periodId!,
            eventCode: _resultEventCode),
      ]);
      if (!mounted) return;
      setState(() {
        _submissionStatus = responses[0];
        _officialResults = responses[1];
        _showSubmissionTracking = true;
        _showOfficialRanking =
            responses[1]['calculationStatus']?.toString() == 'official';
      });
      if (store.isSuperAdmin() || store.currentUser?.role == UserRole.admin) {
        await _refreshBatchAvailability(store);
      }
    } catch (error) {
      if (mounted) {
        AppToast.error(
          context,
          _readableError(
            error,
            'Impossible d’actualiser le suivi pour le moment.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _calculateResults(StoreService store) async {
    if (_classId == null || _periodId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final calculated = await store.calculateSchoolResultsRemote(
          _classId!, _periodId!,
          eventCode: _resultEventCode);
      final submissions = await store.submissionStatusRemote(
          _classId!, _periodId!,
          eventCode: _resultEventCode);
      if (!mounted) return;
      setState(() {
        _officialResults = calculated;
        _submissionStatus = submissions;
        _showSubmissionTracking = false;
        _showOfficialRanking = true;
      });
      await _refreshBatchAvailability(store);
      if (!mounted) return;
      AppToast.success(context, 'Résultats calculés.');
    } catch (error) {
      if (mounted) {
        AppToast.error(
          context,
          _readableError(
            error,
            'Le calcul ne peut pas être effectué pour le moment.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    _scheduleReloadIfNeeded(store);
    final yearId = store.getSelectedAcademicYearId();
    final isTeacher = store.currentUser?.role == UserRole.teacher;
    final teacherId = store.getCurrentTeacherId();
    final teacherAffectations = isTeacher
        ? store
            .getAffectations()
            .where((item) => item.teacherId == teacherId)
            .toList()
        : const [];
    final allowedClassIds =
        teacherAffectations.map((item) => item.classId).toSet();
    final yearClasses = store.getClassesByYear(yearId).where((item) {
      return !isTeacher || allowedClassIds.contains(item.id);
    }).toList();
    final allowedCycleIds =
        yearClasses.map((item) => item.cycleId).whereType<String>().toSet();
    final allowedLevelIds = yearClasses
        .map((item) => item.structuredLevelId ?? item.levelId)
        .whereType<String>()
        .toSet();
    final cycles = store
        .getSchoolCycles()
        .where((item) =>
            item.isActive && (!isTeacher || allowedCycleIds.contains(item.id)))
        .toList();
    final levels = _cycleId == null
        ? const <dynamic>[]
        : store
            .getSchoolLevelsByCycleId(_cycleId!)
            .where((item) =>
                item.status == 'active' &&
                (!isTeacher || allowedLevelIds.contains(item.id)))
            .toList();
    final classes = isTeacher
        ? yearClasses
        : yearClasses.where((item) {
            if (_cycleId != null && item.cycleId != _cycleId) return false;
            if (_levelId != null && item.levelId != _levelId) return false;
            if (_seriesId != null && item.seriesId != _seriesId) return false;
            return true;
          }).toList();
    final seriesOptions = _series
        .where((item) => item['cycleId']?.toString() == _cycleId)
        .toList();
    final allowedSubjectIds = teacherAffectations
        .where((item) => _classId == null || item.classId == _classId)
        .map((item) => item.subjectId)
        .toSet();
    final subjects = store
        .getSubjects()
        .where((item) => !isTeacher || allowedSubjectIds.contains(item.id))
        .toList();
    if (_classId != null && !classes.any((item) => item.id == _classId)) {
      _classId = null;
    }
    if (_subjectId != null && !subjects.any((item) => item.id == _subjectId)) {
      _subjectId = null;
    }
    if (isTeacher &&
        _classId != null &&
        _subjectId == null &&
        subjects.length == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _subjectId == null) {
          setState(() => _subjectId = subjects.single.id);
        }
      });
    }
    final evaluations = _contextEvaluations(store);
    final selected = _selectedEvaluation(store);
    final students = selected == null
        ? <StudentModel>[]
        : store
            .getStudents()
            .where((item) => item.classId == selected.classId)
            .toList();
    students.sort((left, right) {
      final byLastName =
          left.lastName.toLowerCase().compareTo(right.lastName.toLowerCase());
      if (byLastName != 0) return byLastName;
      final byFirstName =
          left.firstName.toLowerCase().compareTo(right.firstName.toLowerCase());
      return byFirstName != 0 ? byFirstName : left.id.compareTo(right.id);
    });
    final ordinaryEvaluations =
        isTeacher ? _ordinaryEvaluations(store) : <EvaluationModel>[];
    final combinedStudents = _classId == null
        ? <StudentModel>[]
        : store
            .getStudents()
            .where((item) => item.classId == _classId)
            .toList()
      ..sort((left, right) {
        final byLastName =
            left.lastName.toLowerCase().compareTo(right.lastName.toLowerCase());
        if (byLastName != 0) return byLastName;
        final byFirstName = left.firstName
            .toLowerCase()
            .compareTo(right.firstName.toLowerCase());
        return byFirstName != 0 ? byFirstName : left.id.compareTo(right.id);
      });
    final isAdmin =
        store.isSuperAdmin() || store.currentUser?.role == UserRole.admin;
    final availableEventCodes = store
        .getEvaluations()
        .where((item) => item.classId == _classId && item.periodId == _periodId)
        .map(_eventCode)
        .whereType<String>()
        .where(const {
          'cepe_test',
          'cepe_blanc',
          'bepc_test',
          'bepc_blanc',
          'bac_test',
          'bac_blanc',
        }.contains)
        .toSet()
        .toList()
      ..sort((left, right) {
        const order = [
          'cepe_test',
          'cepe_blanc',
          'bepc_test',
          'bepc_blanc',
          'bac_test',
          'bac_blanc',
        ];
        return order.indexOf(left).compareTo(order.indexOf(right));
      });
    final selectedEventCode = availableEventCodes.contains(_resultEventCode)
        ? _resultEventCode
        : null;
    if (_resultEventCode != selectedEventCode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _resultEventCode != selectedEventCode) {
          setState(() => _resultEventCode = selectedEventCode);
        }
      });
    }
    final teacherEditable = !isAdmin &&
        (selected?.status == 'draft' || selected?.status == 'rejected');
    final adminCorrection =
        isAdmin && const {'submitted', 'validated'}.contains(selected?.status);
    final editable = teacherEditable || adminCorrection;
    final calculationStatus =
        _officialResults?['calculationStatus']?.toString();
    final resultsReady = _submissionStatus?['readyForCalculation'] == true;
    final hasOfficialResults = calculationStatus == 'official';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkspaceHeader(
              title: isAdmin
                  ? 'Résultats — classement par ordre de mérite'
                  : 'Mes notes et résultats',
              subtitle: isAdmin
                  ? 'Sélectionnez une classe et une période pour consulter les soumissions et le classement global.'
                  : 'Choisissez une de vos classes et une période pour saisir les notes ou consulter les résultats officiels.'),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            AppCard(
              child: Row(children: [
                Expanded(
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red))),
                TextButton(
                    onPressed: () => _load(store),
                    child: const Text('Réessayer')),
              ]),
            ),
          AppCard(
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (isAdmin)
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _cycleId,
                      decoration: const InputDecoration(labelText: 'Cycle'),
                      items: cycles
                          .map((item) => DropdownMenuItem(
                              value: item.id, child: Text(item.name)))
                          .toList(),
                      onChanged: (value) => setState(() {
                        _cycleId = value;
                        _levelId = null;
                        _seriesId = null;
                        _classId = null;
                        if (isAdmin) _subjectId = null;
                        _evaluationId = null;
                        _submissionStatus = null;
                        _officialResults = null;
                        _readyClassesForBatch = const {};
                        _clearGradeEditors();
                      }),
                    ),
                  ),
                if (isAdmin)
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _levelId,
                      decoration: const InputDecoration(labelText: 'Niveau'),
                      items: levels
                          .map((item) => DropdownMenuItem<String>(
                              value: item.id, child: Text(item.name)))
                          .toList(),
                      onChanged: _cycleId == null
                          ? null
                          : (value) => setState(() {
                                _levelId = value;
                                _seriesId = null;
                                _classId = null;
                                if (isAdmin) _subjectId = null;
                                _evaluationId = null;
                                _submissionStatus = null;
                                _officialResults = null;
                                _readyClassesForBatch = const {};
                                _clearGradeEditors();
                              }),
                    ),
                  ),
                if (isAdmin && seriesOptions.isNotEmpty)
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String?>(
                      key: const Key('results-series-filter'),
                      isExpanded: true,
                      initialValue: _seriesId,
                      decoration: const InputDecoration(labelText: 'Série'),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Toutes les séries')),
                        ...seriesOptions
                            .map((item) => DropdownMenuItem<String?>(
                                  value: item['id']?.toString(),
                                  child: Text('${item['name']}'),
                                )),
                      ],
                      onChanged: (value) => setState(() {
                        _seriesId = value;
                        _classId = null;
                        _submissionStatus = null;
                        _officialResults = null;
                        _readyClassesForBatch = const {};
                      }),
                    ),
                  ),
                SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _classId,
                    decoration: InputDecoration(
                        labelText: isAdmin ? 'Classe' : '1. Classe'),
                    items: classes
                        .map((item) => DropdownMenuItem(
                            value: item.id, child: Text(item.name)))
                        .toList(),
                    onChanged: (value) => setState(() {
                      _classId = value;
                      _subjectId = null;
                      _evaluationId = null;
                      _submissionStatus = null;
                      _officialResults = null;
                      _clearGradeEditors();
                    }),
                  ),
                ),
                if (!isAdmin && subjects.length > 1)
                  SizedBox(
                    width: 250,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _subjectId,
                      decoration:
                          const InputDecoration(labelText: '2. Matière'),
                      items: subjects
                          .map((item) => DropdownMenuItem(
                              value: item.id, child: Text(item.name)))
                          .toList(),
                      onChanged: (value) => setState(() {
                        _subjectId = value;
                        _evaluationId = null;
                        _clearGradeEditors();
                      }),
                    ),
                  ),
                if (!isAdmin && subjects.length == 1)
                  AppBadge(
                    label: 'Matière : ${subjects.single.name}',
                    variant: AppBadgeVariant.primary,
                  ),
                SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _periodId,
                    decoration: InputDecoration(
                        labelText: isAdmin
                            ? 'Période pédagogique'
                            : '${subjects.length > 1 ? 3 : 2}. Période pédagogique'),
                    items: _periods
                        .map((item) => DropdownMenuItem(
                              value: item['id']?.toString(),
                              child: Text('${item['name']}'),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() {
                      _periodId = value;
                      _evaluationId = null;
                      _submissionStatus = null;
                      _officialResults = null;
                      _readyClassesForBatch = const {};
                      _clearGradeEditors();
                    }),
                  ),
                ),
                if (isAdmin)
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<String?>(
                      key: const Key('result-event-filter'),
                      isExpanded: true,
                      initialValue: selectedEventCode,
                      decoration: const InputDecoration(
                          labelText: 'Résultat à calculer'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Moyenne de la période'),
                        ),
                        ...availableEventCodes
                            .map((code) => DropdownMenuItem<String?>(
                                  value: code,
                                  child: Text(_eventLabel(code)),
                                )),
                      ],
                      onChanged: (value) => setState(() {
                        _resultEventCode = value;
                        _submissionStatus = null;
                        _officialResults = null;
                        _readyClassesForBatch = const {};
                        _showSubmissionTracking = false;
                        _showOfficialRanking = false;
                      }),
                    ),
                  ),
                if (!isAdmin)
                  AppButton(
                    label: 'Voir mes résultats',
                    icon: Icons.visibility_outlined,
                    onPressed: _loading || _classId == null || _periodId == null
                        ? null
                        : () => _showResults(store),
                  ),
              ],
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(height: AppSpacing.s4),
            LayoutBuilder(builder: (context, _) {
              final contextReady = _classId != null && _periodId != null;
              final actions = <Widget>[
                AppButton(
                  label: hasOfficialResults
                      ? 'Voir les résultats'
                      : resultsReady
                          ? 'Calculer les résultats'
                          : 'En attente',
                  icon: hasOfficialResults
                      ? Icons.visibility_outlined
                      : resultsReady
                          ? Icons.calculate_outlined
                          : Icons.hourglass_empty_rounded,
                  onPressed: !contextReady || _loading
                      ? null
                      : hasOfficialResults
                          ? () => setState(() {
                                _showOfficialRanking = true;
                                _showSubmissionTracking = false;
                              })
                          : resultsReady
                              ? () => _calculateResults(store)
                              : null,
                ),
                if (_readyClassesForBatch.length >= 2)
                  AppButton(
                    label: _calculatingBatch
                        ? 'Calcul des classes…'
                        : 'Calculer toutes les classes prêtes (${_readyClassesForBatch.length})',
                    icon: Icons.calculate_rounded,
                    variant: AppButtonVariant.secondary,
                    onPressed: _loading || _checkingBatchAvailability
                        ? null
                        : () => _calculateAllReadyClasses(store),
                  ),
                AppButton(
                  label: 'Actualiser le suivi',
                  icon: Icons.refresh,
                  variant: AppButtonVariant.secondary,
                  onPressed: contextReady ? () => _showResults(store) : null,
                ),
                AppButton(
                  label: 'Programmer une évaluation',
                  icon: Icons.add,
                  variant: AppButtonVariant.secondary,
                  onPressed: _loading ? null : () => _programEvaluation(store),
                ),
              ];
              return Wrap(
                spacing: AppSpacing.s3,
                runSpacing: AppSpacing.s3,
                children: actions,
              );
            }),
          ],
          const SizedBox(height: AppSpacing.s4),
          if (isAdmin && _showSubmissionTracking && _submissionStatus != null)
            AppCard(
              title: _submissionStatus!['readyForCalculation'] == true
                  ? 'Tous les relevés sont arrivés'
                  : 'Résultats en attente',
              subtitle: _submissionStatus!['readyForCalculation'] == true
                  ? 'Toutes les soumissions requises sont reçues. Les résultats peuvent être calculés.'
                  : '${_submissionStatus!['missingCount'] ?? 0} relevé(s) restent à recevoir.',
              child: Builder(builder: (context) {
                final detailRows = _groupSubmissionRows(_submissionStatus!);
                if (detailRows.isEmpty) {
                  return const Text(
                      'Aucune affectation pédagogique pour cette classe.');
                }
                final ready = _submissionStatus!['readyForCalculation'] == true;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ResponsiveDataTable(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Enseignant')),
                          DataColumn(label: Text('Classe')),
                          DataColumn(label: Text('Matières')),
                          DataColumn(label: Text('Évaluations soumises')),
                          DataColumn(label: Text('État')),
                          DataColumn(label: Text('Dernier envoi')),
                        ],
                        rows: detailRows
                            .map((row) => DataRow(cells: [
                                  DataCell(Text('${row['teacher'] ?? '—'}')),
                                  DataCell(Text('${row['class'] ?? '—'}')),
                                  DataCell(Text(
                                      (row['subjects'] as List? ?? const [])
                                          .join(', '))),
                                  DataCell(Text(
                                      (row['submittedElements'] as List? ??
                                                  const [])
                                              .isEmpty
                                          ? 'Aucune'
                                          : (row['submittedElements'] as List)
                                              .join(', '))),
                                  DataCell(Text(row['status'] == 'submitted'
                                      ? 'Soumis'
                                      : 'En attente')),
                                  DataCell(Text(
                                      _formatSubmittedAt(row['submittedAt']))),
                                ]))
                            .toList(),
                      ),
                    ),
                    if (ready)
                      const Padding(
                        padding: EdgeInsets.only(top: AppSpacing.s4),
                        child: Text(
                          'Tous les relevés sont reçus. Utilisez « Calculer les résultats ».',
                        ),
                      ),
                  ],
                );
              }),
            ),
          if (_showOfficialRanking && calculationStatus == 'official') ...[
            const SizedBox(height: AppSpacing.s4),
            AppCard(
              title: _resultEventCode == null
                  ? 'Classement / ordre de mérite'
                  : 'Résultats — ${_eventLabel(_resultEventCode!)}',
              subtitle: _resultEventCode == null
                  ? 'Moyennes officielles de la période sélectionnée.'
                  : 'Résultats officiels de cet événement uniquement.',
              child: Builder(builder: (context) {
                final rows = List<Map<String, dynamic>>.from(
                    (_officialResults!['students'] as List? ?? const [])
                        .map((item) => Map<String, dynamic>.from(item)));
                if (rows.isEmpty) {
                  return const Text(
                      'Aucun résultat calculable pour cette période.');
                }
                return ResponsiveDataTable(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Rang')),
                      DataColumn(label: Text('Nom')),
                      DataColumn(label: Text('Prénom')),
                      DataColumn(label: Text('Moyenne générale')),
                    ],
                    rows: rows
                        .map((row) => DataRow(cells: [
                              DataCell(Text('${row['rank'] ?? '—'}')),
                              DataCell(Text('${row['lastName'] ?? '—'}')),
                              DataCell(Text('${row['firstName'] ?? '—'}')),
                              DataCell(Text('${row['average'] ?? '—'}')),
                            ]))
                        .toList(),
                  ),
                );
              }),
            ),
          ],
          if (!isAdmin &&
              _officialResults != null &&
              calculationStatus != 'official')
            AppCard(
              title: 'Mes résultats',
              child: Text(calculationStatus == 'ready'
                  ? 'Les relevés sont complets ; les résultats ne sont pas encore officiels.'
                  : calculationStatus == 'stale'
                      ? 'Les résultats sont en cours de mise à jour.'
                      : 'Les résultats de cette classe ne sont pas encore disponibles.'),
            ),
          if (_periods.isEmpty && !_loading)
            const AppCard(
              child: Text(
                'Aucune période configurée. Créez les périodes dans Paramètres pédagogiques.',
              ),
            ),
          if (!isAdmin &&
              _classId != null &&
              _subjectId != null &&
              _periodId != null &&
              evaluations.isEmpty)
            const AppCard(
              title: 'Mes évaluations à compléter',
              child: Text(
                'Aucune évaluation n’a encore été préparée par l’ADMIN pour ce contexte.',
              ),
            ),
          if (!isAdmin && evaluations.isNotEmpty)
            AppCard(
              title:
                  '${subjects.length > 1 ? 4 : 3}. Mes évaluations à compléter',
              subtitle: ordinaryEvaluations.length >= 2
                  ? 'Choisissez la saisie séparée ou combinée pour les devoirs/composition programmés.'
                  : 'Sélectionnez une évaluation pour afficher immédiatement les élèves.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ordinaryEvaluations.length >= 2) ...[
                    Wrap(
                      spacing: AppSpacing.s2,
                      runSpacing: AppSpacing.s2,
                      children: [
                        ChoiceChip(
                          key: const Key('grade-entry-separated'),
                          selected: !_combinedEntry,
                          label: const Text('Saisie séparée'),
                          onSelected: _saving
                              ? null
                              : (_) => setState(() {
                                    _combinedEntry = false;
                                    _combinedGradeControllers.clear();
                                    _combinedPresence.clear();
                                  }),
                        ),
                        ChoiceChip(
                          key: const Key('grade-entry-combined'),
                          selected: _combinedEntry,
                          label: const Text('Saisie combinée'),
                          onSelected: _saving
                              ? null
                              : (_) {
                                  _prepareCombinedEditors(store);
                                  setState(() {
                                    _combinedEntry = true;
                                    _evaluationId = null;
                                  });
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s3),
                  ],
                  if (!_combinedEntry)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: evaluations
                          .map((evaluation) => ChoiceChip(
                                selected: evaluation.id == _evaluationId,
                                label: Text(
                                    '${evaluation.title} · ${evaluation.status}'),
                                onSelected: (_) =>
                                    _selectEvaluation(evaluation, store),
                              ))
                          .toList(),
                    ),
                ],
              ),
            ),
          if (!isAdmin &&
              _combinedEntry &&
              ordinaryEvaluations.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s4),
            _combinedEntryCard(store, combinedStudents, ordinaryEvaluations),
          ],
          if (!_combinedEntry && selected != null) ...[
            const SizedBox(height: AppSpacing.s4),
            AppCard(
              title: isAdmin
                  ? 'Correction administrative — ${selected.title}'
                  : '${selected.title} — /${_formatNumber(selected.maxScore)}',
              subtitle: isAdmin
                  ? 'Toute correction exige un motif et reste enregistrée dans l’historique.'
                  : 'Statut : ${selected.status}',
              child: students.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                          child:
                              Text('Aucun élève inscrit dans cette classe.')),
                    )
                  : Column(
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxWidth < 720;
                            if (compact) {
                              return Column(
                                children: students.map((student) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: AppCard(
                                      padding: const EdgeInsets.all(AppSpacing.s3),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${student.lastName} ${student.firstName}',
                                            style: const TextStyle(fontWeight: FontWeight.w700),
                                          ),
                                          const SizedBox(height: AppSpacing.s3),
                                          ResponsiveFormGrid(
                                            children: [
                                              TextField(
                                                key: ValueKey('grade-value-${student.id}'),
                                                controller: _gradeControllers[student.id],
                                                enabled: editable && !_saving,
                                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                decoration: InputDecoration(
                                                  labelText: 'Note /${_formatNumber(selected.maxScore)}',
                                                  helperText: 'Laissez vide si la note n’est pas renseignée.',
                                                ),
                                                onChanged: (value) {
                                                  if (value.trim().isNotEmpty) {
                                                    _presence[student.id] = 'present';
                                                  }
                                                },
                                              ),
                                              _separatePresenceField(
                                                student,
                                                enabled: editable && !_saving,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              );
                            }
                            return Column(
                              children: [
                                const Row(children: [
                                  Expanded(flex: 2, child: Text('Nom')),
                                  Expanded(flex: 2, child: Text('Prénom')),
                                  SizedBox(width: 160, child: Text('Note')),
                                  SizedBox(width: 150, child: Text('État')),
                                ]),
                                const SizedBox(height: 8),
                                ...students.map((student) => Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Row(children: [
                                        Expanded(flex: 2, child: Text(student.lastName, overflow: TextOverflow.ellipsis)),
                                        Expanded(flex: 2, child: Text(student.firstName, overflow: TextOverflow.ellipsis)),
                                        SizedBox(
                                          width: 160,
                                          child: TextField(
                                            key: ValueKey('grade-value-${student.id}'),
                                            controller: _gradeControllers[student.id],
                                            enabled: editable && !_saving,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            decoration: InputDecoration(
                                              labelText: 'Note /${_formatNumber(selected.maxScore)}',
                                            ),
                                            onChanged: (value) {
                                              if (value.trim().isNotEmpty) {
                                                _presence[student.id] = 'present';
                                              }
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        SizedBox(
                                          width: 150,
                                          child: _separatePresenceField(
                                            student,
                                            enabled: editable && !_saving,
                                          ),
                                        ),
                                      ]),
                                    )),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 10, runSpacing: 10, children: [
                          if (editable)
                            AppButton(
                              label: _saving
                                  ? 'Enregistrement…'
                                  : adminCorrection
                                      ? 'Corriger les notes'
                                      : 'Enregistrer',
                              icon: Icons.save_outlined,
                              onPressed: _saving
                                  ? null
                                  : () => _saveGrades(store, selected),
                            ),
                          if (teacherEditable)
                            AppButton(
                              label: 'Soumettre',
                              icon: Icons.send_outlined,
                              variant: AppButtonVariant.secondary,
                              onPressed: _saving
                                  ? null
                                  : () => _changeStatus(
                                      store, selected, 'submitted'),
                            ),
                          if (isAdmin && selected.status == 'submitted')
                            AppButton(
                              label: 'Valider',
                              icon: Icons.verified_outlined,
                              variant: AppButtonVariant.success,
                              onPressed: _saving
                                  ? null
                                  : () => _changeStatus(
                                      store, selected, 'validated'),
                            ),
                          if (isAdmin && selected.status == 'submitted')
                            AppButton(
                              label: 'Rejeter',
                              icon: Icons.close,
                              variant: AppButtonVariant.danger,
                              onPressed: _saving
                                  ? null
                                  : () => _changeStatus(
                                      store, selected, 'rejected'),
                            ),
                        ]),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

