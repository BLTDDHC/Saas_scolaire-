import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/class_model.dart';
import '../../../data/models/academic_year_model.dart';
import '../../../data/models/affectation_model.dart';
import '../../../data/models/teacher_model.dart';
import '../../../data/models/subject_model.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_modal.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_form_field.dart';
import '../../../core/theme/app_colors.dart';

import '../../../data/services/store_service.dart';
import '../students/students_page.dart';

void showClassProfileModal(BuildContext context, ClassModel cls) {
  AppModal.show(
    context: context,
    title: 'Classe — ${cls.name}',
    maxWidth: 760,
    body: SingleChildScrollView(
      child: Consumer<StoreService>(
        builder: (context, store, _) {
          final currentYearId = store.getSelectedAcademicYearId();
          final students = store
              .getStudentsByYear(currentYearId)
              .where((s) => s.className == cls.name)
              .toList();
          final affs = store
              .getAffectations()
              .where((a) =>
                  (a.classId == cls.id || a.className == cls.name) &&
                  (currentYearId == null || a.academicYearId == currentYearId))
              .toList();
          final teachingAssignments =
              affs.where((a) => a.type != 'main_teacher').toList();
          final principalAssignments =
              affs.where((a) => a.type == 'main_teacher').toList();
          final subjects = store
              .getSubjectsByYear(currentYearId)
              .where((s) => teachingAssignments
                  .any((a) => a.subjectId == s.id || a.subject == s.name))
              .toList();

          final principalTeacherName = principalAssignments.isNotEmpty
              ? principalAssignments.first.teacherName ?? cls.mainTeacher
              : cls.mainTeacher;
          final selectedYear = store.getAcademicYears().firstWhere(
              (y) => y.id == currentYearId,
              orElse: () => AcademicYearModel(
                  id: '', name: '', start: '', end: '', schoolId: ''));

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Classe — ${cls.name}',
                            style: AppTypography.heading3()),
                        const SizedBox(height: 6),
                        Text('Niveau : ${cls.level ?? '—'}'),
                        const SizedBox(height: 4),
                        Text(
                            'Année académique : ${selectedYear.name.isNotEmpty ? selectedYear.name : '—'}'),
                        const SizedBox(height: 4),
                        Text(
                            'Élèves : ${students.length} • Matières : ${subjects.length} • Enseignants : ${teachingAssignments.length}'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      principalTeacherName != null &&
                              principalTeacherName.isNotEmpty
                          ? 'Professeur principal : $principalTeacherName'
                          : 'Professeur principal : Aucun',
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s4),
              AppCard(
                title: 'Professeur principal',
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s4),
                  child: Text(principalTeacherName != null &&
                          principalTeacherName.isNotEmpty
                      ? principalTeacherName
                      : 'Aucun'),
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
              AppCard(
                title: 'Enseignants de la classe',
                child: teachingAssignments.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.s4),
                        child: Text('Aucun enseignant assigné à une matière'))
                    : Column(
                        children: teachingAssignments.map((a) {
                          final t = store.getTeachers().firstWhere(
                              (tt) => tt.id == a.teacherId,
                              orElse: () => TeacherModel(
                                  id: '',
                                  firstName: '',
                                  lastName: '',
                                  schoolId: ''));
                          final subj = store.getSubjects().firstWhere(
                              (s) => s.id == a.subjectId,
                              orElse: () => SubjectModel(
                                  id: '',
                                  name: '',
                                  coefficient: 1,
                                  schoolId: ''));
                          return ListTile(
                            title: Text(t.fullName.isNotEmpty
                                ? t.fullName
                                : a.teacherName ?? a.teacherId),
                            subtitle: Text(a.subject ?? subj.name),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Enseignant'),
                                const SizedBox(width: AppSpacing.s2),
                                TextButton(
                                  onPressed: t.id.isNotEmpty
                                      ? () =>
                                          showTeacherProfileModal(context, t)
                                      : null,
                                  child: const Text('Profil'),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
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
                        children: subjects
                            .map((s) => ListTile(
                                title: Text(s.name),
                                subtitle: Text(s.teacher ?? '—')))
                            .toList()),
              ),
              const SizedBox(height: AppSpacing.s3),
              AppCard(
                title: 'Élèves',
                child: students.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.s4),
                        child: Text('Aucun élève'))
                    : Column(
                        children: students
                            .map((s) => ListTile(
                                  title: Text(s.fullName),
                                  subtitle: Text(s.matricule ?? '—'),
                                  trailing: TextButton(
                                    onPressed: () =>
                                        showStudentProfileModal(context, s),
                                    child: const Text('Voir'),
                                  ),
                                ))
                            .toList(),
                      ),
              ),
            ],
          );
        },
      ),
    ),
    footer: Wrap(
      alignment: WrapAlignment.end,
      spacing: AppSpacing.s3,
      runSpacing: AppSpacing.s2,
      children: [
        AppButton(
            label: 'Fermer',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.pop(context)),
        AppButton(
          label: 'Ajouter un élève',
          variant: AppButtonVariant.primary,
          onPressed: () {
            Navigator.pop(context);
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => StudentsPage(
                    initialClassName: cls.name, openAddModal: true)));
          },
        ),
        AppButton(
          label: 'Voir les élèves',
          variant: AppButtonVariant.ghost,
          onPressed: () {
            Navigator.pop(context);
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => StudentsPage(initialClassName: cls.name)));
          },
        ),
        AppButton(
            label: 'Affecter un enseignant',
            variant: AppButtonVariant.primary,
            onPressed: () => _openAssignTeacherModal(context, cls)),
        AppButton(
            label: 'Affecter le principal',
            variant: AppButtonVariant.secondary,
            onPressed: () => _openAssignPrincipalTeacherModal(context, cls)),
      ],
    ),
  );
}

void _openAssignPrincipalTeacherModal(BuildContext context, ClassModel cls) {
  final store = context.read<StoreService>();
  final teachers = store.getTeachers();
  final years = store.getAcademicYears();

  if (teachers.isEmpty || years.isEmpty) {
    AppToast.warning(context,
        'Assurez-vous d’avoir des enseignants et des années académiques avant d’affecter un professeur principal.');
    return;
  }

  String selectedTeacherId = teachers.first.id;
  String selectedYearId = store.getSelectedAcademicYearId() ?? years.first.id;

  AppModal.show(
    context: context,
    title: 'Affecter un professeur principal — ${cls.name}',
    maxWidth: 520,
    body: StatefulBuilder(
      builder: (ctx, setState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Sélectionnez le professeur principal pour cette classe et cette année.'),
            const SizedBox(height: AppSpacing.s4),
            AppSelectField<String>(
              label: 'Professeur principal *',
              value: selectedTeacherId,
              items: teachers
                  .map((t) => DropdownMenuItem(
                      value: t.id,
                      child: Text('${t.fullName} (${t.subject ?? 'Général'})')))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => selectedTeacherId = val);
              },
            ),
            const SizedBox(height: AppSpacing.s4),
            AppSelectField<String>(
              label: 'Année académique *',
              value: selectedYearId,
              items: years
                  .map(
                      (y) => DropdownMenuItem(value: y.id, child: Text(y.name)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => selectedYearId = val);
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
            onPressed: () => Navigator.pop(context)),
        const SizedBox(width: AppSpacing.s3),
        AppButton(
          label: 'Enregistrer',
          variant: AppButtonVariant.primary,
          onPressed: () {
            final teacher =
                teachers.firstWhere((t) => t.id == selectedTeacherId);
            final existing = store.getAffectations().firstWhere(
                  (a) =>
                      a.type == 'main_teacher' &&
                      a.classId == cls.id &&
                      a.academicYearId == selectedYearId,
                  orElse: () => AffectationModel(
                      id: '', teacherId: '', schoolId: teacher.schoolId),
                );

            if (existing.id.isNotEmpty) {
              final updated = AffectationModel(
                id: existing.id,
                teacherId: teacher.id,
                teacherName: teacher.fullName,
                classId: cls.id,
                className: cls.name,
                schoolId: cls.schoolId,
                academicYearId: selectedYearId,
                type: 'main_teacher',
              );
              store.updateAffectation(updated);
            } else {
              final aff = AffectationModel(
                id: 'AF_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
                teacherId: teacher.id,
                teacherName: teacher.fullName,
                classId: cls.id,
                className: cls.name,
                schoolId: cls.schoolId,
                academicYearId: selectedYearId,
                type: 'main_teacher',
              );
              store.addAffectation(aff);
            }

            store.updateClass(cls.copyWith(mainTeacher: teacher.fullName));
            Navigator.pop(context);
            AppToast.success(context,
                'Professeur principal enregistré : ${teacher.fullName}');
          },
        ),
      ],
    ),
  );
}

void showTeacherProfileModal(BuildContext context, TeacherModel teacher) {
  final store = context.read<StoreService>();
  final currentYearId = store.getSelectedAcademicYearId();
  final affs = store
      .getAffectations()
      .where((a) =>
          a.teacherId == teacher.id &&
          (currentYearId == null || a.academicYearId == currentYearId))
      .toList();
  final classes =
      affs.map((a) => a.className).whereType<String>().toSet().toList();
  final subjects =
      affs.map((a) => a.subject).whereType<String>().toSet().toList();
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
              backgroundColor: AppColors.avatarColorFor(teacher.fullName),
              child: Text(teacher.initials,
                  style: const TextStyle(color: Colors.white))),
          const SizedBox(width: AppSpacing.s3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(teacher.fullName, style: AppTypography.heading3()),
              const SizedBox(height: 4),
              Text('Matricule : ${teacher.employeeNumber ?? teacher.id}',
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
            if (teacher.email != null && teacher.email!.isNotEmpty)
              Text('Email : ${teacher.email}'),
            if (teacher.phone != null && teacher.phone!.isNotEmpty)
              Text('Téléphone : ${teacher.phone}'),
            if ((teacher.email == null || teacher.email!.isEmpty) &&
                (teacher.phone == null || teacher.phone!.isEmpty))
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
                    .toList()),
      ),
      const SizedBox(height: AppSpacing.s3),
      AppCard(
        title: 'Classes',
        child: classes.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.s4),
                child: Text('Aucune classe assignée'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: classes
                    .map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.s2),
                        child: Text(c)))
                    .toList()),
      ),
    ],
  );

  AppModal.show(
    context: context,
    title: 'Profil Enseignant — ${teacher.lastName} ${teacher.firstName}',
    body: body,
    maxWidth: 640,
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

void _openAssignTeacherModal(BuildContext context, ClassModel cls) {
  final store = context.read<StoreService>();
  final teachers = store.getTeachers();
  final subjects = store.getSubjects();
  final years = store.getAcademicYears();
  if (teachers.isEmpty || subjects.isEmpty || years.isEmpty) {
    AppToast.warning(context,
        'Assurez-vous d\'avoir des enseignants, matières et années académiques avant.');
    return;
  }

  String selectedTeacherId = teachers.first.id;
  String selectedSubjectId = subjects.first.id;
  String selectedYearId = store.getSelectedAcademicYearId() ?? years.first.id;
  final selectedClassId = cls.id;

  AppModal.show(
    context: context,
    title: 'Affecter un enseignant — ${cls.name}',
    maxWidth: 520,
    body: StatefulBuilder(builder: (ctx, setState) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
              'Sélectionnez l\'enseignant, la matière et l\'année académique.'),
          const SizedBox(height: AppSpacing.s4),
          AppSelectField<String>(
            label: 'Enseignant *',
            value: selectedTeacherId,
            items: teachers
                .map((t) => DropdownMenuItem(
                    value: t.id,
                    child: Text('${t.fullName} (${t.subject ?? "Général"})')))
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => selectedTeacherId = val);
            },
          ),
          const SizedBox(height: AppSpacing.s4),
          AppSelectField<String>(
            label: 'Matière *',
            value: selectedSubjectId,
            items: subjects
                .map((s) => DropdownMenuItem(
                    value: s.id, child: Text('${s.icon ?? "📚"} ${s.name}')))
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => selectedSubjectId = val);
            },
          ),
          const SizedBox(height: AppSpacing.s4),
          AppSelectField<String>(
            label: 'Année académique *',
            value: selectedYearId,
            items: years
                .map((y) => DropdownMenuItem(value: y.id, child: Text(y.name)))
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => selectedYearId = val);
            },
          ),
          const SizedBox(height: AppSpacing.s4),
          AppSelectField<String>(
            label: 'Classe *',
            value: selectedClassId,
            items: [
              DropdownMenuItem(
                  value: cls.id,
                  child: Text('${cls.name} (${cls.level ?? ''})'))
            ],
            onChanged: null,
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
            onPressed: () => Navigator.pop(context)),
        const SizedBox(width: AppSpacing.s3),
        AppButton(
          label: 'Créer l\'affectation',
          variant: AppButtonVariant.primary,
          onPressed: () {
            final teacher =
                teachers.firstWhere((t) => t.id == selectedTeacherId);
            final subject =
                subjects.firstWhere((s) => s.id == selectedSubjectId);
            final className = cls.name;
            final exists = store.getAffectations().any((a) =>
                a.teacherId == teacher.id &&
                (a.subjectId == subject.id || a.subject == subject.name) &&
                (a.classId == selectedClassId || a.className == className) &&
                a.academicYearId == selectedYearId);
            if (exists) {
              AppToast.warning(context,
                  'Cette affectation existe déjà pour la même classe, matière et année académique.');
              return;
            }

            final school = store.getCurrentSchool();
            final affectation = AffectationModel(
              id: 'AF_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
              teacherId: teacher.id,
              teacherName: teacher.fullName,
              subjectId: subject.id,
              subject: subject.name,
              classId: selectedClassId,
              className: className,
              schoolId: school?.id ?? 'ET001',
              academicYearId: selectedYearId,
            );

            store.addAffectation(affectation);
            Navigator.pop(context);
            AppToast.success(context,
                'Affectation créée : ${teacher.fullName} ➔ ${subject.name} ➔ ${cls.name}');
          },
        ),
      ],
    ),
  );
}
