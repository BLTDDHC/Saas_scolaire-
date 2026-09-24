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
      'primaire expose uniquement Mi-temps et Plein temps',
      (tester) async {
    final store = await createLegacyStore(withSeedData: true);
    final cycle = await store.createSchoolCycle(code: 'PRIMAIRE');
    final year = store.getAcademicYears().first;
    final level = SchoolLevelModel(
      id: 'level-cm1-regime',
      name: 'CM1',
      code: 'CM1',
      cycle: 'Primaire',
      cycleId: cycle.id,
      schoolId: 'school-1',
    );
    store.addSchoolLevel(level);
    final schoolClass = ClassModel(
      id: 'class-cm1-regime',
      name: 'CM1 A',
      cycleId: cycle.id,
      level: 'CM1',
      levelId: level.id,
      structuredLevelId: level.id,
      schoolId: 'school-1',
      academicYearId: year.id,
    );
    store.addClass(schoolClass);
    final student = StudentModel(
      id: 'new-primary-student',
      firstName: 'Nouvel',
      lastName: 'Primaire',
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
                preselectedYearId: year.id,
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
    expect(find.text('Régime *'), findsOneWidget);
    expect(find.text('Plein temps'), findsOneWidget);
    await tester.tap(find.text('Plein temps'));
    await tester.pumpAndSettle();
    expect(find.text('Mi-temps'), findsOneWidget);
    expect(find.text('Normal'), findsNothing);
  });

  testWidgets('collège ne présente aucun champ Régime', (tester) async {
    final store = await createLegacyStore(withSeedData: true);
    final cycle = await store.createSchoolCycle(code: 'COLLEGE');
    final year = store.getAcademicYears().first;
    final level = SchoolLevelModel(
      id: 'level-3e-no-regime',
      name: '3e',
      code: '3E',
      cycle: 'Collège',
      cycleId: cycle.id,
      schoolId: 'school-1',
    );
    store.addSchoolLevel(level);
    final schoolClass = ClassModel(
      id: 'class-3e-no-regime',
      name: '3e A',
      cycleId: cycle.id,
      level: '3e',
      levelId: level.id,
      structuredLevelId: level.id,
      schoolId: 'school-1',
      academicYearId: year.id,
    );
    store.addClass(schoolClass);
    final student = StudentModel(
      id: 'new-college-student',
      firstName: 'Nouvel',
      lastName: 'Collège',
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
                preselectedYearId: year.id,
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
    expect(find.text('Régime *'), findsNothing);
    expect(find.byKey(const Key('student-school-regime')), findsNothing);
    expect(find.text('Mi-temps'), findsNothing);
    expect(find.text('Plein temps'), findsNothing);
    expect(find.text('Option TD'), findsOneWidget);
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
