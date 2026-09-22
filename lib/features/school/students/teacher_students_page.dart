import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../data/models/student_model.dart';
import '../../../data/services/store_service.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_page_header.dart';
import 'student_photo_avatar.dart';

class TeacherStudentsPage extends StatelessWidget {
  const TeacherStudentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final students = context.watch<StoreService>().getStudents().toList()
      ..sort((a, b) {
        final byClass = (a.className ?? '').compareTo(b.className ?? '');
        return byClass != 0 ? byClass : a.fullName.compareTo(b.fullName);
      });
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppPageHeader(
            title: 'Mes élèves',
            subtitle:
                'Uniquement les élèves des classes qui vous sont affectées.',
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
                  Text(student.matricule ?? 'Matricule non renseigné',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    [student.level, student.className]
                        .whereType<String>()
                        .where((value) => value.trim().isNotEmpty)
                        .join(' · '),
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
