import 'package:edupro_flutter_web/data/models/class_model.dart';
import 'package:edupro_flutter_web/data/models/education/school_level_model.dart';
import 'package:edupro_flutter_web/data/models/student_model.dart';
import 'package:edupro_flutter_web/data/services/store_service.dart';
import 'package:edupro_flutter_web/features/school/students/students_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/legacy_store_test_harness.dart';

void main() {
  testWidgets(
      'nouvel eleve affiche scolarite dependante et responsable principal',
      (tester) async {
    final store = await createLegacyStore(withSeedData: true);
    final cycle = await store.createSchoolCycle(code: 'COLLEGE');
    final level = SchoolLevelModel(
      id: 'level-form',
      name: '3e',
      cycle: 'Collège',
      cycleId: cycle.id,
      schoolId: '',
    );
    store.addSchoolLevel(level);
    final year = store.getAcademicYears().first;
    store.setSelectedAcademicYearId(year.id);
    store.addClass(ClassModel(
      id: 'class-form',
      name: '${level.name} A',
      cycleId: cycle.id,
      level: level.name,
      levelId: level.id,
      structuredLevelId: level.id,
      schoolId: 'school-1',
      academicYearId: year.id,
    ));

    await tester.pumpWidget(
      ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const MaterialApp(
          home: Scaffold(body: StudentsPage(openAddModal: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nouvel élève'), findsWidgets);
    expect(find.text('SCOLARITÉ'), findsOneWidget);
    expect(find.text('Cycle *'), findsOneWidget);
    expect(find.text('Niveau *'), findsOneWidget);
    expect(find.text('Classe *'), findsOneWidget);
    expect(find.text('RESPONSABLE LÉGAL PRINCIPAL'), findsOneWidget);
    expect(find.text('Type *'), findsOneWidget);
    expect(find.text('Téléphone du responsable légal *'), findsOneWidget);
    expect(find.text('RESPONSABLE PRINCIPAL (FACULTATIF)'), findsNothing);
    expect(find.text('Nouveau'), findsNothing);
    expect(find.text('Redoublant'), findsNothing);
    expect(find.text('Masculin'), findsOneWidget);
    await tester.tap(find.text('Masculin'));
    await tester.pumpAndSettle();
    expect(find.text('Féminin'), findsOneWidget);
    expect(find.text('Autre'), findsNothing);
  });

  testWidgets(
      'collège masque le régime mais conserve TD au niveau éligible',
      (tester) async {
    final store = await createLegacyStore(withSeedData: true);
    final cycle = await store.createSchoolCycle(code: 'COLLEGE');
    final schoolClass = ClassModel(
      id: 'class-3e',
      name: '3e A',
      level: '3e',
      cycleId: cycle.id,
      schoolId: 'school-1',
      academicYearId: 'year-1',
    );
    store.addClass(schoolClass);
    final student = StudentModel(
      id: 'new-student',
      firstName: 'Nouvel',
      lastName: 'Élève',
      schoolId: schoolClass.schoolId,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => openStudentRegistrationModal(
                context,
                student,
                preselectedYearId: schoolClass.academicYearId,
                preselectedClassId: schoolClass.id,
              ),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();

    expect(find.text('Inscription académique'), findsOneWidget);
    expect(find.textContaining('Régime'), findsNothing);
    expect(find.text('Normal'), findsNothing);
    expect(find.text('Option TD'), findsOneWidget);
    expect(
        find.text('Option académique, sans montant financier'), findsOneWidget);
  });

  testWidgets('primaire affiche uniquement Mi-temps et Plein temps',
      (tester) async {
    final store = await createLegacyStore(withSeedData: true);
    final cycle = await store.createSchoolCycle(code: 'PRIMAIRE');
    final schoolClass = ClassModel(
      id: 'class-cp',
      name: 'CP A',
      level: 'CP',
      cycleId: cycle.id,
      schoolId: 'school-1',
      academicYearId: 'year-1',
    );
    store.addClass(schoolClass);
    final student = StudentModel(
      id: 'primary-student',
      firstName: 'Petit',
      lastName: 'Élève',
      schoolId: schoolClass.schoolId,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => openStudentRegistrationModal(
                context,
                student,
                preselectedYearId: schoolClass.academicYearId,
                preselectedClassId: schoolClass.id,
              ),
              child: const Text('Ouvrir primaire'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ouvrir primaire'));
    await tester.pumpAndSettle();

    expect(find.text('Régime *'), findsOneWidget);
    expect(find.text('Mi-temps'), findsOneWidget);
    await tester.tap(find.text('Mi-temps'));
    await tester.pumpAndSettle();
    expect(find.text('Plein temps'), findsOneWidget);
    expect(find.text('Normal'), findsNothing);
    expect(find.text('Option TD'), findsNothing);
  });

  testWidgets("l'interface ne propose que inscription et reinscription",
      (tester) async {
    final store = await createLegacyStore(withSeedData: true);
    await tester.pumpWidget(
      ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const MaterialApp(
          home: Scaffold(body: StudentsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inscrire / Réinscrire'), findsOneWidget);
    expect(find.textContaining('Préinscription'), findsNothing);
  });

  testWidgets(
      'la réinscription filtre les élèves par classe et masque la décision annuelle',
      (tester) async {
    final store = await createLegacyStore(withSeedData: true);
    store.addClass(ClassModel(
      id: 'class-a',
      name: 'Classe A',
      schoolId: 'school-1',
    ));
    store.addClass(ClassModel(
      id: 'class-b',
      name: 'Classe B',
      schoolId: 'school-1',
    ));
    store.addStudent(StudentModel(
      id: 'student-a',
      firstName: 'Alice',
      lastName: 'Alpha',
      classId: 'class-a',
      className: 'Classe A',
      schoolId: 'school-1',
    ));
    store.addStudent(StudentModel(
      id: 'student-b',
      firstName: 'Bob',
      lastName: 'Beta',
      classId: 'class-b',
      className: 'Classe B',
      schoolId: 'school-1',
    ));

    await tester.pumpWidget(
      ChangeNotifierProvider<StoreService>.value(
        value: store,
        child: const MaterialApp(
          home: Scaffold(body: StudentsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Décision annuelle'), findsNothing);
    await tester.tap(find.text('Inscrire / Réinscrire'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inscription').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réinscription').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    expect(find.text('Filtrer par classe'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reenrollment-class-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Classe B').last);
    await tester.pumpAndSettle();

    // Check the picker, not the still-mounted student table behind the modal.
    final picker = find.byType(AlertDialog);
    expect(find.descendant(of: picker, matching: find.text('Beta Bob')),
        findsOneWidget);
    expect(find.descendant(of: picker, matching: find.text('Alpha Alice')),
        findsNothing);
  });
}
