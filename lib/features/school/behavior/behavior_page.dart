import 'package:flutter/material.dart';
import '../../../shared/widgets/workspace_header.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/establishment_types.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/behavior_assessment_model.dart';
import '../../../data/datasources/api_client.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_form_field.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/responsive_grid.dart';

class BehaviorPage extends StatefulWidget {
  const BehaviorPage({super.key});

  @override
  State<BehaviorPage> createState() => _BehaviorPageState();
}

class _BehaviorPageState extends State<BehaviorPage> {
  String? _cycleId;
  String? _levelId;
  String? _classId;
  String? _periodId;
  String? _periodsYearId;
  List<Map<String, dynamic>> _periods = const [];
  bool _loadingPeriods = false;
  String? _loadedKey;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _result;
  final Map<String, int> _stars = {};
  final Map<String, String> _comments = {};
  final Map<String, BehaviorAssessmentModel> _sent = {};

  Future<void> _loadPeriods(StoreService store, String yearId) async {
    if (_periodsYearId == yearId || _loadingPeriods) return;
    _periodsYearId = yearId;
    setState(() => _loadingPeriods = true);
    try {
      final periods = await store.academicPeriodsRemote(yearId);
      if (!mounted) return;
      setState(() {
        _periods = periods
            .where((item) =>
                item['periodType'] == 'trimester' &&
                item['status'] != 'archived')
            .toList()
          ..sort((left, right) => ((left['sortOrder'] as num?)?.toInt() ?? 0)
              .compareTo((right['sortOrder'] as num?)?.toInt() ?? 0));
        if (!_periods.any((item) => item['id'] == _periodId)) {
          _periodId = null;
          _resetContext();
        }
        _loadingPeriods = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingPeriods = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _load(
      StoreService store, String classId, String periodId) async {
    final yearId = store.getSelectedAcademicYearId();
    final key = '$classId|$yearId|$periodId';
    if (_loadedKey == key) return;
    _loadedKey = key;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final events = await store.behaviorEventsRemote(
        classId: classId,
        academicYearId: yearId,
        periodId: periodId,
      );
      if (!mounted || _loadedKey != key) return;
      setState(() {
        _stars.clear();
        _comments.clear();
        _sent.clear();
        for (final event in events.where((event) =>
            store.currentUser?.role == UserRole.teacher &&
            event.teacherId == store.getCurrentTeacherId())) {
          _stars[event.studentId] = event.score.round().clamp(1, 5);
          _comments[event.studentId] = event.comment ?? '';
          if (event.status == 'locked' || event.status == 'active') {
            _sent[event.studentId] = event;
          }
        }
        _loading = false;
      });
      if (store.currentUser?.role != UserRole.teacher) {
        final result = await store.behaviorResultsRemote(classId, periodId);
        if (mounted && _loadedKey == key) setState(() => _result = result);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _submit(StoreService store, List<dynamic> students,
      {bool draft = false}) async {
    final classId = _classId;
    final periodId = _periodId;
    final pending =
        students.where((student) => !_sent.containsKey(student.id)).toList();
    if (classId == null || periodId == null || pending.isEmpty) return;
    if (!draft && pending.any((student) => !_stars.containsKey(student.id))) {
      AppToast.warning(context,
          'Le relevé est incomplet. Renseignez tous les élèves avant de l’envoyer.');
      return;
    }
    final selected =
        pending.where((student) => _stars.containsKey(student.id)).toList();
    if (selected.isEmpty) {
      AppToast.warning(context,
          'Renseignez au moins un élève pour enregistrer le brouillon.');
      return;
    }
    setState(() => _saving = true);
    try {
      await store.submitBehaviorRemote(
        classId: classId,
        periodId: periodId,
        action: draft ? 'draft' : 'submit',
        entries: selected
            .map((student) => {
                  'studentId': student.id,
                  'stars': _stars[student.id]!,
                  if ((_comments[student.id] ?? '').trim().isNotEmpty)
                    'comment': _comments[student.id]!.trim(),
                })
            .toList(),
      );
      _loadedKey = null;
      await _load(store, classId, periodId);
      if (mounted) {
        AppToast.success(
          context,
          draft
              ? 'Brouillon enregistré.'
              : 'Comportements envoyés et verrouillés.',
        );
      }
    } catch (error) {
      if (mounted) {
        AppToast.error(
            context,
            error is ApiException && error.statusCode == 409
                ? 'Ce relevé est déjà envoyé ou une opération est en cours. Actualisez la page.'
                : error is ApiException && error.statusCode == 422
                    ? 'Le relevé est incomplet ou la liste des élèves a changé. Actualisez puis renseignez tous les élèves.'
                    : 'Impossible d’enregistrer le relevé. Vérifiez votre connexion et vos droits.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetContext() {
    _loadedKey = null;
    _stars.clear();
    _comments.clear();
    _sent.clear();
    _result = null;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final role = store.currentUser?.role;
    final isTeacher = role == UserRole.teacher;
    final yearId = store.getSelectedAcademicYearId();
    if (yearId != null &&
        yearId.isNotEmpty &&
        _periodsYearId != yearId &&
        !_loadingPeriods) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _loadPeriods(store, yearId));
    }
    final teacherId = store.getCurrentTeacherId();
    final allowedClassIds = isTeacher
        ? store
            .getAffectations()
            .where((item) =>
                item.teacherId == teacherId && item.academicYearId == yearId)
            .map((item) => item.classId)
            .toSet()
        : <String?>{};
    final yearClasses = store.getClassesByYear(yearId).where((item) {
      return !isTeacher || allowedClassIds.contains(item.id);
    }).toList();
    final allowedCycleIds =
        yearClasses.map((item) => item.cycleId).whereType<String>().toSet();
    final cycles = store
        .getSchoolCycles()
        .where((item) =>
            item.isActive && (!isTeacher || allowedCycleIds.contains(item.id)))
        .toList();
    final allowedLevelIds = yearClasses
        .map((item) => item.structuredLevelId ?? item.levelId)
        .whereType<String>()
        .toSet();
    final levels = _cycleId == null
        ? const <dynamic>[]
        : store
            .getSchoolLevelsByCycleId(_cycleId!)
            .where((item) =>
                item.status == 'active' &&
                (!isTeacher || allowedLevelIds.contains(item.id)))
            .toList();
    final classes = yearClasses.where((item) {
      final levelId = item.structuredLevelId ?? item.levelId;
      return (_cycleId == null || item.cycleId == _cycleId) &&
          (_levelId == null || levelId == _levelId);
    }).toList();
    if (_classId != null && !classes.any((item) => item.id == _classId)) {
      _classId = null;
      _resetContext();
    }
    final classId = _classId;
    final periodId = _periodId;
    final expectedKey = '$classId|$yearId|$periodId';
    if (classId != null && periodId != null && _loadedKey != expectedKey) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _load(store, classId, periodId));
    }
    final students = classId == null
        ? <dynamic>[]
        : store
            .getStudents()
            .where((student) => student.classId == classId)
            .toList();
    students.sort((left, right) {
      final byLastName = left.lastName
          .toString()
          .toLowerCase()
          .compareTo(right.lastName.toString().toLowerCase());
      return byLastName != 0
          ? byLastName
          : left.firstName
              .toString()
              .toLowerCase()
              .compareTo(right.firstName.toString().toLowerCase());
    });
    final pendingCount =
        students.where((student) => !_sent.containsKey(student.id)).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkspaceHeader(
              title: 'Comportement des élèves',
              subtitle: isTeacher
                  ? 'Attribuez 1 à 5 étoiles et un court commentaire, puis envoyez. L’envoi est définitif.'
                  : 'Consultation des comportements envoyés par les enseignants.'),
          Wrap(
            spacing: AppSpacing.s4,
            runSpacing: AppSpacing.s3,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              SizedBox(
                width: 220,
                child: AppSelectField<String?>(
                  label: 'Cycle',
                  value: _cycleId,
                  items: cycles
                      .map((item) => DropdownMenuItem<String?>(
                          value: item.id, child: Text(item.name)))
                      .toList(),
                  onChanged: (value) => setState(() {
                    _cycleId = value;
                    _levelId = null;
                    _classId = null;
                    _resetContext();
                  }),
                ),
              ),
              SizedBox(
                width: 220,
                child: AppSelectField<String?>(
                  label: 'Niveau',
                  value: _levelId,
                  items: levels
                      .map((item) => DropdownMenuItem<String?>(
                          value: item.id, child: Text(item.name)))
                      .toList(),
                  onChanged: _cycleId == null
                      ? null
                      : (value) => setState(() {
                            _levelId = value;
                            _classId = null;
                            _resetContext();
                          }),
                ),
              ),
              SizedBox(
                width: 280,
                child: AppSelectField<String?>(
                  label: 'Classe',
                  value: _classId,
                  items: classes
                      .map((item) => DropdownMenuItem<String?>(
                          value: item.id, child: Text(item.name)))
                      .toList(),
                  onChanged: _levelId == null
                      ? null
                      : (value) => setState(() {
                            _classId = value;
                            _resetContext();
                          }),
                ),
              ),
              SizedBox(
                width: 240,
                child: AppSelectField<String?>(
                  label: 'Trimestre',
                  value: _periodId,
                  items: _periods
                      .map((item) => DropdownMenuItem<String?>(
                            value: item['id'] as String?,
                            child: Text(item['name']?.toString() ?? ''),
                          ))
                      .toList(),
                  onChanged: _loadingPeriods
                      ? null
                      : (value) => setState(() {
                            _periodId = value;
                            _resetContext();
                          }),
                ),
              ),
              if (isTeacher)
                AppButton(
                  label: 'Enregistrer le brouillon',
                  onPressed: _saving ||
                          _loading ||
                          periodId == null ||
                          students.isEmpty ||
                          pendingCount == 0
                      ? null
                      : () => _submit(store, students, draft: true),
                ),
              if (isTeacher)
                AppButton(
                  label: _saving
                      ? 'Envoi…'
                      : pendingCount == 0 && students.isNotEmpty
                          ? 'Déjà envoyé'
                          : 'Envoyer et verrouiller',
                  icon: Icons.lock_outline_rounded,
                  onPressed: _saving ||
                          _loading ||
                          students.isEmpty ||
                          periodId == null ||
                          pendingCount == 0
                      ? null
                      : () => _submit(store, students),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s5),
          if (!isTeacher && classId != null && periodId != null)
            AppCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      '${_result?['receivedCount'] ?? 0} enseignant(s) sur ${_result?['expectedCount'] ?? 0} ont envoyé leur appréciation.'),
                  Text(switch (_result?['calculationStatus']) {
                    'official' => 'Résultat officiel disponible',
                    'ready' => 'Tous les relevés sont reçus',
                    'stale' =>
                      'Résultat obsolète : vérifiez les relevés puis recalculez',
                    _ => 'En attente des relevés',
                  }),
                  if ((_result?['teacherSubmissions'] as List? ?? const [])
                      .any((row) => row['status'] != 'submitted'))
                    Text(
                        'En attente : ${(_result?['teacherSubmissions'] as List? ?? const []).where((row) => row['status'] != 'submitted').map((row) => row['teacher']).join(', ')}'),
                  Wrap(spacing: 12, children: [
                    AppButton(
                        label: 'Actualiser le suivi',
                        onPressed: _loading
                            ? null
                            : () {
                                _loadedKey = null;
                                _load(store, classId, periodId);
                              }),
                    AppButton(
                        label: 'Calculer les moyennes',
                        onPressed: _saving ||
                                _result?['readyForCalculation'] != true
                            ? null
                            : () async {
                                setState(() => _saving = true);
                                try {
                                  final result =
                                      await store.calculateBehaviorRemote(
                                          classId, periodId);
                                  if (mounted &&
                                      _classId == classId &&
                                      _periodId == periodId)
                                    setState(() => _result = result);
                                } catch (_) {
                                  if (context.mounted)
                                    AppToast.error(context,
                                        'Impossible de calculer. Actualisez le suivi et vérifiez les relevés reçus.');
                                } finally {
                                  if (mounted) setState(() => _saving = false);
                                }
                              }),
                  ]),
                  if ((_result?['calculationStatus'] ?? '') == 'official') ...[
                    const SizedBox(height: AppSpacing.s4),
                    ResponsiveDataTable(
                        child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Rang')),
                        DataColumn(label: Text('Élève')),
                        DataColumn(label: Text('Enseignants')),
                        DataColumn(label: Text('Moyenne officielle')),
                      ],
                      rows: (List<Map<String, dynamic>>.from(
                              _result?['students'] as List? ?? const [])
                            ..sort((left, right) => (right['average'] as num)
                                .compareTo(left['average'] as num)))
                          .asMap()
                          .entries
                          .map((entry) => DataRow(cells: [
                                DataCell(Text('${entry.key + 1}')),
                                DataCell(Text(
                                    '${entry.value['student'] ?? 'Élève'}')),
                                DataCell(Text(
                                    '${entry.value['contributionCount'] ?? 0}')),
                                DataCell(Text(
                                    '${(entry.value['average'] as num).toStringAsFixed(2)} ★')),
                              ]))
                          .toList(),
                    )),
                  ],
                ])),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            AppCard(
              child: Column(children: [
                const Text(
                    'Impossible de charger les comportements. Vérifiez votre sélection puis réessayez.'),
                const SizedBox(height: AppSpacing.s3),
                AppButton(
                  label: 'Réessayer',
                  onPressed: () {
                    _loadedKey = null;
                    if (classId != null && periodId != null) {
                      _load(store, classId, periodId);
                    }
                  },
                ),
              ]),
            )
          else if (students.isEmpty || periodId == null)
            const AppCard(
                child: Center(
                    child: Text('Sélectionnez une classe et un trimestre.')))
          else if (isTeacher)
            AppCard(
              padding: EdgeInsets.zero,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Élève')),
                    DataColumn(label: Text('Étoiles')),
                    DataColumn(label: Text('Commentaire')),
                    DataColumn(label: Text('Statut')),
                  ],
                  rows: students.map((student) {
                    final locked = _sent.containsKey(student.id);
                    final stars = _stars[student.id];
                    return DataRow(cells: [
                      DataCell(Text(student.fullName)),
                      DataCell(
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            value: stars,
                            hint: const Text('À renseigner'),
                            items: List.generate(
                              5,
                              (index) => DropdownMenuItem(
                                value: index + 1,
                                child:
                                    Text('${'★' * (index + 1)} (${index + 1})'),
                              ),
                            ),
                            onChanged: isTeacher && !locked
                                ? (value) {
                                    if (value != null)
                                      setState(
                                          () => _stars[student.id] = value);
                                  }
                                : null,
                            decoration: const InputDecoration(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 300,
                          child: TextFormField(
                            key: ValueKey(
                                'behavior-comment-${student.id}-$periodId-$locked'),
                            initialValue: _comments[student.id] ?? '',
                            enabled: isTeacher && !locked,
                            maxLength: 500,
                            decoration: const InputDecoration(
                              hintText: 'Petit commentaire (facultatif)',
                              counterText: '',
                            ),
                            onChanged: (value) => _comments[student.id] = value,
                          ),
                        ),
                      ),
                      DataCell(Row(children: [
                        Icon(
                          locked ? Icons.lock_rounded : Icons.edit_outlined,
                          size: 18,
                          color: locked ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 6),
                        Text(locked ? 'Envoyé · verrouillé' : 'Brouillon'),
                      ])),
                    ]);
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
