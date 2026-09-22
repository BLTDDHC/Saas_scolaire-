import 'package:flutter/material.dart';

import '../grades/canonical_grades_page.dart';

/// Les devoirs de ce produit sont des evaluations surveillees et notees.
/// Cette entree reutilise donc le moteur canonique Evaluations/Notes au lieu
/// de l ancien modele de devoir maison `school_assignments`.
class AssignmentsPage extends StatelessWidget {
  const AssignmentsPage({super.key});

  @override
  Widget build(BuildContext context) => const CanonicalGradesPage();
}
