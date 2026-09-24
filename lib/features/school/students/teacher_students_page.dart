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
    final yearId = store.getSelectedAcademicYearId();
    final affectations = store.getAffectations().where((item) {
      if (item.teacherId != teacherId) return false;
      return yearId == null ||
          item.academicYearId == null ||
          item.academicYearId == yearId;
    }).toList();
    final taughtClassIds = affectations.map((item) => item.classId).toSet();
    final taughtClasses = store
        .getClasses()
        .where((item) => taughtClassIds.contains(item.id))
        .toList()
      ..sort((a, b) => _normalized(a.name).compareTo(_normalized(b.name)));

    if (_classId != null && !taughtClassIds.contains(_classId)) {
      _classId = null;
    }

    final classNameById = {for (final item in taughtClasses) item.id: item.name};
    final students = store.getStudents().where((student) {
      if (!taughtClassIds.contains(student.classId)) return false;
      return _classId == null || student.classId == _classId;
    }).toList()
      ..sort((a, b) {
        final byClass = _normalized(classNameById[a.classId] ?? a.className ?? '')
            .compareTo(_normalized(classNameById[b.classId] ?? b.className ?? ''));
        if (byClass != 0) return byClass;
        final byLast = _normalized(a.lastName).compareTo(_normalized(b.lastName));
        if (byLast != 0) return byLast;
        final byFirst =
            _normalized(a.firstName).compareTo(_normalized(b.firstName));
        return byFirst != 0 ? byFirst : a.id.compareTo(b.id);
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
          if (taughtClasses.isNotEmpty)
            SizedBox(
              width: 360,
              child: DropdownButtonFormField<String?>(
                key: const Key('teacher-students-class-filter'),
                isExpanded: true,
                initialValue: _classId,
                decoration: const InputDecoration(labelText: 'Classe'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Toutes mes classes'),
                  ),
                  ...taughtClasses.map(
                    (schoolClass) => DropdownMenuItem<String?>(
                      value: schoolClass.id,
                      child: Text(
                        schoolClass.name,
                        overflow: TextOverflow.ellipsis,
                      ),
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
              title: 'Aucun élève dans ce périmètre',
              message:
                  'Les élèves apparaîtront ici dès qu’une classe enseignée contient des inscriptions actives.',
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
                      .map(
                        (student) => SizedBox(
                          width: cardWidth,
                          child: _StudentCard(student: student),
                        ),
                      )
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
                  Text(
                    student.lastName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    student.firstName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    student.matricule ?? 'Matricule non renseigné',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    student.className ?? 'Classe non renseignée',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
