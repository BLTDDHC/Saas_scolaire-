import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../data/models/student_model.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_page_header.dart';
import 'student_photo_avatar.dart';

class TeacherStudentsPage extends StatefulWidget {
  const TeacherStudentsPage({super.key});

  @override
  State<TeacherStudentsPage> createState() => _TeacherStudentsPageState();
}

class _TeacherStudentsPageState extends State<TeacherStudentsPage> {
  String? _classId;

  String _normalized(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[àáâäãå]'), 'a')
      .replaceAll(RegExp(r'[ç]'), 'c')
      .replaceAll(RegExp(r'[èéêë]'), 'e')
      .replaceAll(RegExp(r'[ìíîï]'), 'i')
      .replaceAll(RegExp(r'[ñ]'), 'n')
      .replaceAll(RegExp(r'[òóôöõ]'), 'o')
      .replaceAll(RegExp(r'[ùúûü]'), 'u')
      .replaceAll(RegExp(r'[ýÿ]'), 'y');

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final teacherId = store.getCurrentTeacherId();
    final taughtClassIds = store
        .getAffectations()
        .where((item) => teacherId != null && item.teacherId == teacherId)
        .map((item) => item.classId)
        .toSet();
    final classById = {
      for (final item in store.getClasses())
        if (taughtClassIds.contains(item.id)) item.id: item,
    };
    final classes = classById.values.toList()
      ..sort((a, b) => _normalized(a.name).compareTo(_normalized(b.name)));

    if (_classId != null && !taughtClassIds.contains(_classId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _classId = null);
      });
    }

    final students = store
        .getStudents()
        .where((student) =>
            student.classId != null &&
            taughtClassIds.contains(student.classId) &&
            (_classId == null || student.classId == _classId))
        .toList()
      ..sort((a, b) {
        final classA = classById[a.classId]?.name ?? a.className ?? '';
        final classB = classById[b.classId]?.name ?? b.className ?? '';
        final byClass = _normalized(classA).compareTo(_normalized(classB));
        if (byClass != 0) return byClass;
        final byLastName =
            _normalized(a.lastName).compareTo(_normalized(b.lastName));
        if (byLastName != 0) return byLastName;
        final byFirstName =
            _normalized(a.firstName).compareTo(_normalized(b.firstName));
        if (byFirstName != 0) return byFirstName;
        return a.id.compareTo(b.id);
      });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppPageHeader(
            title: 'Mes élèves',
            subtitle:
                'Uniquement les élèves des classes dans lesquelles vous enseignez.',
          ),
          const SizedBox(height: AppSpacing.s4),
          if (classes.isNotEmpty)
            SizedBox(
              width: 340,
              child: DropdownButtonFormField<String?>(
                key: const Key('teacher-students-class-filter'),
                initialValue: _classId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Classe'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Toutes mes classes'),
                  ),
                  ...classes.map(
                    (item) => DropdownMenuItem<String?>(
                      value: item.id,
                      child: Text(item.name, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _classId = value),
              ),
            ),
          const SizedBox(height: AppSpacing.s5),
          if (students.isEmpty)
            const AppEmptyState(
              iconData: Icons.people_outline_rounded,
              title: 'Aucun élève affecté',
              message:
                  'Les élèves apparaîtront ici dès qu’une classe vous sera affectée.',
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth < 620
                    ? constraints.maxWidth
                    : constraints.maxWidth < 1050
                        ? (constraints.maxWidth - AppSpacing.s3) / 2
                        : (constraints.maxWidth - AppSpacing.s3 * 2) / 3;
                return Wrap(
                  spacing: AppSpacing.s3,
                  runSpacing: AppSpacing.s3,
                  children: students
                      .map((student) => SizedBox(
                            width: cardWidth,
                            child: _StudentCard(student: student),
                          ))
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.student});

  final StudentModel student;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Row(
          children: [
            if (student.photoUrl != null)
              StudentPhotoAvatar(
                studentId: student.id,
                initials: student.initials,
                radius: 25,
              )
            else
              CircleAvatar(radius: 25, child: Text(student.initials)),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(student.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(student.className ?? 'Classe non renseignée',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(student.matricule ?? 'Matricule non renseigné',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      );
}
