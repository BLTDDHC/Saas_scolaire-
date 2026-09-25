import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/responsive_utils.dart';
import '../../../data/models/class_model.dart';
import '../../../data/models/subject_model.dart';
import '../../../data/models/teacher_model.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_form_field.dart';
import '../../../shared/widgets/responsive_grid.dart';
import '../../../shared/widgets/app_modal.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/confirm_dialog.dart';

const _days = <int, String>{
  1: 'Lundi',
  2: 'Mardi',
  3: 'Mercredi',
  4: 'Jeudi',
  5: 'Vendredi',
  6: 'Samedi',
};
const _months = <String>[
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

enum _ScheduleView { day, week }

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  String? _selectedClassId;
  String? _loadedKey;
  Future<List<Map<String, dynamic>>>? _schedule;
  _ScheduleView? _preferredView;
  DateTime _focusedDate = DateUtils.dateOnly(DateTime.now());

  List<ClassModel> _visibleClasses(StoreService store) {
    final yearId = store.getSelectedAcademicYearId();
    final classes = store.getClassesByYear(yearId);
    if (store.currentUser?.role == UserRole.student) {
      final studentId = store.getCurrentStudentId();
      final ids = store
          .getStudents()
          .where((s) => s.id == studentId)
          .map((s) => s.classId)
          .whereType<String>()
          .toSet();
      return classes.where((c) => ids.contains(c.id)).toList();
    }
    if (store.currentUser?.role == UserRole.parent) {
      final ids =
          store.getStudents().map((s) => s.classId).whereType<String>().toSet();
      return classes.where((c) => ids.contains(c.id)).toList();
    }
    if (store.currentUser?.role != UserRole.teacher) return classes;
    final teacherId = store.getCurrentTeacherId();
    final ids = store
        .getAffectations()
        .where((a) => a.teacherId == teacherId && a.academicYearId == yearId)
        .map((a) => a.classId)
        .toSet();
    return classes.where((c) => ids.contains(c.id)).toList();
  }

  void _ensureLoaded(StoreService store) {
    final yearId = store.getSelectedAcademicYearId();
    final isTeacher = store.currentUser?.role == UserRole.teacher;
    final classes = _visibleClasses(store);
    if (!isTeacher && _selectedClassId == null && classes.isNotEmpty) {
      _selectedClassId = classes.first.id;
    }
    final key = isTeacher ? '$yearId|personal' : '$yearId|$_selectedClassId';
    if (yearId != null &&
        (isTeacher || _selectedClassId != null) &&
        key != _loadedKey) {
      _loadedKey = key;
      _schedule = store.scheduleRemote(yearId,
          classId: isTeacher ? null : _selectedClassId);
    }
  }

  void _reload() {
    final store = context.read<StoreService>();
    final yearId = store.getSelectedAcademicYearId();
    final isTeacher = store.currentUser?.role == UserRole.teacher;
    if (yearId == null || (!isTeacher && _selectedClassId == null)) return;
    setState(() {
      _loadedKey = isTeacher ? '$yearId|personal' : '$yearId|$_selectedClassId';
      _schedule = store.scheduleRemote(yearId,
          classId: isTeacher ? null : _selectedClassId);
    });
  }

  void _move(_ScheduleView view, int direction) => setState(() {
        _focusedDate = _focusedDate.add(Duration(
            days: view == _ScheduleView.week ? direction * 7 : direction));
      });

  Future<void> _openCreate(BuildContext context,
      [Map<String, dynamic>? existing]) async {
    final store = context.read<StoreService>();
    final selectedYearId = store.getSelectedAcademicYearId();
    final classes = store.getClassesByYear(selectedYearId);
    final allTeachers = store.getTeachers();
    final allSubjects = store.getSubjectsByYear(selectedYearId);
    final affectations = store.getAffectations()
        .where((item) =>
            item.academicYearId == selectedYearId &&
            item.classId != null &&
            item.subjectId != null)
        .toList();

    List<SubjectModel> subjectsForClass(String selectedClassId) {
      final schoolClass = classes.firstWhere((item) => item.id == selectedClassId);
      final levelId = schoolClass.structuredLevelId ?? schoolClass.levelId;
      if (levelId == null || levelId.isEmpty) return const <SubjectModel>[];

      final assignedSubjectIds = affectations
          .where((item) => item.classId == selectedClassId)
          .map((item) => item.subjectId)
          .whereType<String>()
          .toSet();

      return allSubjects.where((subject) {
        if (!assignedSubjectIds.contains(subject.id)) return false;
        return subject.levelSettings.any((setting) {
          final settingLevelId = setting['schoolLevelId']?.toString();
          final settingYearId = setting['academicYearId']?.toString();
          final settingSeriesId = setting['seriesId']?.toString();
          final settingStatus = setting['status']?.toString() ?? 'active';
          final sameSeries = (schoolClass.seriesId == null ||
                  schoolClass.seriesId!.isEmpty)
              ? settingSeriesId == null || settingSeriesId.isEmpty
              : settingSeriesId == schoolClass.seriesId;
          return settingStatus == 'active' &&
              settingLevelId == levelId &&
              settingYearId == selectedYearId &&
              sameSeries;
        });
      }).toList();
    }

    List<TeacherModel> teachersForClassSubject(
        String selectedClassId, String selectedSubjectId) {
      final teacherIds = affectations
          .where((item) =>
              item.classId == selectedClassId &&
              item.subjectId == selectedSubjectId)
          .map((item) => item.teacherId)
          .toSet();
      return allTeachers
          .where((teacher) => teacherIds.contains(teacher.id))
          .toList();
    }

    if (classes.isEmpty) {
      AppToast.warning(context, 'Aucune classe n’est disponible.');
      return;
    }

    var classId = existing?['classId']?.toString() ??
        _selectedClassId ??
        classes.first.id;
    var availableSubjects = subjectsForClass(classId);
    if (availableSubjects.isEmpty) {
      AppToast.warning(
        context,
        'Aucune matière active n’est assignée au niveau/série de cette classe avec une affectation enseignant.',
      );
      return;
    }

    String subjectId =
        existing?['subjectId']?.toString() ?? availableSubjects.first.id;
    if (!availableSubjects.any((subject) => subject.id == subjectId)) {
      subjectId = availableSubjects.first.id;
    }

    var availableTeachers = teachersForClassSubject(classId, subjectId);
    if (availableTeachers.isEmpty) {
      AppToast.warning(
        context,
        'Aucun enseignant actif n’est affecté à cette matière dans cette classe.',
      );
      return;
    }

    String teacherId =
        existing?['teacherId']?.toString() ?? availableTeachers.first.id;
    if (!availableTeachers.any((teacher) => teacher.id == teacherId)) {
      teacherId = availableTeachers.first.id;
    }
    var weekday = (existing?['weekday'] as num?)?.toInt() ?? 1;
    final start = TextEditingController(
        text: existing?['startTime']?.toString() ?? '08:00');
    final end = TextEditingController(
        text: existing?['endTime']?.toString() ?? '09:00');
    await AppModal.show(
      context: context,
      title: existing == null ? 'Ajouter un cours' : 'Modifier le cours',
      maxWidth: 560,
      body: StatefulBuilder(
          builder: (context, setModalState) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Informations de la séance',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.s4),
                  AppSelectField<String>(
                    label: 'Classe',
                    value: classId,
                    items: classes
                        .map((c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.name)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setModalState(() {
                        classId = v;
                        availableSubjects = subjectsForClass(classId);
                        if (availableSubjects.isNotEmpty) {
                          subjectId = availableSubjects.first.id;
                          availableTeachers =
                              teachersForClassSubject(classId, subjectId);
                          if (availableTeachers.isNotEmpty) {
                            teacherId = availableTeachers.first.id;
                          }
                        } else {
                          availableTeachers = <TeacherModel>[];
                        }
                      });
                    },
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  AppSelectField<String>(
                    label: 'Enseignant',
                    value: teacherId,
                    items: availableTeachers
                        .map((t) => DropdownMenuItem(
                            value: t.id, child: Text(t.fullName)))
                        .toList(),
                    onChanged: (v) =>
                        setModalState(() => teacherId = v ?? teacherId),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  AppSelectField<String>(
                    label: 'Matière',
                    value: subjectId,
                    items: availableSubjects
                        .map((s) =>
                            DropdownMenuItem(value: s.id, child: Text(s.name)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setModalState(() {
                        subjectId = v;
                        availableTeachers =
                            teachersForClassSubject(classId, subjectId);
                        if (availableTeachers.isNotEmpty) {
                          teacherId = availableTeachers.first.id;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  AppSelectField<int>(
                    label: 'Jour',
                    value: weekday,
                    items: _days.entries
                        .map((d) => DropdownMenuItem(
                            value: d.key, child: Text(d.value)))
                        .toList(),
                    onChanged: (v) =>
                        setModalState(() => weekday = v ?? weekday),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  ResponsiveFormGrid(
                    children: [
                      AppFormField(label: 'Début (HH:mm)', controller: start),
                      AppFormField(label: 'Fin (HH:mm)', controller: end),
                    ],
                  ),
                ],
              )),
      footer: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        AppButton(
            label: 'Annuler',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.pop(context)),
        const SizedBox(width: AppSpacing.s3),
        AppButton(
            label: 'Enregistrer',
            onPressed: () async {
              if (availableSubjects.isEmpty || availableTeachers.isEmpty) {
                AppToast.warning(
                  context,
                  'Sélectionnez une classe disposant d’une matière configurée et d’un enseignant affecté.',
                );
                return;
              }
              try {
                final payload = <String, dynamic>{
                  'classId': classId,
                  'teacherId': teacherId,
                  'subjectId': subjectId,
                  'weekday': weekday,
                  'startTime': start.text.trim(),
                  'endTime': end.text.trim(),
                };
                if (existing == null) {
                  await store.createScheduleEntryRemote(payload);
                } else {
                  await store.updateScheduleEntryRemote(
                      existing['id'].toString(), payload);
                }
                if (!context.mounted) return;
                Navigator.pop(context);
                _selectedClassId = classId;
                _reload();
                AppToast.success(context,
                    existing == null ? 'Cours enregistré.' : 'Cours modifié.');
              } catch (error) {
                if (context.mounted) AppToast.error(context, error.toString());
              }
            }),
      ]),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      start.dispose();
      end.dispose();
    });
  }

  Future<void> _openDetails(BuildContext context, Map<String, dynamic> item) =>
      AppModal.show(
        context: context,
        title: '${item['subject'] ?? 'Matière'}',
        maxWidth: 460,
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _DetailLine(
              icon: Icons.schedule_outlined,
              label: 'Horaire',
              value: '${item['startTime']} – ${item['endTime']}'),
          _DetailLine(
              icon: Icons.groups_2_outlined,
              label: 'Classe',
              value: '${item['class'] ?? 'Classe'}'),
          _DetailLine(
              icon: Icons.person_outline,
              label: 'Enseignant',
              value: '${item['teacher'] ?? 'Enseignant'}'),
          if ('${item['room'] ?? ''}'.trim().isNotEmpty)
            _DetailLine(
                icon: Icons.meeting_room_outlined,
                label: 'Salle',
                value: '${item['room']}'),
        ]),
        footer: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          AppButton(
              label: 'Fermer',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.pop(context)),
        ]),
      );

  Future<void> _deleteEntry(Map<String, dynamic> item) async {
    final confirmed = await ConfirmDialog.show(
      context: context,
      title: 'Retirer le cours',
      message: 'Confirmer le retrait de ce cours ?',
      isDanger: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await context
          .read<StoreService>()
          .archiveScheduleEntryRemote(item['id'].toString());
      if (mounted) _reload();
    } catch (error) {
      if (mounted) AppToast.error(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final role = store.currentUser?.role;
    final canManage = role == UserRole.admin || role == UserRole.superadmin;
    final classes = _visibleClasses(store);
    final mobile = ContextUtils.isMobile(context);
    final view =
        _preferredView ?? (mobile ? _ScheduleView.day : _ScheduleView.week);
    if (role != UserRole.teacher &&
        _selectedClassId != null &&
        !classes.any((c) => c.id == _selectedClassId)) {
      _selectedClassId = null;
      _loadedKey = null;
    }
    _ensureLoaded(store);
    return SingleChildScrollView(
      padding: EdgeInsets.all(mobile ? AppSpacing.s4 : AppSpacing.s6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppPageHeader(
          title: canManage
              ? 'Emploi du temps'
              : role == UserRole.parent
                  ? 'Emplois du temps de mes enfants'
                  : 'Mon emploi du temps',
          subtitle: canManage
              ? 'Pilotez les créneaux de chaque classe en un coup d’œil.'
              : role == UserRole.teacher
                  ? 'Retrouvez votre journée, votre prochain cours et votre semaine.'
                  : 'Consultez les cours prévus pour votre classe.',
          actions: canManage
              ? [
                  AppButton(
                      label: 'Ajouter un cours',
                      icon: Icons.add,
                      onPressed: () => _openCreate(context))
                ]
              : const [],
        ),
        const SizedBox(height: AppSpacing.s5),
        _ScheduleControls(
          showClassFilter: role != UserRole.teacher,
          selectedClassId: _selectedClassId,
          classes: classes,
          view: view,
          focusedDate: _focusedDate,
          onClassChanged: (v) => setState(() {
            _selectedClassId = v;
            _loadedKey = null;
          }),
          onViewChanged: (v) => setState(() => _preferredView = v),
          onPrevious: () => _move(view, -1),
          onNext: () => _move(view, 1),
          onToday: () =>
              setState(() => _focusedDate = DateUtils.dateOnly(DateTime.now())),
        ),
        const SizedBox(height: AppSpacing.s4),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _schedule,
          builder: (context, snapshot) {
            if (store.getSelectedAcademicYearId() == null ||
                (role != UserRole.teacher && classes.isEmpty)) {
              return _ScheduleMessage(
                  icon: Icons.calendar_month_outlined,
                  title: role == UserRole.teacher
                      ? 'Aucune année scolaire disponible'
                      : 'Aucune classe disponible',
                  message: role == UserRole.teacher
                      ? 'Aucun contexte scolaire ne permet de charger votre agenda.'
                      : 'Ajoutez une classe à cette année pour créer un emploi du temps.');
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _ScheduleLoading();
            }
            if (snapshot.hasError) {
              return _ScheduleMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Impossible de charger l’emploi du temps.',
                message: 'Vérifiez votre connexion puis réessayez.',
                action: AppButton(
                    label: 'Réessayer',
                    icon: Icons.refresh_rounded,
                    variant: AppButtonVariant.secondary,
                    onPressed: _reload),
              );
            }
            final uniqueRows = <String, Map<String, dynamic>>{};
            for (final row in snapshot.data ?? const <Map<String, dynamic>>[]) {
              uniqueRows['${row['id']}'] = row;
            }
            final rows = [...uniqueRows.values]
              ..sort((a, b) => _weekday(a) == _weekday(b)
                  ? '${a['startTime']}'.compareTo('${b['startTime']}')
                  : _weekday(a).compareTo(_weekday(b)));
            if (rows.isEmpty) {
              return _ScheduleMessage(
                  icon: Icons.event_available_outlined,
                  title: 'Aucun cours prévu',
                  message: role == UserRole.teacher
                      ? 'Aucun cours ne vous est affecté pour cette année.'
                      : 'Aucun cours planifié pour cette classe.');
            }
            return Column(children: [
              if (role == UserRole.teacher) ...[
                _NextCourseCard(rows: rows),
                const SizedBox(height: AppSpacing.s4),
              ],
              AppCard(
                padding: EdgeInsets.all(mobile ? AppSpacing.s3 : AppSpacing.s4),
                child: view == _ScheduleView.week
                    ? _WeekSchedule(
                        rows: rows,
                        focusedDate: _focusedDate,
                        canManage: canManage,
                        onOpen: _openDetails,
                        onEdit: (item) => _openCreate(context, item),
                        onDelete: _deleteEntry)
                    : _DaySchedule(
                        rows: rows,
                        focusedDate: _focusedDate,
                        canManage: canManage,
                        onOpen: _openDetails,
                        onEdit: (item) => _openCreate(context, item),
                        onDelete: _deleteEntry),
              ),
            ]);
          },
        ),
      ]),
    );
  }
}

class _ScheduleControls extends StatelessWidget {
  const _ScheduleControls({
    required this.showClassFilter,
    required this.selectedClassId,
    required this.classes,
    required this.view,
    required this.focusedDate,
    required this.onClassChanged,
    required this.onViewChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });
  final bool showClassFilter;
  final String? selectedClassId;
  final List<ClassModel> classes;
  final _ScheduleView view;
  final DateTime focusedDate;
  final ValueChanged<String?> onClassChanged;
  final ValueChanged<_ScheduleView> onViewChanged;
  final VoidCallback onPrevious, onNext, onToday;

  @override
  Widget build(BuildContext context) {
    final mobile = ContextUtils.isMobile(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.s3),
      child: Wrap(
          spacing: AppSpacing.s3,
          runSpacing: AppSpacing.s3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (showClassFilter)
              SizedBox(
                width: mobile ? double.infinity : 250,
                child: AppSelectField<String?>(
                  label: 'Classe',
                  value: selectedClassId,
                  items: classes
                      .map((c) =>
                          DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: onClassChanged,
                ),
              ),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _ViewButton(
                    label: 'Jour',
                    icon: Icons.view_day_outlined,
                    selected: view == _ScheduleView.day,
                    onPressed: () => onViewChanged(_ScheduleView.day)),
                _ViewButton(
                    label: 'Semaine',
                    icon: Icons.calendar_view_week_outlined,
                    selected: view == _ScheduleView.week,
                    onPressed: () => onViewChanged(_ScheduleView.week)),
              ]),
            ),
            Container(
              constraints: BoxConstraints(
                  minWidth: mobile ? 216 : 250, maxWidth: 320),
              decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    tooltip: view == _ScheduleView.week
                        ? 'Semaine précédente'
                        : 'Jour précédent',
                    onPressed: onPrevious,
                    icon: const Icon(Icons.chevron_left_rounded)),
                SizedBox(
                    width: mobile ? 120 : 154,
                    child: TextButton(
                        onPressed: onToday,
                        child: Text(_periodLabel(focusedDate, view),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center))),
                IconButton(
                    tooltip: view == _ScheduleView.week
                        ? 'Semaine suivante'
                        : 'Jour suivant',
                    onPressed: onNext,
                    icon: const Icon(Icons.chevron_right_rounded)),
              ]),
            ),
          ]),
    );
  }
}

class _ViewButton extends StatelessWidget {
  const _ViewButton(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onPressed});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        label: 'Vue $label',
        child: TextButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 17),
          label: Text(label),
          style: TextButton.styleFrom(
            foregroundColor: selected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            backgroundColor:
                selected ? Theme.of(context).colorScheme.primary : null,
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm)),
          ),
        ),
      );
}

class _WeekSchedule extends StatelessWidget {
  const _WeekSchedule(
      {required this.rows,
      required this.focusedDate,
      required this.canManage,
      required this.onOpen,
      required this.onEdit,
      required this.onDelete});
  final List<Map<String, dynamic>> rows;
  final DateTime focusedDate;
  final bool canManage;
  final Future<void> Function(BuildContext, Map<String, dynamic>) onOpen;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        const gap = AppSpacing.s3;
        final width =
            constraints.maxWidth < 1120 ? 1120.0 : constraints.maxWidth;
        final columnWidth = (width - gap * 5) / 6;
        final monday = _monday(focusedDate);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
              width: width,
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _days.entries.map((day) {
                    final dayRows =
                        rows.where((r) => _weekday(r) == day.key).toList();
                    return Padding(
                      padding: EdgeInsets.only(right: day.key == 6 ? 0 : gap),
                      child: SizedBox(
                          width: columnWidth,
                          child: _DayColumn(
                            day: day.value,
                            date: monday.add(Duration(days: day.key - 1)),
                            rows: dayRows,
                            canManage: canManage,
                            onOpen: onOpen,
                            onEdit: onEdit,
                            onDelete: onDelete,
                          )),
                    );
                  }).toList())),
        );
      });
}

class _DaySchedule extends StatelessWidget {
  const _DaySchedule(
      {required this.rows,
      required this.focusedDate,
      required this.canManage,
      required this.onOpen,
      required this.onEdit,
      required this.onDelete});
  final List<Map<String, dynamic>> rows;
  final DateTime focusedDate;
  final bool canManage;
  final Future<void> Function(BuildContext, Map<String, dynamic>) onOpen;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  @override
  Widget build(BuildContext context) => _DayColumn(
        day: _days[focusedDate.weekday] ?? 'Dimanche',
        date: focusedDate,
        rows: rows.where((r) => _weekday(r) == focusedDate.weekday).toList(),
        canManage: canManage,
        daily: true,
        onOpen: onOpen,
        onEdit: onEdit,
        onDelete: onDelete,
      );
}

class _DayColumn extends StatelessWidget {
  const _DayColumn(
      {required this.day,
      required this.date,
      required this.rows,
      required this.canManage,
      required this.onOpen,
      required this.onEdit,
      required this.onDelete,
      this.daily = false});
  final String day;
  final DateTime date;
  final List<Map<String, dynamic>> rows;
  final bool canManage, daily;
  final Future<void> Function(BuildContext, Map<String, dynamic>) onOpen;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  @override
  Widget build(BuildContext context) {
    final today = DateUtils.isSameDay(date, DateTime.now());
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
            color: today
                ? Theme.of(context).colorScheme.primary.withValues(alpha: .45)
                : Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s3, vertical: AppSpacing.s3),
          decoration: BoxDecoration(
            color: today
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: .35),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
          ),
          child: Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(day,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(_shortDate(date),
                      style: Theme.of(context).textTheme.bodySmall),
                ])),
            if (today)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s2, vertical: 3),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(AppRadius.full)),
                child: Text('Aujourd’hui',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.s2),
          child: rows.isEmpty
              ? SizedBox(
                  height: daily ? 180 : 130,
                  child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.event_busy_outlined,
                        color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: AppSpacing.s2),
                    Text('Aucun cours',
                        style: Theme.of(context).textTheme.bodySmall),
                  ])),
                )
              : Column(
                  children: rows
                      .map((item) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.s2),
                            child: _CourseCard(
                                item: item,
                                canManage: canManage,
                                onOpen: () => onOpen(context, item),
                                onEdit: () => onEdit(item),
                                onDelete: () => onDelete(item)),
                          ))
                      .toList()),
        ),
      ]),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard(
      {required this.item,
      required this.canManage,
      required this.onOpen,
      required this.onEdit,
      required this.onDelete});
  final Map<String, dynamic> item;
  final bool canManage;
  final VoidCallback onOpen, onEdit, onDelete;
  @override
  Widget build(BuildContext context) {
    final subject = '${item['subject'] ?? 'Matière'}';
    final accent = _subjectColor(subject);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label:
          '$subject, ${item['startTime']} à ${item['endTime']}, ${item['class'] ?? 'Classe'}',
      child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Ink(
              padding: const EdgeInsets.all(AppSpacing.s3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: dark ? .18 : .10),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border(left: BorderSide(color: accent, width: 4)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subject,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: AppSpacing.s1),
                    _Meta(
                        icon: Icons.schedule_outlined,
                        text: '${item['startTime']} – ${item['endTime']}',
                        color: accent,
                        strong: true),
                    const SizedBox(height: AppSpacing.s2),
                    _Meta(
                        icon: Icons.groups_2_outlined,
                        text: '${item['class'] ?? 'Classe'}'),
                    _Meta(
                        icon: Icons.person_outline,
                        text: '${item['teacher'] ?? 'Enseignant'}'),
                    if ('${item['room'] ?? ''}'.trim().isNotEmpty)
                      _Meta(
                          icon: Icons.meeting_room_outlined,
                          text: 'Salle : ${item['room']}'),
                    if (canManage)
                      Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(children: [
                            IconButton(
                                tooltip: 'Modifier',
                                visualDensity: VisualDensity.compact,
                                iconSize: 18,
                                onPressed: onEdit,
                                icon: const Icon(Icons.edit_outlined)),
                            IconButton(
                                tooltip: 'Retirer',
                                visualDensity: VisualDensity.compact,
                                iconSize: 18,
                                color: Theme.of(context).colorScheme.error,
                                onPressed: onDelete,
                                icon: const Icon(Icons.delete_outline)),
                          ])),
                  ]),
            ),
          )),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(
      {required this.icon,
      required this.text,
      this.color,
      this.strong = false});
  final IconData icon;
  final String text;
  final Color? color;
  final bool strong;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(children: [
          Icon(icon,
              size: 14, color: color ?? Theme.of(context).colorScheme.outline),
          const SizedBox(width: AppSpacing.s1),
          Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: strong ? FontWeight.w700 : null))),
        ]),
      );
}

class _NextCourseCard extends StatelessWidget {
  const _NextCourseCard({required this.rows});
  final List<Map<String, dynamic>> rows;
  @override
  Widget build(BuildContext context) {
    final item = _nextCourse(rows);
    if (item == null) return const SizedBox.shrink();
    final subject = '${item['subject'] ?? 'Matière'}';
    final accent = _subjectColor(subject);
    final room = '${item['room'] ?? ''}'.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
          color: accent.withValues(alpha: .11),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: accent.withValues(alpha: .30))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            padding: const EdgeInsets.all(AppSpacing.s2),
            decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(AppRadius.md)),
            child: const Icon(Icons.notifications_active_outlined,
                size: 20, color: Colors.white)),
        const SizedBox(width: AppSpacing.s3),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Prochain cours', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.s1),
          Text(subject,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.s1),
          Text(
              '${item['startTime']} – ${item['endTime']} • ${item['class'] ?? 'Classe'}${room.isEmpty ? '' : ' • Salle $room'}'),
        ])),
      ]),
    );
  }
}

class _ScheduleLoading extends StatelessWidget {
  const _ScheduleLoading();
  @override
  Widget build(BuildContext context) => AppCard(
      child: SizedBox(
          height: 230,
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: AppSpacing.s3),
            const Text('Chargement de votre emploi du temps…'),
          ]))));
}

class _ScheduleMessage extends StatelessWidget {
  const _ScheduleMessage(
      {required this.icon,
      required this.title,
      required this.message,
      this.action});
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => AppCard(
      child: SizedBox(
          height: 230,
          child: Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  size: 34, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: AppSpacing.s3),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.s1),
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[
                const SizedBox(height: AppSpacing.s4),
                action!
              ],
            ]),
          ))));
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 2),
                Text(value, style: Theme.of(context).textTheme.bodyLarge),
              ])),
        ]),
      );
}

int _weekday(Map<String, dynamic> item) =>
    (item['weekday'] as num?)?.toInt() ?? 0;
DateTime _monday(DateTime date) =>
    DateUtils.dateOnly(date.subtract(Duration(days: date.weekday - 1)));
String _shortDate(DateTime date) => '${date.day} ${_months[date.month - 1]}';
String _periodLabel(DateTime date, _ScheduleView view) {
  if (view == _ScheduleView.day) {
    return '${_days[date.weekday] ?? 'Dimanche'} ${_shortDate(date)}';
  }
  final start = _monday(date);
  final end = start.add(const Duration(days: 5));
  final ending = start.month == end.month
      ? '${end.day} ${_months[end.month - 1]} ${end.year}'
      : '${_shortDate(end)} ${end.year}';
  return 'Semaine du ${start.day} $ending';
}

Color _subjectColor(String value) {
  const palette = <Color>[
    AppColors.primary600,
    AppColors.secondary600,
    AppColors.info600,
    AppColors.success600,
    AppColors.warning600
  ];
  var hash = 0;
  for (final unit in value.codeUnits) {
    hash = unit + ((hash << 5) - hash);
  }
  return palette[hash.abs() % palette.length];
}

Map<String, dynamic>? _nextCourse(List<Map<String, dynamic>> rows) {
  final now = DateTime.now();
  final time =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  for (var offset = 0; offset < 6; offset++) {
    final weekday = ((now.weekday - 1 + offset) % 6) + 1;
    final candidates = rows
        .where((row) =>
            _weekday(row) == weekday &&
            (offset > 0 || '${row['startTime']}'.compareTo(time) >= 0))
        .toList()
      ..sort((a, b) => '${a['startTime']}'.compareTo('${b['startTime']}'));
    if (candidates.isNotEmpty) return candidates.first;
  }
  return null;
}
