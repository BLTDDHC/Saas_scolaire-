import 'package:flutter/material.dart';
import 'finance_page.dart';

/// Financial access uses the official school registration, including after transfer.
class StudentAccountPage extends StatelessWidget {
  const StudentAccountPage({super.key, required this.studentId, this.initialRegistrationId});
  final String studentId;
  final String? initialRegistrationId;
  @override
  Widget build(BuildContext context) => FinancePage(initialStudentId: studentId);
}

