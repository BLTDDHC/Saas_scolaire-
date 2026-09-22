import 'dart:async';
import 'package:flutter/material.dart';
import '../../../shared/widgets/workspace_header.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/establishment_types.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/services/store_service.dart';
import '../../../data/models/attendance_sheet_model.dart';
import 'attendance_admin_page.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_form_field.dart';
import '../../../shared/widgets/app_toast.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  String? _selectedCycleId;
  String? _selectedLevelId;
  String? _selectedClassId;
  String? _selectedScheduleId;
  DateTime _selectedDate = DateTime.now();
  String? _scheduleLoadedKey;
  List<Map<String, dynamic>> _scheduleRows = const [];
  bool _loadingSchedule = false;
  String? _loadedKey;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _dailyStatistics;
  Map<String, dynamic>? _monthlyStatistics;
  Map<String, dynamic>? _trimesterStatistics;
  String? _trimesterName;
  final Map<String, String> _statuses = {};
  List<AttendanceStudent> _students = [];
  bool _locked = false;
  Timer? _availabilityTimer;

  @override
  void dispose() {
    _availabilityTimer?.cancel();
    super.dispose();
  }

  String get _date => _selectedDate.toIso8601String().split('T').first;
  String get _displayDate => AppDateUtils.formatDate(_selectedDate);

  Future<void> _loadSchedules(StoreService store, String? classId) async {
    final yearId = store.getSelectedAcademicYearId();
    if (yearId == null) return;
    final key = '$yearId|$classId';
    if (_scheduleLoadedKey == key || _loadingSchedule) return;
    _scheduleLoadedKey = key;
    setState(() => _loadingSchedule = true);
    try {
      final rows = await store.scheduleRemote(yearId, classId: classId);
      if (!mounted) return;
      if (classId != _selectedClassId ||
          yearId != store.getSelectedAcademicYearId()) {
        setState(() => _loadingSchedule = false);
        return;
      }
      _availabilityTimer?.cancel();
      final delays = rows
          .map((row) {
            final now = DateTime.tryParse('${row['serverTime']}');
            final next = DateTime.tryParse('${row['nextAttendanceChangeAt']}');
            return now == null || next == null ? null : next.difference(now);
          })
          .whereType<Duration>()
          .where((delay) => !delay.isNegative)
          .toList()
        ..sort((a, b) => a.compareTo(b));
      if (delays.isNotEmpty) {
        _availabilityTimer =
            Timer(delays.first + const Duration(milliseconds: 200), () {
          if (!mounted || _selectedClassId != classId) return;
          _scheduleLoadedKey = null;
          _loadSchedules(store, classId);
        });
      }
      setState(() {
        if (rows.isNotEmpty) {
          final localDay = rows.first['attendanceDate']?.toString() ??
              rows.first['serverTime']?.toString().split('T').first;
          final serverDate = DateTime.tryParse(localDay ?? '');
          if (serverDate != null && _date != localDay) {
            _selectedDate = serverDate;
            _selectedScheduleId = null;
            _resetCall();
          }
        }
        _scheduleRows = rows;
        if (!_scheduleRows.any((item) => item['id'] == _selectedScheduleId)) {
          _selectedScheduleId = null;
          _resetCall();
        }
        _loadingSchedule = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingSchedule = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _load(
      StoreService store, String classId, String scheduleId) async {
    final key = '$classId|$scheduleId|$_date';
    if (_loadedKey == key) return;
    _loadedKey = key;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final yearId = store.getSelectedAcademicYearId();
      final periods = yearId == null
          ? <Map<String, dynamic>>[]
          : await store.academicPeriodsRemote(yearId);
      Map<String, dynamic>? trimester;
      final selected = DateTime.parse(_date);
      for (final period in periods) {
        if (period['periodType'] != 'trimester') continue;
        final start = DateTime.tryParse(period['startDate']?.toString() ?? '');
        final end = DateTime.tryParse(period['endDate']?.toString() ?? '');
        if (start != null &&
            end != null &&
            !selected.isBefore(start) &&
            !selected.isAfter(end)) {
          trimester = period;
          break;
        }
      }
      final results = await Future.wait<dynamic>([
        store.attendanceSheetRemote(classId, scheduleId, _date),
        store.attendanceStatisticsRemote(
          classId,
          month: _selectedDate.month,
        ),
        if (trimester != null)
          store.attendanceStatisticsRemote(
            classId,
            periodId: trimester['id']?.toString(),
          ),
      ]);
      final sheet = results.first as AttendanceSheetModel;
      final records = sheet.records;
      if (!mounted || _loadedKey != key) return;
      setState(() {
        _students = sheet.students;
        _locked = sheet.locked;
        _statuses
          ..clear()
          ..addEntries(
              records.map((item) => MapEntry(item.studentId, item.status)));
        _dailyStatistics = {
          'present': records.where((item) => item.status == 'present').length,
          'absent': records.where((item) => item.status == 'absent').length,
          'justified':
              records.where((item) => item.status == 'justified').length,
        };
        _monthlyStatistics = Map<String, dynamic>.from(results[1] as Map);
        _trimesterStatistics = trimester == null
            ? null
            : Map<String, dynamic>.from(results[2] as Map);
        _trimesterName = trimester?['name']?.toString();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _save(StoreService store, List<dynamic> students,
      {bool submit = false}) async {
    final classId = _selectedClassId;
    final scheduleId = _selectedScheduleId;
    if (classId == null || scheduleId == null || students.isEmpty) return;
    if (_locked) return;
    if (!submit && _statuses.isEmpty) {
      AppToast.warning(
          context, 'Renseignez au moins un élève avant d’enregistrer.');
      return;
    }
    if (submit &&
        students.any((student) => !_statuses.containsKey(student.id))) {
      AppToast.warning(
          context, 'Renseignez la présence de chaque élève avant l’envoi.');
      return;
    }
    setState(() => _saving = true);
    try {
      await store.saveAttendanceRemote(
        classId: classId,
        scheduleId: scheduleId,
        date: _date,
        action: submit ? 'submit' : 'draft',
        entries: students
            .where((student) => _statuses.containsKey(student.id))
            .map((student) => {
                  'studentId': student.id,
                  'status': _statuses[student.id],
                })
            .toList(),
      );
      _loadedKey = null;
      await _load(store, classId, scheduleId);
      if (!mounted) return;
      final unavailable = students
          .where((s) => (_statuses[s.id] ?? 'present') != 'present')
          .length;
      AppToast.success(
          context,
          submit
              ? 'Relevé envoyé et verrouillé.'
              : 'Brouillon enregistré ($unavailable absence signalée).');
    } catch (error) {
      if (!mounted) return;
      AppToast.error(
          context, 'Impossible d’enregistrer l’appel pour le moment.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetCall() {
    _loadedKey = null;
    _statuses.clear();
    _dailyStatistics = null;
    _monthlyStatistics = null;
    _trimesterStatistics = null;
    _students = [];
    _locked = false;
  }

  void _resetSchedule() {
    _selectedScheduleId = null;
    _scheduleLoadedKey = null;
    _scheduleRows = const [];
    _resetCall();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final role = store.currentUser?.role;
    final isTeacher = role == UserRole.teacher;
    if (!isTeacher) return const AttendanceAdminPage();
    final yearId = store.getSelectedAcademicYearId();
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
    final levels = _selectedCycleId == null
        ? const <dynamic>[]
        : store
            .getSchoolLevelsByCycleId(_selectedCycleId!)
            .where((item) =>
                item.status == 'active' &&
                (!isTeacher || allowedLevelIds.contains(item.id)))
            .toList();
    final classes = yearClasses.where((item) {
      final levelId = item.structuredLevelId ?? item.levelId;
      return (_selectedCycleId == null || item.cycleId == _selectedCycleId) &&
          (_selectedLevelId == null || levelId == _selectedLevelId);
    }).toList();
    if (_selectedClassId != null &&
        !classes.any((item) => item.id == _selectedClassId)) {
      _selectedClassId = null;
      _resetSchedule();
    }
    final classId = _selectedClassId;
    if (yearId != null && _scheduleLoadedKey != '$yearId|$classId') {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _loadSchedules(store, classId));
    }
    final weekday = _selectedDate.weekday;
    final courseRows = _scheduleRows
        .where((item) =>
            (classId == null || item['classId'] == classId) &&
            item['weekday'] == weekday)
        .toList()
      ..sort((left, right) =>
          '${left['startTime']}'.compareTo('${right['startTime']}'));
    final scheduleId = _selectedScheduleId;
    if (classId != null &&
        scheduleId != null &&
        _loadedKey != '$classId|$scheduleId|$_date') {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _load(store, classId, scheduleId));
    }
    final students = _students;
    final canWrite = role == UserRole.teacher && !_locked;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WorkspaceHeader(
              title: 'Présences',
              subtitle:
                  'Vos séances du jour. L’appel reste accessible du début du cours à la fin de la journée, pendant l’année scolaire.'),
          if (_locked) const Text('Relevé envoyé · verrouillé'),
          const SizedBox(height: AppSpacing.s5),
          Wrap(
            spacing: AppSpacing.s4,
            runSpacing: AppSpacing.s3,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              SizedBox(
                width: 220,
                child: AppSelectField<String?>(
                  label: 'Cycle',
                  value: _selectedCycleId,
                  items: cycles
                      .map((item) => DropdownMenuItem<String?>(
                          value: item.id, child: Text(item.name)))
                      .toList(),
                  onChanged: (value) => setState(() {
                    _selectedCycleId = value;
                    _selectedLevelId = null;
                    _selectedClassId = null;
                    _resetSchedule();
                  }),
                ),
              ),
              SizedBox(
                width: 220,
                child: AppSelectField<String?>(
                  label: 'Niveau',
                  value: _selectedLevelId,
                  items: levels
                      .map((item) => DropdownMenuItem<String?>(
                          value: item.id, child: Text(item.name)))
                      .toList(),
                  onChanged: _selectedCycleId == null
                      ? null
                      : (value) => setState(() {
                            _selectedLevelId = value;
                            _selectedClassId = null;
                            _resetSchedule();
                          }),
                ),
              ),
              SizedBox(
                width: 280,
                child: AppSelectField<String?>(
                  label: 'Classe',
                  value: _selectedClassId,
                  items: classes
                      .map((item) => DropdownMenuItem(
                          value: item.id, child: Text(item.name)))
                      .toList(),
                  onChanged: (value) => setState(() {
                    _selectedClassId = value;
                    _resetSchedule();
                  }),
                ),
              ),
              if (isTeacher)
                AppButton(
                  label: 'Aujourd’hui : $_displayDate',
                  icon: Icons.today_rounded,
                  variant: AppButtonVariant.secondary,
                )
              else
                AppButton(
                  label: 'Date : $_displayDate',
                  icon: Icons.calendar_today_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked == null || !context.mounted) return;
                    setState(() {
                      _selectedDate = picked;
                      _selectedScheduleId = null;
                      _resetCall();
                    });
                  },
                ),
              if (canWrite)
                AppButton(
                    label: 'Soumettre et verrouiller',
                    icon: Icons.lock_outline,
                    onPressed: _saving ||
                            _loading ||
                            students.isEmpty ||
                            scheduleId == null
                        ? null
                        : () => _save(store, students, submit: true)),
              if (canWrite)
                AppButton(
                  label: _saving ? 'Enregistrement…' : 'Enregistrer l’appel',
                  icon: Icons.check_rounded,
                  onPressed: _saving ||
                          _loading ||
                          scheduleId == null ||
                          students.isEmpty
                      ? null
                      : () => _save(store, students),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s5),
          AppCard(
            title: isTeacher ? 'Cours d’aujourd’hui' : 'Cours de cette date',
            child: _loadingSchedule
                ? const Center(child: CircularProgressIndicator())
                : courseRows.isEmpty
                    ? const Text('Aucun cours programmé pour cette classe.')
                    : Column(
                        children: courseRows.map((course) {
                          final selected = course['id'] == _selectedScheduleId;
                          final canTake = course['canTakeAttendance'] == true;
                          return ListTile(
                            title: Text(
                                '${course['startTime']}–${course['endTime']} · ${course['subject'] ?? 'Matière'}'),
                            subtitle: Text(
                                '${course['class'] ?? ''} · ${course['teacher'] ?? ''}'
                                '${!canTake && course['attendanceUnavailableReason'] != null ? '\n${course['attendanceUnavailableReason']}' : ''}'),
                            selected: selected,
                            trailing: AppButton(
                              label: isTeacher
                                  ? canTake
                                      ? 'Faire l’appel'
                                      : 'Appel pas encore disponible'
                                  : 'Consulter l’appel',
                              icon: isTeacher
                                  ? Icons.fact_check_outlined
                                  : Icons.visibility_outlined,
                              onPressed: isTeacher && !canTake
                                  ? null
                                  : () => setState(() {
                                        _selectedClassId =
                                            course['classId']?.toString();
                                        _selectedScheduleId =
                                            course['id']?.toString();
                                        _resetCall();
                                      }),
                            ),
                          );
                        }).toList(),
                      ),
          ),
          const SizedBox(height: AppSpacing.s4),
          if (canWrite && scheduleId != null && students.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: 'Marquer tous présents',
                variant: AppButtonVariant.secondary,
                onPressed: () => setState(() {
                  for (final student in students) {
                    _statuses[student.id] = 'present';
                  }
                }),
              ),
            ),
          if (canWrite &&
              scheduleId != null &&
              students.isNotEmpty &&
              _statuses.length < students.length)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s3),
              child: Text(
                '${students.length - _statuses.length} élève(s) restent à renseigner avant la soumission.',
                style: const TextStyle(color: Colors.orange),
              ),
            ),
          if (canWrite && scheduleId != null && students.isNotEmpty)
            const SizedBox(height: AppSpacing.s4),
          if (_dailyStatistics != null)
            AppCard(
              title: 'Statistiques du jour',
              child: Wrap(spacing: 24, runSpacing: 12, children: [
                Text('Présents : ${_dailyStatistics!['present'] ?? 0}'),
                Text('Absents : ${_dailyStatistics!['absent'] ?? 0}'),
                Text('Justifiés : ${_dailyStatistics!['justified'] ?? 0}'),
              ]),
            ),
          if (_dailyStatistics != null) const SizedBox(height: AppSpacing.s4),
          if (_monthlyStatistics != null)
            AppCard(
              title: 'Statistiques du mois',
              child: Wrap(spacing: 24, runSpacing: 12, children: [
                Text('Présents : ' +
                    (_monthlyStatistics!['present'] ?? 0).toString()),
                Text('Absents : ' +
                    (_monthlyStatistics!['absent'] ?? 0).toString()),
                Text('Justifiés : ' +
                    (_monthlyStatistics!['justified'] ?? 0).toString()),
                Text('Taux : ' +
                    (_monthlyStatistics!['attendanceRate'] ?? '—').toString() +
                    ' %'),
              ]),
            ),
          if (_monthlyStatistics != null) const SizedBox(height: AppSpacing.s4),
          if (_trimesterStatistics != null)
            AppCard(
              title: 'Statistiques du trimestre — ${_trimesterName ?? ''}',
              child: Wrap(spacing: 24, runSpacing: 12, children: [
                Text('Présents : ${_trimesterStatistics!['present'] ?? 0}'),
                Text('Absents : ${_trimesterStatistics!['absent'] ?? 0}'),
                Text('Justifiés : ${_trimesterStatistics!['justified'] ?? 0}'),
                Text(
                    'Taux : ${_trimesterStatistics!['attendanceRate'] ?? '—'} %'),
              ]),
            ),
          if (_trimesterStatistics != null)
            const SizedBox(height: AppSpacing.s4),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            AppCard(
              child: Column(
                children: [
                  const Text(
                      'Impossible de charger les présences. Vérifiez votre sélection et réessayez.'),
                  const SizedBox(height: AppSpacing.s3),
                  AppButton(
                    label: 'Réessayer',
                    onPressed: () {
                      _loadedKey = null;
                      if (classId != null && scheduleId != null) {
                        _load(store, classId, scheduleId);
                      } else if (classId != null) {
                        _scheduleLoadedKey = null;
                        _loadSchedules(store, classId);
                      }
                    },
                  ),
                ],
              ),
            )
          else if (scheduleId == null)
            const AppCard(
              child: Center(
                  child: Text('Sélectionnez un cours pour ouvrir son appel.')),
            )
          else if (students.isEmpty)
            const AppCard(
                child: Center(child: Text('Aucun élève dans cette classe.')))
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Élève')),
                    DataColumn(label: Text('Présence')),
                  ],
                  rows: students.map((student) {
                    final value = _statuses[student.id];
                    return DataRow(cells: [
                      DataCell(Text(student.fullName)),
                      DataCell(
                        SegmentedButton<String>(
                          emptySelectionAllowed: true,
                          selected: value == null ? const {} : {value},
                          onSelectionChanged: canWrite
                              ? (selection) => setState(() {
                                    if (selection.isEmpty) {
                                      _statuses.remove(student.id);
                                    } else {
                                      _statuses[student.id] = selection.first;
                                    }
                                  })
                              : null,
                          segments: const [
                            ButtonSegment(
                                value: 'present', label: Text('Présent')),
                            ButtonSegment(
                                value: 'absent', label: Text('Absent')),
                            ButtonSegment(
                                value: 'justified',
                                label: Text('Absent justifié')),
                          ],
                        ),
                      ),
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
