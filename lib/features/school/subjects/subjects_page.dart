import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/subject_model.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_form_field.dart';
import '../../../shared/widgets/app_modal.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../settings/pedagogical_coefficients_card.dart';

/// Page de gestion des Matières — Reproduction de subjects.js
class SubjectsPage extends StatefulWidget {
  const SubjectsPage({super.key});

  @override
  State<SubjectsPage> createState() => _SubjectsPageState();
}

class _SubjectsPageState extends State<SubjectsPage> {
  String _searchQuery = '';

  void _openAddModal(BuildContext context) {
    final nameController = TextEditingController();

    final store = context.read<StoreService>();

    AppModal.show(
      context: context,
      title: 'Ajouter une nouvelle matière',
      maxWidth: 520,
      body: StatefulBuilder(
        builder: (context, modalSetState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppFormField(
                label: 'Nom de la matière *',
                controller: nameController,
                hint: 'ex: Français, Mathématiques',
              ),
              const SizedBox(height: AppSpacing.s3),
              const Text(
                'Cette matière pourra ensuite être configurée par niveau ou série, puis affectée depuis une classe.',
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
            label: 'Créer la matière',
            variant: AppButtonVariant.primary,
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                AppToast.warning(
                    context, 'Veuillez renseigner le nom de la matière.');
                return;
              }

              final school = store.getCurrentSchool();

              final subject = SubjectModel(
                id: '',
                name: name,
                coefficient: 1,
                schoolId: school?.id ?? 'ET001',
              );

              await store.createSubjectRemote(subject);
              if (!context.mounted) return;
              Navigator.pop(context);
              AppToast.success(context, 'Matière "$name" créée avec succès !');
            },
          ),
        ],
      ),
    );
  }

  void _openDetailModal(BuildContext context, SubjectModel subject) {
    final store = context.read<StoreService>();
    final currentYearId = store.getSelectedAcademicYearId();
    final affs = store
        .getAffectations()
        .where((a) =>
            (a.subjectId == subject.id || a.subject == subject.name) &&
            (currentYearId == null || a.academicYearId == currentYearId))
        .toList();
    final classes =
        affs.map((a) => a.className).whereType<String>().toSet().toList();
    final teachers =
        affs.map((a) => a.teacherName).whereType<String>().toSet().toList();

    final body = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subject.name, style: AppTypography.heading3()),
          const SizedBox(height: AppSpacing.s3),
          AppCard(
            title: 'Détails de la matière',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                    title: const Text('Classes assignées'),
                    subtitle:
                        Text(classes.isEmpty ? 'Aucune' : classes.join(', '))),
                ListTile(
                    title: const Text('Enseignants assignés'),
                    subtitle:
                        Text(teachers.isEmpty ? 'Aucun' : teachers.join(', '))),
              ],
            ),
          ),
        ],
      ),
    );

    AppModal.show(
      context: context,
      title: 'Matière — ${subject.name}',
      maxWidth: 560,
      body: body,
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
              label: 'Fermer',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }

  void _openEditModal(BuildContext context, SubjectModel subject) {
    final nameController = TextEditingController(text: subject.name);

    AppModal.show(
      context: context,
      title: 'Modifier la matière',
      maxWidth: 520,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppFormField(
              label: 'Nom de la matière *', controller: nameController),
          const SizedBox(height: AppSpacing.s3),
          const Text(
            'Les enseignants sont affectés à cette matière depuis leurs classes.',
          ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
              label: 'Annuler',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.pop(context)),
          const SizedBox(width: AppSpacing.s3),
          AppButton(
            label: 'Enregistrer',
            variant: AppButtonVariant.primary,
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                AppToast.warning(
                    context, 'Veuillez renseigner le nom de la matière.');
                return;
              }
              final updated = SubjectModel(
                id: subject.id,
                name: name,
                coefficient: subject.coefficient,
                teacher: subject.teacher,
                classes: subject.classes,
                color: subject.color,
                icon: subject.icon,
                schoolId: subject.schoolId,
                institutionId: subject.institutionId,
                academicYearId: subject.academicYearId,
                institutionType: subject.institutionType,
                status: subject.status,
                eliminationGrade: subject.eliminationGrade,
              );
              await context.read<StoreService>().updateSubjectRemote(updated);
              if (!context.mounted) return;
              Navigator.pop(context);
              AppToast.success(context, 'Matière modifiée.');
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
    final currentYearId = store.getSelectedAcademicYearId();
    final subjects = store.getSubjectsByYear(currentYearId);

    final filtered = subjects.where((s) {
      if (_searchQuery.isEmpty) return true;
      return s.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppPageHeader(
            title: 'Matières',
            subtitle: '${subjects.length} matière(s) configurée(s)',
            actions: [
              AppButton(
                label: 'Nouvelle matière',
                icon: Icons.add_rounded,
                variant: AppButtonVariant.primary,
                onPressed: () => _openAddModal(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),

          // Recherche
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AppFormField(
              label: '',
              hint: 'Rechercher une matière...',
              prefixIcon: Icons.search_rounded,
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          const SizedBox(height: AppSpacing.s6),

          // Table / Grid
          if (filtered.isEmpty)
            const AppEmptyState(
              iconData: Icons.menu_book_outlined,
              title: 'Aucune matière trouvée.',
              message: 'Modifiez votre recherche ou ajoutez une matière.',
            )
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    isDark ? AppColors.darkBgTableStripe : AppColors.gray100,
                  ),
                  columns: const [
                    DataColumn(label: Text('Matière')),
                    DataColumn(label: Text('État')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: filtered.map((s) {
                    return DataRow(
                      cells: [
                        DataCell(
                          Row(
                            children: [
                              const Icon(Icons.menu_book_outlined,
                                  size: 18, color: AppColors.primary600),
                              const SizedBox(width: 8),
                              Text(s.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                            ],
                          ),
                        ),
                        DataCell(
                          AppBadge(
                            label: s.status == 'active' ? 'Active' : 'Inactive',
                            variant: s.status == 'active'
                                ? AppBadgeVariant.success
                                : AppBadgeVariant.secondary,
                          ),
                        ),
                        DataCell(
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  s.status == 'active'
                                      ? Icons.pause_circle_outline
                                      : Icons.play_circle_outline,
                                  size: 18,
                                  color: AppColors.primary600,
                                ),
                                onPressed: () async {
                                  try {
                                    await context
                                        .read<StoreService>()
                                        .updateSubjectStatusRemote(
                                          s.id,
                                          s.status == 'active'
                                              ? 'inactive'
                                              : 'active',
                                        );
                                    if (context.mounted) {
                                      AppToast.success(
                                        context,
                                        s.status == 'active'
                                            ? 'Matière désactivée.'
                                            : 'Matière activée.',
                                      );
                                    }
                                  } on Exception {
                                    if (context.mounted) {
                                      AppToast.error(context,
                                          'Impossible de modifier cette matière.');
                                    }
                                  }
                                },
                                tooltip: s.status == 'active'
                                    ? 'Désactiver'
                                    : 'Activer',
                              ),
                              IconButton(
                                icon: const Icon(Icons.visibility_outlined,
                                    size: 18, color: AppColors.primary600),
                                onPressed: () => _openDetailModal(context, s),
                                tooltip: 'Voir',
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    size: 18, color: AppColors.primary600),
                                onPressed: () => _openEditModal(context, s),
                                tooltip: 'Modifier',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18, color: AppColors.danger500),
                                onPressed: () async {
                                  final actionContext = context;
                                  if (!actionContext.mounted) return;

                                  final confirm = await ConfirmDialog.show(
                                    context: actionContext,
                                    title: 'Supprimer la matière',
                                    message:
                                        'Voulez-vous vraiment supprimer "${s.name}" ?',
                                    isDanger: true,
                                  );
                                  if (!actionContext.mounted || !confirm)
                                    return;

                                  final store =
                                      actionContext.read<StoreService>();
                                  final deps =
                                      store.getSubjectDependencies(s.id);
                                  final totalDeps =
                                      deps.values.fold<int>(0, (a, b) => a + b);
                                  if (totalDeps > 0) {
                                    if (!actionContext.mounted) return;
                                    final messages = deps.entries
                                        .where((e) => e.value > 0)
                                        .map((e) => '${e.key}: ${e.value}')
                                        .join('\n');
                                    await ConfirmDialog.show(
                                      context: actionContext,
                                      title: 'Suppression bloquée',
                                      message:
                                          'La matière contient des dépendances:\n$messages\nSupprimez-les d\'abord.',
                                      isDanger: true,
                                    );
                                    if (!actionContext.mounted) return;
                                    return;
                                  }
                                  if (!actionContext.mounted) return;
                                  await store.archiveSubjectRemote(s.id);
                                  if (!actionContext.mounted) return;
                                  AppToast.success(
                                      actionContext, 'Matière supprimée.');
                                },
                                tooltip: 'Supprimer',
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.s6),
          const PedagogicalCoefficientsCard(),
        ],
      ),
    );
  }
}
