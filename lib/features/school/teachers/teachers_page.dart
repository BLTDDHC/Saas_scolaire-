import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/academic_year_model.dart';
import '../../../data/models/teacher_model.dart';
import '../../../data/models/class_model.dart';
import '../../../data/datasources/api_client.dart';
import '../../../data/services/store_service.dart';
import '../shared/profile_modals.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_form_field.dart';
import '../../../shared/widgets/app_modal.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/responsive_grid.dart';

/// Page de gestion des Enseignants — Reproduction de teachers.js
class TeachersPage extends StatefulWidget {
  const TeachersPage({super.key});

  @override
  State<TeachersPage> createState() => _TeachersPageState();
}

class _TeachersPageState extends State<TeachersPage> {
  String _searchQuery = '';

  void _openAddModal(BuildContext context) {
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    String sex = 'M';
    final store = context.read<StoreService>();
    final currentYearId = store.getSelectedAcademicYearId();
    final subjects = store.getSubjectsByYear(currentYearId);
    final selectedSubjectIds = <String>{};

    AppModal.show(
      context: context,
      title: 'Créer un nouvel enseignant',
      maxWidth: 820,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ResponsiveFormGrid(
            children: [
              AppFormField(
                label: 'Prénom *',
                controller: firstNameController,
                hint: 'ex: Moussa',
              ),
              AppFormField(
                label: 'Nom *',
                controller: lastNameController,
                hint: 'ex: Konaté',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s5),
          ResponsiveFormGrid(
            children: [
              AppFormField(
                label: 'Email',
                controller: emailController,
                hint: 'enseignant@ecole.com',
              ),
              AppFormField(
                label: 'Téléphone',
                controller: phoneController,
                hint: '+242 06...',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s5),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 320,
              child: AppSelectField<String>(
                label: 'Sexe',
                value: sex,
                items: const [
                  DropdownMenuItem(value: 'M', child: Text('Masculin (M)')),
                  DropdownMenuItem(value: 'F', child: Text('Féminin (F)')),
                ],
                onChanged: (val) {
                  if (val != null) sex = val;
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          Builder(builder: (ctx) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Matières que cet enseignant peut enseigner',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.s2),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: subjects.map((subject) {
                    final isSelected = selectedSubjectIds.contains(subject.id);
                    return FilterChip(
                      label: Text(subject.name),
                      selected: isSelected,
                      onSelected: (sel) {
                        if (sel)
                          selectedSubjectIds.add(subject.id);
                        else
                          selectedSubjectIds.remove(subject.id);
                        (ctx as Element).markNeedsBuild();
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.s2),
                const Text(
                  'Les classes et les matières réellement enseignées sont définies depuis chaque classe.',
                  style: TextStyle(fontSize: 12, color: AppColors.gray500),
                ),
              ],
            );
          }),
        ],
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
            label: 'Créer l\'enseignant',
            variant: AppButtonVariant.primary,
            onPressed: () async {
              final first = firstNameController.text.trim();
              final last = lastNameController.text.trim();

              if (first.isEmpty || last.isEmpty) {
                AppToast.warning(
                    context, 'Veuillez remplir le prénom et le nom.');
                return;
              }

              final store = context.read<StoreService>();
              final school = store.getCurrentSchool();
              final teacher = TeacherModel(
                id: '',
                firstName: first,
                lastName: last,
                email: emailController.text.trim(),
                phone: phoneController.text.trim(),
                subject: subjects
                    .where((subject) => selectedSubjectIds.contains(subject.id))
                    .map((subject) => subject.name)
                    .join(', '),
                schoolId: school?.id ?? 'ET001',
                sex: sex,
              );

              await store.createTeacherRemote(teacher);

              Navigator.pop(context);
              AppToast.success(context,
                  'Enseignant "${teacher.fullName}" créé avec succès !');
            },
          ),
        ],
      ),
    );
  }

  Future<void> _provisionTeacherAccess(
      BuildContext context, TeacherModel teacher) async {
    final reset = teacher.userId != null && teacher.userId!.isNotEmpty;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(reset
            ? 'Réinitialiser l’accès enseignant'
            : 'Créer l’accès enseignant'),
        content: Text(reset
            ? 'Un nouveau mot de passe temporaire remplacera l’ancien. Le matricule enseignant reste inchangé.'
            : 'La connexion se fera avec le matricule ${teacher.employeeNumber ?? 'attribué au profil'}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(reset ? 'Réinitialiser' : 'Créer l’accès'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final store = context.read<StoreService>();
      final password = await store.provisionTeacherAccess(teacher.id);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Accès enseignant prêt'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Matricule'),
              SelectableText(
                teacher.employeeNumber ?? '',
                key: const Key('teacher-login-matricule'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.s3),
              const Text(
                  'Copiez ce mot de passe maintenant. Il ne sera affiché qu’une seule fois, expire après 24 heures et ne permet qu’une connexion avant son remplacement.'),
              const SizedBox(height: AppSpacing.s3),
              SelectableText(
                password,
                key: const Key('temporary-teacher-password'),
                style: const TextStyle(
                    fontFamily: 'monospace', fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('J’ai copié le mot de passe'),
            ),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (context.mounted) {
        AppToast.error(context, error.message);
      }
    } on Exception {
      if (context.mounted) {
        AppToast.error(context, 'Impossible de joindre le service.');
      }
    }
  }

  void _openProfileModal(BuildContext context, TeacherModel t) {
    final store = context.read<StoreService>();
    final currentYearId = store.getSelectedAcademicYearId();

    // subjects via affectations preferred
    final affs = store
        .getAffectations()
        .where((a) =>
            a.teacherId == t.id &&
            (currentYearId == null || a.academicYearId == currentYearId))
        .toList();
    final subjects = <String>{};
    final classes = <String>{};
    for (final a in affs) {
      if (a.subject != null) subjects.add(a.subject!);
      if (a.className != null) classes.add(a.className!);
    }

    final selectedYear = store.getAcademicYears().firstWhere(
          (y) => y.id == currentYearId,
          orElse: () => AcademicYearModel(
              id: '', name: '', start: '', end: '', schoolId: ''),
        );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.avatarColorFor(t.fullName),
                child: Text(t.initials,
                    style: const TextStyle(color: Colors.white))),
            const SizedBox(width: AppSpacing.s3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.fullName, style: AppTypography.heading3()),
                const SizedBox(height: 4),
                Text('Matricule : ${t.employeeNumber ?? t.id}',
                    style: AppTypography.caption()),
                const SizedBox(height: 4),
                Text(
                    'Année académique : ${selectedYear.name.isNotEmpty ? selectedYear.name : '—'}',
                    style: AppTypography.caption()),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        AppCard(
          title: 'Contact',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (t.email != null && t.email!.isNotEmpty)
                Text('Email : ${t.email}'),
              if (t.phone != null && t.phone!.isNotEmpty)
                Text('Téléphone : ${t.phone}'),
              if ((t.email == null || t.email!.isEmpty) &&
                  (t.phone == null || t.phone!.isEmpty))
                Text('Aucun contact disponible',
                    style: TextStyle(color: Theme.of(context).hintColor)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s3),
        AppCard(
          title: 'Matières',
          child: subjects.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.s4),
                  child: Text('Aucune matière assignée'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: subjects
                      .map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.s2),
                          child: Text(s)))
                      .toList(),
                ),
        ),
        const SizedBox(height: AppSpacing.s3),
        AppCard(
          title: 'Classes assignées',
          child: classes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.s4),
                  child: Text('Aucune classe assignée'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: classes.map((c) {
                    final classModel =
                        store.getClassesByYear(currentYearId).firstWhere(
                              (cc) => cc.name == c,
                              orElse: () => store.getClasses().firstWhere(
                                    (cc) => cc.name == c,
                                    orElse: () => ClassModel(
                                        id: '',
                                        name: c,
                                        level: '',
                                        schoolId: ''),
                                  ),
                            );
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            alignment: Alignment.centerLeft),
                        onPressed: classModel.id.isNotEmpty
                            ? () {
                                Navigator.pop(context);
                                showClassProfileModal(context, classModel);
                              }
                            : null,
                        child: Text(c,
                            style:
                                const TextStyle(color: AppColors.primary600)),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );

    AppModal.show(
        context: context,
        title: 'Enseignant — ${t.lastName} ${t.firstName}',
        body: body,
        maxWidth: 640,
        footer: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          AppButton(
              label: 'Fermer',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.pop(context)),
          const SizedBox(width: AppSpacing.s3),
          AppButton(
              label: 'Voir le profil',
              variant: AppButtonVariant.primary,
              onPressed: () => Navigator.pop(context))
        ]));
  }

  void _openEditModal(BuildContext context, TeacherModel t) {
    final firstNameController = TextEditingController(text: t.firstName);
    final lastNameController = TextEditingController(text: t.lastName);
    final emailController = TextEditingController(text: t.email ?? '');
    final phoneController = TextEditingController(text: t.phone ?? '');
    String sex = t.sex ?? 'M';
    final store = context.read<StoreService>();
    final currentYearId = store.getSelectedAcademicYearId();
    final subjects = store.getSubjectsByYear(currentYearId);
    final currentNames = (t.subject ?? '')
        .split(',')
        .map((name) => name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
    final selectedSubjectIds = subjects
        .where((subject) => currentNames.contains(subject.name.toLowerCase()))
        .map((subject) => subject.id)
        .toSet();

    AppModal.show(
      context: context,
      title: 'Modifier l\'enseignant',
      maxWidth: 520,
      body: Column(mainAxisSize: MainAxisSize.min, children: [
        ResponsiveFormGrid(
          children: [
            AppFormField(label: 'Prénom *', controller: firstNameController),
            AppFormField(label: 'Nom *', controller: lastNameController),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        Row(children: [
          Expanded(
              child: AppSelectField<String>(
                  label: 'Sexe',
                  value: sex,
                  items: const [
                    DropdownMenuItem(value: 'M', child: Text('Masculin (M)')),
                    DropdownMenuItem(value: 'F', child: Text('Féminin (F)'))
                  ],
                  onChanged: (val) {
                    if (val != null) sex = val;
                  })),
        ]),
        const SizedBox(height: AppSpacing.s4),
        Builder(builder: (ctx) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Matières que cet enseignant peut enseigner',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.s2),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: subjects.map((subject) {
                  return FilterChip(
                    label: Text(subject.name),
                    selected: selectedSubjectIds.contains(subject.id),
                    onSelected: (selected) {
                      if (selected) {
                        selectedSubjectIds.add(subject.id);
                      } else {
                        selectedSubjectIds.remove(subject.id);
                      }
                      (ctx as Element).markNeedsBuild();
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.s2),
              const Text(
                'Les classes et les matières réellement enseignées sont définies depuis chaque classe.',
                style: TextStyle(fontSize: 12, color: AppColors.gray500),
              ),
            ],
          );
        }),
        const SizedBox(height: AppSpacing.s4),
        ResponsiveFormGrid(
          children: [
            AppFormField(label: 'Email', controller: emailController),
            AppFormField(label: 'Téléphone', controller: phoneController),
          ],
        ),
      ]),
      footer: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        AppButton(
            label: 'Annuler',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.pop(context)),
        const SizedBox(width: AppSpacing.s3),
        AppButton(
            label: 'Enregistrer',
            variant: AppButtonVariant.primary,
            onPressed: () async {
              final first = firstNameController.text.trim();
              final last = lastNameController.text.trim();
              if (first.isEmpty || last.isEmpty) {
                AppToast.warning(
                    context, 'Veuillez remplir le prénom et le nom.');
                return;
              }
              final updated = TeacherModel(
                  id: t.id,
                  firstName: first,
                  lastName: last,
                  email: emailController.text.trim(),
                  phone: phoneController.text.trim(),
                  subject: subjects
                      .where(
                          (subject) => selectedSubjectIds.contains(subject.id))
                      .map((subject) => subject.name)
                      .join(', '),
                  schoolId: t.schoolId,
                  sex: sex,
                  status: t.status,
                  employeeNumber: t.employeeNumber);
              await context.read<StoreService>().updateTeacherRemote(updated);
              if (!context.mounted) return;
              Navigator.pop(context);
              AppToast.success(context, 'Enseignant modifié.');
            })
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final store = context.watch<StoreService>();
    final teachers = store.getTeachers();
    final activeTeacherCount =
        teachers.where((teacher) => teacher.status == 'active').length;

    final filtered = teachers.where((t) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return t.fullName.toLowerCase().contains(q) ||
          (t.employeeNumber?.toLowerCase().contains(q) ?? false) ||
          (t.subject != null && t.subject!.toLowerCase().contains(q));
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppPageHeader(
            title: 'Enseignants',
            subtitle:
                '${teachers.length} enseignant(s) enregistré(s) · $activeTeacherCount actif(s)',
            actions: [
              AppButton(
                label: 'Nouvel enseignant',
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
              hint: 'Rechercher un enseignant...',
              prefixIcon: Icons.search_rounded,
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          const SizedBox(height: AppSpacing.s6),

          // Table
          if (filtered.isEmpty)
            const AppEmptyState(
              iconData: Icons.school_outlined,
              title: 'Aucun enseignant trouvé.',
              message: 'Modifiez votre recherche ou ajoutez un enseignant.',
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
                    DataColumn(label: Text('Enseignant')),
                    DataColumn(label: Text('Matières possibles')),
                    DataColumn(label: Text('Email / Tél')),
                    DataColumn(label: Text('Statut')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: filtered.map((t) {
                    return DataRow(
                      cells: [
                        DataCell(
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    AppColors.avatarColorFor(t.fullName),
                                child: Text(t.initials,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t.fullName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                  if (t.employeeNumber != null)
                                    Text(t.employeeNumber!,
                                        style: AppTypography.caption()),
                                ],
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          Text(
                              t.subject != null && t.subject!.isNotEmpty
                                  ? t.subject!
                                  : 'Non renseignées',
                              style: const TextStyle(fontSize: 13)),
                        ),
                        DataCell(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (t.email != null && t.email!.isNotEmpty)
                                Text(t.email!,
                                    style: const TextStyle(fontSize: 12)),
                              if (t.phone != null && t.phone!.isNotEmpty)
                                Text(t.phone!,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? AppColors.darkTextTertiary
                                            : AppColors.lightTextTertiary)),
                            ],
                          ),
                        ),
                        DataCell(
                          AppBadge(
                            label: t.status == 'active' ? 'Actif' : 'Inactif',
                            variant: t.status == 'active'
                                ? AppBadgeVariant.success
                                : AppBadgeVariant.secondary,
                          ),
                        ),
                        DataCell(
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.visibility_outlined,
                                    size: 18),
                                onPressed: () => _openProfileModal(context, t),
                                tooltip: 'Voir',
                              ),
                              IconButton(
                                key: Key('teacher-access-${t.id}'),
                                icon: Icon(
                                    t.userId == null || t.userId!.isEmpty
                                        ? Icons.person_add_alt_1_rounded
                                        : Icons.password_rounded,
                                    size: 18),
                                onPressed: () =>
                                    _provisionTeacherAccess(context, t),
                                tooltip: t.userId == null || t.userId!.isEmpty
                                    ? 'Créer l’accès de connexion'
                                    : 'Réinitialiser le mot de passe',
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () => _openEditModal(context, t),
                                tooltip: 'Modifier',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18, color: AppColors.danger500),
                                onPressed: () async {
                                  final confirm = await ConfirmDialog.show(
                                    context: context,
                                    title: 'Supprimer l\'enseignant',
                                    message:
                                        'Voulez-vous vraiment supprimer "${t.fullName}" ?',
                                    isDanger: true,
                                  );
                                  if (!context.mounted) return;
                                  if (confirm) {
                                    final deps = context
                                        .read<StoreService>()
                                        .getTeacherDependencies(t.id);
                                    final totalDeps = deps.values
                                        .fold<int>(0, (a, b) => a + b);
                                    if (totalDeps > 0) {
                                      final messages = deps.entries
                                          .where((e) => e.value > 0)
                                          .map((e) => '${e.key}: ${e.value}')
                                          .join('\n');
                                      if (!context.mounted) return;
                                      await ConfirmDialog.show(
                                        context: context,
                                        title: 'Suppression bloquée',
                                        message:
                                            'L\'enseignant contient des dépendances:\n$messages\nSupprimez-les d\'abord.',
                                        isDanger: true,
                                      );
                                      return;
                                    }
                                    if (!context.mounted) return;
                                    await context
                                        .read<StoreService>()
                                        .archiveTeacherRemote(t.id);
                                    if (!context.mounted) return;
                                    AppToast.success(
                                        context, 'Enseignant supprimé.');
                                  }
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
        ],
      ),
    );
  }
}
