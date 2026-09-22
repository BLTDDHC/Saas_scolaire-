import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/academic_year_model.dart';
import '../../../data/models/affectation_model.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_form_field.dart';
import '../../../shared/widgets/app_modal.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/confirm_dialog.dart';

/// Page des Affectations — Triple liaison Enseignant → Matière → Classe (affectations.js)
class AffectationsPage extends StatefulWidget {
  const AffectationsPage({super.key});

  @override
  State<AffectationsPage> createState() => _AffectationsPageState();
}

class _AffectationsPageState extends State<AffectationsPage> {
  String _searchQuery = '';
  String? _selectedTeacherFilter;
  String? _selectedSubjectFilter;
  String? _selectedClassFilter;
  String? _selectedYearFilter;
  void _openAddModal(BuildContext context) {
    final store = context.read<StoreService>();
    final currentYearId = store.getSelectedAcademicYearId();
    final teachers = store.getTeachers();
    final subjects = store.getSubjectsByYear(currentYearId);
    final classes = store.getClassesByYear(currentYearId);
    final years = store.getAcademicYears();

    if (teachers.isEmpty ||
        subjects.isEmpty ||
        classes.isEmpty ||
        years.isEmpty) {
      AppToast.warning(
        context,
        'Vous devez avoir au moins 1 enseignant, 1 matière, 1 classe et 1 année académique pour créer une affectation.',
      );
      return;
    }

    String selectedTeacherId = teachers.first.id;
    String selectedSubjectId = subjects.first.id;
    String selectedClassId = classes.first.id;
    String selectedYearId = currentYearId ?? years.first.id;

    AppModal.show(
      context: context,
      title: 'Nouvelle Affectation Pédagogique',
      maxWidth: 520,
      body: StatefulBuilder(
        builder: (context, setModalState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Choisissez qui enseigne quelle matière dans quelle classe.',
                style: TextStyle(fontSize: 13, color: AppColors.gray500),
              ),
              const SizedBox(height: AppSpacing.s4),
              AppSelectField<String>(
                label: 'Enseignant *',
                value: selectedTeacherId,
                items: teachers
                    .map((t) => DropdownMenuItem(
                        value: t.id,
                        child:
                            Text('${t.fullName} (${t.subject ?? "Général"})')))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setModalState(() => selectedTeacherId = val);
                },
              ),
              const SizedBox(height: AppSpacing.s4),
              AppSelectField<String>(
                label: 'Matière à enseigner *',
                value: selectedSubjectId,
                items: subjects
                    .map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text('${s.icon ?? "📚"} ${s.name}')))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setModalState(() => selectedSubjectId = val);
                },
              ),
              const SizedBox(height: AppSpacing.s4),
              AppSelectField<String>(
                label: 'Année académique *',
                value: selectedYearId,
                items: years
                    .map((y) =>
                        DropdownMenuItem(value: y.id, child: Text(y.name)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setModalState(() => selectedYearId = val);
                },
              ),
              const SizedBox(height: AppSpacing.s4),
              AppSelectField<String>(
                label: 'Classe affectée *',
                value: selectedClassId,
                items: classes
                    .map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text('${c.name} (${c.level ?? ""})')))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setModalState(() => selectedClassId = val);
                },
              ),
            ],
          );
        },
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Annuler',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: AppSpacing.s3),
          AppButton(
            label: 'Créer l\'affectation',
            variant: AppButtonVariant.primary,
            onPressed: () async {
              final teacher =
                  teachers.firstWhere((t) => t.id == selectedTeacherId);
              final cls = classes.firstWhere((c) => c.id == selectedClassId);
              final school = store.getCurrentSchool();
              final subject =
                  subjects.firstWhere((s) => s.id == selectedSubjectId);

              final affectation = AffectationModel(
                id: '',
                teacherId: teacher.id,
                teacherName: teacher.fullName,
                subjectId: subject.id,
                subject: subject.name,
                classId: cls.id,
                className: cls.name,
                schoolId: school?.id ?? 'ET001',
                academicYearId: selectedYearId,
                type: 'teaching',
              );

              final added = !store.hasDuplicateAffectation(affectation);
              if (added) {
                await store.createAffectationRemote(affectation);
                if (!context.mounted) return;
              }
              if (!added) {
                AppToast.warning(context,
                    'Cette affectation existe déjà pour la même année, la même classe et le même enseignant.');
                return;
              }

              Navigator.pop(context);
              AppToast.success(context,
                  'Affectation enregistrée : ${teacher.fullName} — ${subject.name} — ${cls.name}.');
            },
          ),
        ],
      ),
    );
  }

  void _openMainTeacherModal(BuildContext context) {
    final store = context.read<StoreService>();
    final classes =
        store.getClassesByYear(store.getSelectedAcademicYearId()).toList();
    if (classes.isEmpty) {
      AppToast.warning(context, 'Créez d’abord une classe.');
      return;
    }
    String selectedClassId = classes.first.id;
    String? selectedTeacherId;

    List<dynamic> eligibleTeachers() {
      final teacherIds = store
          .getAffectations()
          .where((item) =>
              item.classId == selectedClassId &&
              item.type == 'teaching' &&
              item.subjectId != null)
          .map((item) => item.teacherId)
          .toSet();
      return store
          .getTeachers()
          .where((teacher) =>
              teacher.status == 'active' && teacherIds.contains(teacher.id))
          .toList();
    }

    AppModal.show(
      context: context,
      title: 'Définir le professeur principal',
      maxWidth: 520,
      body: StatefulBuilder(builder: (context, setModalState) {
        final teachers = eligibleTeachers();
        if (selectedTeacherId == null ||
            !teachers.any((teacher) => teacher.id == selectedTeacherId)) {
          selectedTeacherId =
              teachers.isEmpty ? null : teachers.first.id as String;
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSelectField<String>(
              label: 'Classe *',
              value: selectedClassId,
              items: classes
                  .map((item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setModalState(() {
                    selectedClassId = value;
                    selectedTeacherId = null;
                  });
                }
              },
            ),
            const SizedBox(height: AppSpacing.s4),
            if (teachers.isEmpty)
              const Text(
                'Aucun enseignant n’est encore affecté à cette classe.',
                style: TextStyle(color: AppColors.warning600),
              )
            else
              AppSelectField<String>(
                label: 'Professeur principal *',
                value: selectedTeacherId,
                items: teachers
                    .map((teacher) => DropdownMenuItem<String>(
                        value: teacher.id, child: Text(teacher.fullName)))
                    .toList(),
                onChanged: (value) =>
                    setModalState(() => selectedTeacherId = value),
              ),
            const SizedBox(height: AppSpacing.s3),
            const Text(
              'Une classe ne peut avoir qu’un seul professeur principal. Un nouveau choix remplace le précédent.',
              style: TextStyle(fontSize: 12, color: AppColors.gray500),
            ),
          ],
        );
      }),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Annuler',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: AppSpacing.s3),
          AppButton(
            label: 'Confirmer',
            onPressed: () async {
              if (selectedTeacherId == null) {
                AppToast.warning(context,
                    'Choisissez un enseignant affecté à cette classe.');
                return;
              }
              await store.setClassMainTeacherRemote(
                  selectedClassId, selectedTeacherId!);
              if (!context.mounted) return;
              Navigator.pop(context);
              AppToast.success(context, 'Professeur principal enregistré.');
            },
          ),
        ],
      ),
    );
  }

  void _openEditModal(BuildContext context, AffectationModel affectation) {
    final store = context.read<StoreService>();
    final years = store.getAcademicYears();
    final teachers = store.getTeachers();
    final subjects = store.getSubjects();
    final classes = store.getClasses();

    if (teachers.isEmpty || classes.isEmpty || years.isEmpty) {
      AppToast.warning(context,
          'Impossible de modifier cette affectation : les données requises sont manquantes.');
      return;
    }

    String selectedTeacherId = affectation.teacherId;
    String selectedYearId = affectation.academicYearId ?? years.first.id;
    String selectedClassId = affectation.classId ?? classes.first.id;
    String selectedSubjectId =
        affectation.subjectId ?? (subjects.isNotEmpty ? subjects.first.id : '');

    AppModal.show(
      context: context,
      title: 'Modifier l\'affectation',
      maxWidth: 520,
      body: StatefulBuilder(
        builder: (context, setModalState) {
          final filteredSubjects = subjects;
          final filteredClasses =
              classes.where((c) => c.academicYearId == selectedYearId).toList();
          if (filteredSubjects.isNotEmpty &&
              !filteredSubjects.any((s) => s.id == selectedSubjectId)) {
            selectedSubjectId = filteredSubjects.first.id;
          }
          if (!filteredClasses.any((c) => c.id == selectedClassId)) {
            selectedClassId = filteredClasses.isNotEmpty
                ? filteredClasses.first.id
                : classes.first.id;
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Mettez à jour l\'affectation de l\'enseignant.',
                style: TextStyle(fontSize: 13, color: AppColors.gray500),
              ),
              const SizedBox(height: AppSpacing.s4),
              AppSelectField<String>(
                label: 'Enseignant *',
                value: selectedTeacherId,
                items: teachers
                    .map((t) => DropdownMenuItem(
                        value: t.id,
                        child:
                            Text('${t.fullName} (${t.subject ?? "Général"})')))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setModalState(() => selectedTeacherId = val);
                },
              ),
              const SizedBox(height: AppSpacing.s4),
              AppSelectField<String>(
                label: 'Matière à enseigner *',
                value: selectedSubjectId,
                items: filteredSubjects
                    .map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text('${s.icon ?? "📚"} ${s.name}')))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setModalState(() => selectedSubjectId = val);
                },
              ),
              const SizedBox(height: AppSpacing.s4),
              AppSelectField<String>(
                label: 'Année académique *',
                value: selectedYearId,
                items: years
                    .map((y) =>
                        DropdownMenuItem(value: y.id, child: Text(y.name)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setModalState(() => selectedYearId = val);
                },
              ),
              const SizedBox(height: AppSpacing.s4),
              AppSelectField<String>(
                label: 'Classe affectée *',
                value: selectedClassId,
                items: filteredClasses
                    .map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text('${c.name} (${c.level ?? ""})')))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setModalState(() => selectedClassId = val);
                },
              ),
            ],
          );
        },
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Annuler',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: AppSpacing.s3),
          AppButton(
            label: 'Enregistrer',
            variant: AppButtonVariant.primary,
            onPressed: () async {
              final teacher =
                  teachers.firstWhere((t) => t.id == selectedTeacherId);
              final cls = classes.firstWhere((c) => c.id == selectedClassId);
              final school = store.getCurrentSchool();
              final subject =
                  subjects.firstWhere((s) => s.id == selectedSubjectId);

              final updated = AffectationModel(
                id: affectation.id,
                teacherId: teacher.id,
                teacherName: teacher.fullName,
                subjectId: subject.id,
                subject: subject.name,
                classId: cls.id,
                className: cls.name,
                schoolId: school?.id ?? 'ET001',
                academicYearId: selectedYearId,
                type: 'teaching',
              );

              final success = !store.hasDuplicateAffectation(updated,
                  excludeId: updated.id);
              if (success) {
                await store.updateAffectationRemote(updated);
                if (!context.mounted) return;
              }
              if (!success) {
                AppToast.warning(context,
                    'Impossible d\'enregistrer : affectation dupliquée ou invalide.');
                return;
              }

              Navigator.pop(context);
              AppToast.success(context, 'Affectation mise à jour.');
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final store = context.watch<StoreService>();
    final allAffectations = store.getAffectations();
    final years = store.getAcademicYears();
    final teachers = store.getTeachers();
    final subjects = store.getSubjects();
    final classes = store.getClasses();

    final affectations = allAffectations.where((a) {
      if (_selectedTeacherFilter != null &&
          _selectedTeacherFilter!.isNotEmpty &&
          a.teacherId != _selectedTeacherFilter) return false;
      if (_selectedSubjectFilter != null &&
          _selectedSubjectFilter!.isNotEmpty &&
          a.subjectId != _selectedSubjectFilter) return false;
      if (_selectedClassFilter != null &&
          _selectedClassFilter!.isNotEmpty &&
          a.classId != _selectedClassFilter) return false;
      if (_selectedYearFilter != null &&
          _selectedYearFilter!.isNotEmpty &&
          a.academicYearId != _selectedYearFilter) return false;
      if (_searchQuery.isNotEmpty) {
        final needle = _searchQuery.toLowerCase();
        final teacherName = a.teacherName?.toLowerCase() ?? '';
        final subjectName = a.subject?.toLowerCase() ?? '';
        final className = a.className?.toLowerCase() ?? '';
        final yearName = years
            .firstWhere((y) => y.id == a.academicYearId,
                orElse: () => AcademicYearModel(
                    id: '', name: '', start: '', end: '', schoolId: ''))
            .name
            .toLowerCase();
        if (!teacherName.contains(needle) &&
            !subjectName.contains(needle) &&
            !className.contains(needle) &&
            !yearName.contains(needle)) {
          return false;
        }
      }
      return true;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppPageHeader(
            title: 'Affectations pédagogiques',
            subtitle: 'Liaisons Enseignant → Matière → Classe',
            actions: [
              AppButton(
                label: 'Professeur principal',
                icon: Icons.workspace_premium_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: () => _openMainTeacherModal(context),
              ),
              AppButton(
                label: 'Nouvelle affectation',
                icon: Icons.add_rounded,
                variant: AppButtonVariant.primary,
                onPressed: () => _openAddModal(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.s4),
            child: Wrap(
              spacing: AppSpacing.s3,
              runSpacing: AppSpacing.s3,
              children: [
                SizedBox(
                  width: 280,
                  child: AppFormField(
                    label: 'Recherche',
                    hint: 'Chercher enseignant, matière, classe...',
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: AppSelectField<String?>(
                    label: 'Filtrer par enseignant',
                    value: _selectedTeacherFilter,
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Tous les enseignants')),
                      ...teachers.map((t) => DropdownMenuItem(
                          value: t.id, child: Text(t.fullName))),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedTeacherFilter = value),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: AppSelectField<String?>(
                    label: 'Filtrer par matière',
                    value: _selectedSubjectFilter,
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Toutes les matières')),
                      ...subjects.map((s) =>
                          DropdownMenuItem(value: s.id, child: Text(s.name))),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedSubjectFilter = value),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: AppSelectField<String?>(
                    label: 'Filtrer par classe',
                    value: _selectedClassFilter,
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Toutes les classes')),
                      ...classes.map((c) =>
                          DropdownMenuItem(value: c.id, child: Text(c.name))),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedClassFilter = value),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: AppSelectField<String?>(
                    label: 'Filtrer par année',
                    value: _selectedYearFilter,
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Toutes les années')),
                      ...years.map((y) =>
                          DropdownMenuItem(value: y.id, child: Text(y.name))),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedYearFilter = value),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s4),

          // Table
          AppCard(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  isDark ? AppColors.darkBgTableStripe : AppColors.gray100,
                ),
                columns: const [
                  DataColumn(label: Text('Enseignant')),
                  DataColumn(label: Text('Matière')),
                  DataColumn(label: Text('Classe')),
                  DataColumn(label: Text('Année')),
                  DataColumn(label: Text('Statut')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: affectations.map((a) {
                  final yearName = years
                      .firstWhere((y) => y.id == a.academicYearId,
                          orElse: () => AcademicYearModel(
                              id: '',
                              name: '—',
                              start: '',
                              end: '',
                              schoolId: ''))
                      .name;
                  return DataRow(
                    cells: [
                      DataCell(Text(a.teacherName ?? a.teacherId,
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(a.subject ?? 'Matière inconnue')),
                      DataCell(Text(a.className ?? '—')),
                      DataCell(Text(yearName)),
                      DataCell(Text('Actif',
                          style: const TextStyle(color: AppColors.success600))),
                      DataCell(Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined,
                                size: 18, color: AppColors.primary600),
                            onPressed: () => _openEditModal(context, a),
                            tooltip: 'Modifier',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 18, color: AppColors.danger500),
                            onPressed: () async {
                              final confirm = await ConfirmDialog.show(
                                context: context,
                                title: 'Supprimer l\'affectation',
                                message:
                                    'Voulez-vous supprimer cette affectation ?',
                                isDanger: true,
                              );
                              if (!context.mounted) return;
                              if (confirm) {
                                await context
                                    .read<StoreService>()
                                    .archiveAffectationRemote(a.id);
                                if (!context.mounted) return;
                                AppToast.success(
                                    context, 'Affectation supprimée.');
                              }
                            },
                          ),
                        ],
                      )),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
