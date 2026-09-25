import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/datasources/api_client.dart';
import '../../../data/models/class_model.dart';
import '../../../data/models/affectation_model.dart';
import '../../../data/models/subject_model.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_form_field.dart';
import '../../../shared/widgets/app_modal.dart';
import '../../../shared/widgets/workspace_header.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/responsive_grid.dart';

class ClassesPage extends StatefulWidget {
  const ClassesPage({super.key});
  @override
  State<ClassesPage> createState() => _ClassesPageState();
}

class _ClassesPageState extends State<ClassesPage> {
  bool _loading = true;
  String? _error;
  String _search = '';
  String? _cycleFilter;
  String? _levelFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = context.read<StoreService>();
      await Future.wait([
        store.refreshAcademicOrganization(),
        store.loadSchoolCycles(),
        store.refreshTeachersRemote(),
        store.refreshSubjectsRemote(),
        store.refreshAffectationsRemote(
            academicYearId: store.getSelectedAcademicYearId()),
      ]);
      for (final cycle in store.getSchoolCycles()) {
        await store.loadStructuredSchoolLevels(cycle.id);
      }
    } on Exception catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSeriesEditor() async {
    final store = context.read<StoreService>();
    final cycles =
        store.getSchoolCycles().where((cycle) => cycle.isActive).toList();
    if (cycles.isEmpty) {
      AppToast.warning(context, 'Un cycle actif est requis.');
      return;
    }
    var cycleId = cycles.first.id;
    final code = TextEditingController();
    final name = TextEditingController();
    var saving = false;
    await AppModal.show(
      context: context,
      title: 'Nouvelle serie',
      maxWidth: 480,
      body: StatefulBuilder(
          builder: (context, setModalState) =>
              Column(mainAxisSize: MainAxisSize.min, children: [
                AppSelectField<String>(
                    label: 'Cycle *',
                    value: cycleId,
                    items: cycles
                        .map((cycle) => DropdownMenuItem(
                            value: cycle.id, child: Text(cycle.name)))
                        .toList(),
                    onChanged: (value) =>
                        setModalState(() => cycleId = value ?? cycleId)),
                const SizedBox(height: AppSpacing.s3),
                AppFormField(label: 'Code *', controller: code),
                const SizedBox(height: AppSpacing.s3),
                AppFormField(label: 'Nom *', controller: name),
              ])),
      footer: StatefulBuilder(
          builder: (context, setModalState) =>
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                AppButton(
                    label: 'Annuler',
                    variant: AppButtonVariant.secondary,
                    onPressed: saving ? null : () => Navigator.pop(context)),
                const SizedBox(width: AppSpacing.s3),
                AppButton(
                    label: saving ? 'Enregistrement...' : 'Enregistrer',
                    onPressed: saving
                        ? null
                        : () async {
                            if (code.text.trim().isEmpty ||
                                name.text.trim().isEmpty) {
                              AppToast.warning(
                                  context, 'Code et nom sont obligatoires.');
                              return;
                            }
                            setModalState(() => saving = true);
                            try {
                              await store.createSchoolSeriesRemote({
                                'cycleId': cycleId,
                                'code': code.text.trim(),
                                'name': name.text.trim()
                              });
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              AppToast.success(this.context, 'Serie creee.');
                            } on ApiException catch (error) {
                              if (context.mounted)
                                AppToast.error(context, error.message);
                            } finally {
                              if (context.mounted)
                                setModalState(() => saving = false);
                            }
                          }),
              ])),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    code.dispose();
    name.dispose();
  }

  static const Map<String, List<Map<String, String>>> _standardLevels = {
    'MATERNELLE': [
      {'code': 'GARDERIE', 'name': 'Garderie'},
      {'code': 'P1', 'name': 'P1'},
      {'code': 'P2', 'name': 'P2'},
      {'code': 'P3', 'name': 'P3'},
    ],
    'PRIMAIRE': [
      {'code': 'CP1', 'name': 'CP1'},
      {'code': 'CP2', 'name': 'CP2'},
      {'code': 'CE1', 'name': 'CE1'},
      {'code': 'CE2', 'name': 'CE2'},
      {'code': 'CM1', 'name': 'CM1'},
      {'code': 'CM2', 'name': 'CM2'},
    ],
    'COLLEGE': [
      {'code': '6E', 'name': '6e'},
      {'code': '5E', 'name': '5e'},
      {'code': '4E', 'name': '4e'},
      {'code': '3E', 'name': '3e'},
    ],
    'LYCEE': [
      {'code': 'SECONDE', 'name': 'Seconde'},
      {'code': 'PREMIERE', 'name': 'Première'},
      {'code': 'TERMINALE', 'name': 'Terminale'},
    ],
  };

  Future<void> _openStandardLevelEditor() async {
    final store = context.read<StoreService>();
    final cycles =
        store.getSchoolCycles().where((cycle) => cycle.isActive).toList();
    if (cycles.isEmpty) {
      AppToast.warning(context, 'Un cycle actif est requis.');
      return;
    }
    var cycleId = cycles.first.id;
    String? selectedCode;
    var saving = false;

    List<Map<String, String>> choices() {
      final cycle = cycles.firstWhere((item) => item.id == cycleId);
      final existing = store
          .getSchoolLevelsByCycleId(cycleId)
          .map((level) => level.code.toUpperCase())
          .toSet();
      return (_standardLevels[cycle.code.toUpperCase()] ?? const [])
          .where((item) => !existing.contains(item['code']))
          .toList();
    }

    final initial = choices();
    selectedCode = initial.isEmpty ? null : initial.first['code'];
    await AppModal.show(
      context: context,
      title: 'Ajouter un niveau standard',
      maxWidth: 480,
      body: StatefulBuilder(builder: (modalContext, setModalState) {
        final options = choices();
        if (selectedCode != null &&
            !options.any((item) => item['code'] == selectedCode)) {
          selectedCode = options.isEmpty ? null : options.first['code'];
        }
        return Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Choisissez un niveau du catalogue. Les classes seront créées séparément.'),
          const SizedBox(height: AppSpacing.s3),
          AppSelectField<String>(
            label: 'Cycle *',
            value: cycleId,
            items: cycles
                .map((cycle) =>
                    DropdownMenuItem(value: cycle.id, child: Text(cycle.name)))
                .toList(),
            onChanged: (value) => setModalState(() {
              cycleId = value ?? cycleId;
              final updated = choices();
              selectedCode = updated.isEmpty ? null : updated.first['code'];
            }),
          ),
          const SizedBox(height: AppSpacing.s3),
          AppSelectField<String?>(
            label: 'Niveau standard *',
            value: selectedCode,
            items: options.isEmpty
                ? const [
                    DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Tous les niveaux sont disponibles'))
                  ]
                : options
                    .map((item) => DropdownMenuItem<String?>(
                        value: item['code'], child: Text(item['name']!)))
                    .toList(),
            onChanged: (value) => setModalState(() => selectedCode = value),
          ),
        ]);
      }),
      footer: StatefulBuilder(
        builder: (modalContext, setModalState) => Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.s2,
          runSpacing: AppSpacing.s2,
          children: [
            TextButton(
              onPressed: saving
                  ? null
                  : () {
                      Navigator.pop(modalContext);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _openLevelEditor();
                      });
                    },
              child: const Text('Niveau particulier'),
            ),
            AppButton(
              label: 'Annuler',
              variant: AppButtonVariant.secondary,
              onPressed: saving ? null : () => Navigator.pop(modalContext),
            ),
            AppButton(
              label: saving ? 'Enregistrement...' : 'Ajouter',
              onPressed: saving
                  ? null
                  : () async {
                      final options = choices();
                      final selected = options
                          .where((item) => item['code'] == selectedCode)
                          .toList();
                      if (selected.isEmpty) {
                        AppToast.warning(modalContext,
                            'Tous les niveaux standards sont déjà disponibles.');
                        return;
                      }
                      setModalState(() => saving = true);
                      try {
                        await store.createStructuredSchoolLevel(cycleId, {
                          'code': selected.first['code'],
                          'name': selected.first['name'],
                          'status': 'active',
                        });
                        if (!modalContext.mounted) return;
                        Navigator.pop(modalContext);
                        AppToast.success(
                            context, 'Niveau ajouté au catalogue.');
                      } on ApiException catch (error) {
                        if (modalContext.mounted) {
                          AppToast.error(modalContext, error.message);
                        }
                      } finally {
                        if (modalContext.mounted) {
                          setModalState(() => saving = false);
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  // Conservé pour les établissements qui possèdent un niveau particulier.
  Future<void> _openLevelEditor() async {
    final store = context.read<StoreService>();
    final cycles =
        store.getSchoolCycles().where((cycle) => cycle.isActive).toList();
    if (cycles.isEmpty) {
      AppToast.warning(context, 'Un cycle actif est requis.');
      return;
    }
    var cycleId = cycles.first.id;
    final code = TextEditingController();
    final name = TextEditingController();
    var saving = false;
    await AppModal.show(
      context: context,
      title: 'Nouveau niveau',
      maxWidth: 480,
      body: StatefulBuilder(
          builder: (modalContext, setModalState) =>
              Column(mainAxisSize: MainAxisSize.min, children: [
                AppSelectField<String>(
                    label: 'Cycle *',
                    value: cycleId,
                    items: cycles
                        .map((cycle) => DropdownMenuItem(
                            value: cycle.id, child: Text(cycle.name)))
                        .toList(),
                    onChanged: (value) =>
                        setModalState(() => cycleId = value ?? cycleId)),
                const SizedBox(height: AppSpacing.s3),
                AppFormField(
                    label: 'Code métier *',
                    controller: code,
                    hint: 'Ex. CP1, CM2, 6E'),
                const SizedBox(height: AppSpacing.s3),
                AppFormField(
                    label: 'Nom du niveau *',
                    controller: name,
                    hint: 'Ex. CP1, CM2, 6e'),
              ])),
      footer: StatefulBuilder(
          builder: (modalContext, setModalState) =>
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                AppButton(
                    label: 'Annuler',
                    variant: AppButtonVariant.secondary,
                    onPressed:
                        saving ? null : () => Navigator.pop(modalContext)),
                const SizedBox(width: AppSpacing.s3),
                AppButton(
                    label: saving ? 'Enregistrement...' : 'Enregistrer',
                    onPressed: saving
                        ? null
                        : () async {
                            if (code.text.trim().isEmpty ||
                                name.text.trim().isEmpty) {
                              AppToast.warning(modalContext,
                                  'Code métier et nom sont obligatoires.');
                              return;
                            }
                            setModalState(() => saving = true);
                            try {
                              await store.createStructuredSchoolLevel(cycleId, {
                                'code': code.text.trim(),
                                'name': name.text.trim(),
                                'status': 'active',
                              });
                              if (!modalContext.mounted) return;
                              Navigator.pop(modalContext);
                              AppToast.success(context, 'Niveau créé.');
                            } on ApiException catch (error) {
                              if (modalContext.mounted) {
                                AppToast.error(modalContext, error.message);
                              }
                            } on Exception {
                              if (modalContext.mounted) {
                                AppToast.error(modalContext,
                                    'Impossible de joindre le serveur.');
                              }
                            } finally {
                              if (modalContext.mounted) {
                                setModalState(() => saving = false);
                              }
                            }
                          }),
              ])),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    code.dispose();
    name.dispose();
  }

  Future<void> _openEditor([ClassModel? existing]) async {
    final store = context.read<StoreService>();
    final allSeries = await store.schoolSeriesRemote();
    final nameController = TextEditingController(text: existing?.name ?? '');
    String? yearId =
        existing?.academicYearId ?? store.getSelectedAcademicYearId();
    String? cycleId = existing?.cycleId;
    String? levelId = existing?.structuredLevelId ?? existing?.levelId;
    String? seriesId = existing?.seriesId;
    var submitting = false;

    await AppModal.show(
      context: context,
      title: existing == null ? 'Créer une classe' : 'Modifier la classe',
      maxWidth: 520,
      body: StatefulBuilder(builder: (modalContext, setModalState) {
        final cycles =
            store.getSchoolCycles().where((cycle) => cycle.isActive).toList();
        final levels = cycleId == null
            ? const <dynamic>[]
            : store
                .getSchoolLevelsByCycleId(cycleId!)
                .where((level) => level.status == 'active')
                .toList();
        final availableSeries = allSeries
            .where((item) => item['cycleId']?.toString() == cycleId)
            .toList();
        final isLycee = cycles.any((cycle) =>
            cycle.id == cycleId && cycle.code.toUpperCase() == 'LYCEE');
        return Column(mainAxisSize: MainAxisSize.min, children: [
          AppSelectField<String?>(
              label: 'Année scolaire *',
              value: yearId,
              items: store
                  .getAcademicYears()
                  .map((year) => DropdownMenuItem<String?>(
                      value: year.id, child: Text(year.name)))
                  .toList(),
              onChanged: (value) => setModalState(() => yearId = value)),
          const SizedBox(height: AppSpacing.s4),
          AppSelectField<String?>(
              label: 'Cycle *',
              value: cycleId,
              items: cycles
                  .map((cycle) => DropdownMenuItem<String?>(
                      value: cycle.id, child: Text(cycle.name)))
                  .toList(),
              onChanged: (value) => setModalState(() {
                    cycleId = value;
                    levelId = null;
                    seriesId = null;
                  })),
          const SizedBox(height: AppSpacing.s4),
          AppSelectField<String?>(
              label: 'Niveau *',
              value:
                  levels.any((level) => level.id == levelId) ? levelId : null,
              items: levels
                  .map((level) => DropdownMenuItem<String?>(
                      value: level.id, child: Text(level.name)))
                  .toList(),
              onChanged: (value) => setModalState(() => levelId = value)),
          const SizedBox(height: AppSpacing.s4),
          AppSelectField<String?>(
              label: isLycee ? 'Série *' : 'Série (optionnelle)',
              value: availableSeries
                      .any((item) => item['id']?.toString() == seriesId)
                  ? seriesId
                  : null,
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('Sélectionner une série')),
                ...availableSeries.map((item) => DropdownMenuItem<String?>(
                    value: item['id']?.toString(),
                    child: Text(item['name']?.toString() ?? 'Serie'))),
              ],
              onChanged: (value) => setModalState(() => seriesId = value)),
          const SizedBox(height: AppSpacing.s4),
          AppFormField(
              label: 'Nom de la classe *',
              controller: nameController,
              hint: 'Ex. CP1 A, 6e A, Seconde A'),
        ]);
      }),
      footer: StatefulBuilder(builder: (modalContext, setModalState) {
        Future<void> submit() async {
          final name = nameController.text.trim();
          if (yearId == null ||
              cycleId == null ||
              levelId == null ||
              name.isEmpty) {
            AppToast.warning(
                modalContext, 'Année, cycle, niveau et nom sont obligatoires.');
            return;
          }
          final selectedCycle = store
              .getSchoolCycles()
              .where((cycle) => cycle.id == cycleId)
              .toList();
          final isLycee = selectedCycle.isNotEmpty &&
              selectedCycle.first.code.toUpperCase() == 'LYCEE';
          if (isLycee && seriesId == null) {
            AppToast.warning(modalContext, 'Veuillez sélectionner une série.');
            return;
          }
          setModalState(() => submitting = true);
          try {
            final value = ClassModel(
                id: existing?.id ?? '',
                name: name,
                schoolId: store.currentUser?.schoolId ?? '',
                academicYearId: yearId,
                cycleId: cycleId,
                structuredLevelId: levelId,
                levelId: levelId,
                seriesId: seriesId);
            if (existing == null) {
              await store.createStructuredClass(value);
            } else {
              await store.updateStructuredClass(value);
            }
            if (!modalContext.mounted) return;
            Navigator.pop(modalContext);
            AppToast.success(context,
                existing == null ? 'Classe créée.' : 'Classe modifiée.');
          } on ApiException catch (error) {
            if (modalContext.mounted)
              AppToast.error(modalContext, error.message);
          } on Exception {
            if (modalContext.mounted)
              AppToast.error(modalContext, 'Impossible de joindre le serveur.');
          } finally {
            if (modalContext.mounted) setModalState(() => submitting = false);
          }
        }

        return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          AppButton(
              label: 'Annuler',
              variant: AppButtonVariant.secondary,
              onPressed: submitting ? null : () => Navigator.pop(modalContext)),
          const SizedBox(width: AppSpacing.s3),
          AppButton(
              label: submitting ? 'Enregistrement...' : 'Enregistrer',
              onPressed: submitting ? null : submit),
        ]);
      }),
    );
  }

  Future<void> _delete(ClassModel value) async {
    final confirmed = await ConfirmDialog.show(
        context: context,
        title: 'Supprimer la classe',
        message: 'Supprimer « ${value.name} » ?',
        isDanger: true);
    if (!confirmed || !mounted) return;
    try {
      await context.read<StoreService>().deleteStructuredClass(value.id);
      if (mounted) AppToast.success(context, 'Classe supprimée.');
    } on ApiException catch (error) {
      if (mounted) AppToast.error(context, error.message);
    } on Exception {
      if (mounted) AppToast.error(context, 'Impossible de joindre le serveur.');
    }
  }

  List<SubjectModel> _availableSubjectsForClass(
      StoreService store, ClassModel schoolClass) {
    final levelId = schoolClass.structuredLevelId ?? schoolClass.levelId;
    final settings = store.getSubjects().expand((subject) {
      return subject.levelSettings.map((setting) => (subject, setting));
    }).where((entry) {
      final setting = entry.$2;
      final sameSeries =
          setting['seriesId']?.toString() == schoolClass.seriesId;
      return setting['academicYearId']?.toString() ==
              schoolClass.academicYearId &&
          setting['schoolLevelId']?.toString() == levelId &&
          sameSeries &&
          setting['status'] != 'archived';
    }).toList();
    if (settings.isEmpty) {
      return store
          .getSubjects()
          .where((subject) => subject.status == 'active')
          .toList();
    }
    final enabledIds = settings
        .where((entry) => entry.$2['status'] == 'active')
        .map((entry) => entry.$1.id)
        .toSet();
    return store
        .getSubjects()
        .where((subject) =>
            subject.status == 'active' && enabledIds.contains(subject.id))
        .toList();
  }

  Future<bool> _openAssignmentEditor(ClassModel schoolClass) async {
    final store = context.read<StoreService>();
    final current = store
        .getAffectations()
        .where((item) =>
            item.classId == schoolClass.id &&
            item.academicYearId == schoolClass.academicYearId)
        .toList();
    final occupiedSubjectIds =
        current.map((item) => item.subjectId).whereType<String>().toSet();
    final subjects = _availableSubjectsForClass(store, schoolClass)
        .where((subject) => !occupiedSubjectIds.contains(subject.id))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final teachers = store
        .getTeachers()
        .where((teacher) => teacher.status == 'active')
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    if (subjects.isEmpty) {
      AppToast.warning(context,
          'Toutes les matières disponibles sont déjà attribuées dans cette classe.');
      return false;
    }
    if (teachers.isEmpty) {
      AppToast.warning(context, 'Créez d’abord un enseignant actif.');
      return false;
    }
    String subjectId = subjects.first.id;
    String teacherId = teachers.first.id;
    var saving = false;
    final created = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AppModal(
              title: 'Affecter un enseignant — ${schoolClass.name}',
              maxWidth: 680,
              body: Column(mainAxisSize: MainAxisSize.min, children: [
                AppSelectField<String>(
                  key: const Key('class-assignment-subject'),
                  label: 'Matière *',
                  value: subjectId,
                  items: subjects
                      .map((subject) => DropdownMenuItem(
                          value: subject.id, child: Text(subject.name)))
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) =>
                          setDialogState(() => subjectId = value ?? subjectId),
                ),
                const SizedBox(height: AppSpacing.s3),
                AppSelectField<String>(
                  key: const Key('class-assignment-teacher'),
                  label: 'Enseignant *',
                  value: teacherId,
                  items: teachers
                      .map((teacher) => DropdownMenuItem(
                          value: teacher.id, child: Text(teacher.fullName)))
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) =>
                          setDialogState(() => teacherId = value ?? teacherId),
                ),
              ]),
              footer: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                    onPressed:
                        saving ? null : () => Navigator.pop(dialogContext),
                    child: const Text('Annuler')),
                FilledButton(
                  key: const Key('save-class-assignment'),
                  onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() => saving = true);
                          try {
                            await store.createAffectationRemote(
                              AffectationModel(
                                id: '',
                                teacherId: teacherId,
                                subjectId: subjectId,
                                classId: schoolClass.id,
                                schoolId: schoolClass.schoolId,
                                academicYearId: schoolClass.academicYearId,
                              ),
                            );
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext, true);
                          } on ApiException catch (error) {
                            if (dialogContext.mounted) {
                              AppToast.error(dialogContext, error.message);
                              setDialogState(() => saving = false);
                            }
                          } on Exception {
                            if (dialogContext.mounted) {
                              AppToast.error(dialogContext,
                                  'Impossible de joindre le service.');
                              setDialogState(() => saving = false);
                            }
                          }
                        },
                  child: Text(saving ? 'Enregistrement…' : 'Affecter'),
                ),
              ]),
            ),
          ),
        ) ??
        false;
    if (created && mounted) {
      AppToast.success(context, 'Affectation enregistrée.');
    }
    return created;
  }

  Future<bool> _openMainTeacherEditor(ClassModel schoolClass) async {
    final store = context.read<StoreService>();
    final assignedTeacherIds = store
        .getAffectations()
        .where((item) =>
            item.classId == schoolClass.id &&
            item.academicYearId == schoolClass.academicYearId)
        .map((item) => item.teacherId)
        .whereType<String>()
        .toSet();
    final teachers = store
        .getTeachers()
        .where((teacher) =>
            teacher.status == 'active' &&
            assignedTeacherIds.contains(teacher.id))
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    if (teachers.isEmpty) {
      AppToast.warning(context,
          'Affectez d’abord un enseignant à une matière de cette classe.');
      return false;
    }
    String teacherId = schoolClass.mainTeacherId != null &&
            teachers.any((item) => item.id == schoolClass.mainTeacherId)
        ? schoolClass.mainTeacherId!
        : teachers.first.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AppModal(
          title: 'Professeur principal — ${schoolClass.name}',
          maxWidth: 680,
          body: AppSelectField<String>(
            label: 'Enseignant *',
            value: teacherId,
            items: teachers
                .map((teacher) => DropdownMenuItem(
                      value: teacher.id,
                      child: Text(teacher.fullName),
                    ))
                .toList(),
            onChanged: (value) =>
                setDialogState(() => teacherId = value ?? teacherId),
          ),
          footer: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (schoolClass.mainTeacherId != null)
              TextButton(
                onPressed: () async {
                  try {
                    await store.clearClassMainTeacherRemote(schoolClass.id);
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  } on ApiException catch (error) {
                    if (dialogContext.mounted) {
                      AppToast.error(dialogContext, error.message);
                    }
                  }
                },
                child: const Text('Retirer le principal'),
              ),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                try {
                  await store.setClassMainTeacherRemote(
                      schoolClass.id, teacherId);
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } on ApiException catch (error) {
                  if (dialogContext.mounted) {
                    AppToast.error(dialogContext, error.message);
                  }
                }
              },
              child: const Text('Définir comme principal'),
            ),
          ]),
        ),
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _openClassTeam(ClassModel schoolClass) async {
    final store = context.read<StoreService>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final assignments = store
              .getAffectations()
              .where((item) =>
                  item.classId == schoolClass.id &&
                  item.academicYearId == schoolClass.academicYearId)
              .toList()
            ..sort((a, b) => (a.subject ?? '').compareTo(b.subject ?? ''));
          final currentClass = store.getClasses().firstWhere(
                (item) => item.id == schoolClass.id,
                orElse: () => schoolClass,
              );
          return AppModal(
            title: 'Enseignants — ${schoolClass.name}',
            maxWidth: 860,
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentClass.mainTeacher == null
                      ? 'Professeur principal : aucun'
                      : 'Professeur principal : ' + currentClass.mainTeacher!,
                ),
                const SizedBox(height: AppSpacing.s3),
                if (assignments.isEmpty)
                  const Text('Aucun enseignant affecté à cette classe.')
                else
                  ResponsiveDataTable(
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Matière')),
                        DataColumn(label: Text('Enseignant')),
                        DataColumn(label: Text('Action')),
                      ],
                      rows: assignments
                          .map((assignment) => DataRow(cells: [
                                DataCell(Text(assignment.subject ?? 'Matière')),
                                DataCell(Text(
                                    assignment.teacherName ?? 'Enseignant')),
                                DataCell(IconButton(
                                  tooltip: 'Retirer de la classe',
                                  icon: const Icon(Icons.link_off_rounded),
                                  onPressed: () async {
                                    try {
                                      await store.archiveAffectationRemote(
                                          assignment.id);
                                      if (dialogContext.mounted) {
                                        setDialogState(() {});
                                        AppToast.success(dialogContext,
                                            'Affectation retirée.');
                                      }
                                    } on ApiException catch (error) {
                                      if (dialogContext.mounted) {
                                        AppToast.error(
                                            dialogContext, error.message);
                                      }
                                    }
                                  },
                                )),
                              ]))
                          .toList(),
                    ),
                  ),
              ],
            ),
            footer: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Fermer')),
              OutlinedButton.icon(
                onPressed: () async {
                  final changed = await _openMainTeacherEditor(currentClass);
                  if (changed && dialogContext.mounted) {
                    setDialogState(() {});
                    AppToast.success(
                        dialogContext, 'Professeur principal mis à jour.');
                  }
                },
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Professeur principal'),
              ),
              FilledButton.icon(
                key: const Key('assign-teacher-from-class'),
                onPressed: () async {
                  final changed = await _openAssignmentEditor(schoolClass);
                  if (changed && dialogContext.mounted) {
                    setDialogState(() {});
                  }
                },
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Affecter un enseignant'),
              ),
            ]),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final selectedYear = store.getSelectedAcademicYear();
    final cycles = store.getSchoolCycles();
    final levels = _cycleFilter == null
        ? store.getSchoolLevels()
        : store.getSchoolLevelsByCycleId(_cycleFilter!);
    final classes = store.getClassesByYear(selectedYear?.id).where((item) {
      if (_search.isNotEmpty &&
          !item.name.toLowerCase().contains(_search.toLowerCase()))
        return false;
      if (_cycleFilter != null && item.cycleId != _cycleFilter) return false;
      if (_levelFilter != null &&
          (item.structuredLevelId ?? item.levelId) != _levelFilter)
        return false;
      return true;
    }).toList();
    return WorkspacePage(
      title: 'Classes',
      subtitle: 'Structure : année → cycle → niveau → classe',
      actions: [
        AppButton(
            label: 'Nouveau niveau',
            icon: Icons.layers_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: () => _openStandardLevelEditor()),
        AppButton(
            label: 'Nouvelle série',
            icon: Icons.account_tree_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: () => _openSeriesEditor()),
        AppButton(
            label: 'Nouvelle classe',
            icon: Icons.add_rounded,
            onPressed: selectedYear == null ? null : () => _openEditor()),
      ],
      children: [
        if (_loading)
          const WorkspaceLoadingState(
            key: Key('classes-loading'),
            label: 'Chargement de l’organisation académique…',
          )
        else if (_error != null)
          WorkspaceErrorState(
            message: 'Impossible de charger l’organisation académique.',
            onRetry: _load,
          )
        else ...[
          Wrap(spacing: AppSpacing.s3, runSpacing: AppSpacing.s3, children: [
            ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AppFormField(
                    label: '',
                    hint: 'Rechercher une classe...',
                    prefixIcon: Icons.search_rounded,
                    onChanged: (value) => setState(() => _search = value))),
            SizedBox(
                width: 220,
                child: AppSelectField<String?>(
                    label: 'Cycle',
                    value: _cycleFilter,
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('Tous les cycles')),
                      ...cycles.map((cycle) => DropdownMenuItem<String?>(
                          value: cycle.id, child: Text(cycle.name)))
                    ],
                    onChanged: (value) => setState(() {
                          _cycleFilter = value;
                          _levelFilter = null;
                        }))),
            SizedBox(
                width: 220,
                child: AppSelectField<String?>(
                    label: 'Niveau',
                    value: _levelFilter,
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('Tous les niveaux')),
                      ...levels.map((level) => DropdownMenuItem<String?>(
                          value: level.id, child: Text(level.name)))
                    ],
                    onChanged: (value) =>
                        setState(() => _levelFilter = value))),
          ]),
          const SizedBox(height: AppSpacing.s5),
          if (classes.isEmpty)
            AppEmptyState(
              iconData: Icons.meeting_room_outlined,
              title: 'Aucune classe trouvée.',
              message: selectedYear == null
                  ? 'Créez d’abord une année scolaire.'
                  : 'Aucune classe n’est configurée pour ${selectedYear.name}.',
            )
          else
            ResponsiveGrid(
                desktopColumns: 3,
                tabletColumns: 2,
                mobileColumns: 1,
                children: classes
                    .map((item) => AppCard(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Expanded(
                                    child: Text(item.name,
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary600))),
                                AppBadge(
                                    label: item.cycle ?? 'Cycle',
                                    variant: AppBadgeVariant.secondary),
                              ]),
                              const SizedBox(height: AppSpacing.s3),
                              Text('Niveau : ${item.level ?? "—"}'),
                              const SizedBox(height: AppSpacing.s3),
                              OutlinedButton.icon(
                                key: Key('class-team-${item.id}'),
                                onPressed: () => _openClassTeam(item),
                                icon: const Icon(Icons.groups_2_outlined),
                                label: const Text('Enseignants'),
                              ),
                              const SizedBox(height: AppSpacing.s2),
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                        icon: const Icon(Icons.edit_outlined),
                                        tooltip: 'Modifier',
                                        onPressed: () => _openEditor(item)),
                                    IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            color: AppColors.danger500),
                                        tooltip: 'Supprimer',
                                        onPressed: () => _delete(item)),
                                  ]),
                            ])))
                    .toList()),
        ],
      ],
    );
  }
}
