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

  int _compareStudents(StudentModel left, StudentModel right) {
    final byClass = _normalized(left.className ?? '')
        .compareTo(_normalized(right.className ?? ''));
    if (byClass != 0) return byClass;
    final byLastName =
        _normalized(left.lastName).compareTo(_normalized(right.lastName));
    if (byLastName != 0) return byLastName;
    final byFirstName =
        _normalized(left.firstName).compareTo(_normalized(right.firstName));
    if (byFirstName != 0) return byFirstName;
    return left.id.compareTo(right.id);
  }

  @override
  Widget build(BuildContext context) {
    final allStudents = context.watch<StoreService>().getStudents().toList()
      ..sort(_compareStudents);
    final classOptions = <String, String>{};
    for (final student in allStudents) {
      final id = student.classId;
      if (id == null || id.isEmpty) continue;
      classOptions[id] = student.className ?? 'Classe';
    }
    final orderedClasses = classOptions.entries.toList()
      ..sort((a, b) => _normalized(a.value).compareTo(_normalized(b.value)));
    if (_classId != null && !classOptions.containsKey(_classId)) {
      _classId = null;
    }
    final students = _classId == null
        ? allStudents
        : allStudents.where((item) => item.classId == _classId).toList();

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
          if (orderedClasses.isNotEmpty)
            SizedBox(
              width: 320,
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
                  ...orderedClasses.map(
                    (entry) => DropdownMenuItem<String?>(
                      value: entry.key,
                      child: Text(entry.value, overflow: TextOverflow.ellipsis),
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
                    student.className ?? 'Classe non renseignée',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((student.matricule ?? '').trim().isNotEmpty)
                    Text(
                      'Matricule : ${student.matricule}',
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
