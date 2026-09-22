import 'package:edupro_flutter_web/data/datasources/seed_data.dart';
import 'package:edupro_flutter_web/data/models/affectation_model.dart';
import 'package:edupro_flutter_web/data/models/class_model.dart';
import 'package:edupro_flutter_web/data/models/subject_model.dart';
import 'package:edupro_flutter_web/data/models/teacher_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/legacy_store_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('resetDemoData restores the demo seed data', () async {
    final store = await createLegacyStore(withSeedData: true);
    expect(store.getUsers().length, greaterThan(0));

    await store.login('admin@edupro.com', 'demo1234');
    expect(store.currentUser, isNotNull);

    await store.resetDemoData();

    expect(store.currentUser, isNull);

    expect(store.getUsers().length, equals(SeedData.users.length));
    expect(store.getEstablishments().length,
        equals(SeedData.establishments.length));
    expect(store.getStudents().length, equals(SeedData.students.length));
  });

  test('clearDemoData empties demo data and clears the session', () async {
    final store = await createLegacyStore(withSeedData: true);

    expect(store.getUsers().length, greaterThan(0));

    await store.clearDemoData();

    expect(store.currentUser, isNull);
    expect(store.getEstablishments(), isEmpty);
    expect(store.getStudents(), isEmpty);
    expect(store.getUsers(), isEmpty);
    expect(await store.login('admin@edupro.com', legacyTestPassword), isFalse);
  });

  test(
      'classes stay filtered by academic year and room number remains independent',
      () async {
    final store = await createLegacyStore(withSeedData: true);

    final year2026 = 'AY_2026_2027';
    final year2027 = 'AY_2027_2028';
    store.addClass(ClassModel(
      id: 'CL_TEST_2026',
      name: 'Première C',
      cycle: 'Lycée',
      level: 'Première',
      levelId: 'SL_L_1ERE',
      series: 'C',
      seriesId: 'SR_C',
      room: '12',
      schoolId: 'ET015',
      academicYearId: year2026,
    ));
    store.addClass(ClassModel(
      id: 'CL_TEST_2027',
      name: 'Première C',
      cycle: 'Lycée',
      level: 'Première',
      levelId: 'SL_L_1ERE',
      series: 'C',
      seriesId: 'SR_C',
      room: '15',
      schoolId: 'ET015',
      academicYearId: year2027,
    ));

    final year2026Classes = store.getClassesByYear(year2026);
    expect(year2026Classes, hasLength(1));
    expect(year2026Classes.first.name, 'Première C');
    expect(year2026Classes.first.room, '12');
    expect(year2026Classes.first.name.contains('12'), isFalse);

    final year2027Classes = store.getClassesByYear(year2027);
    expect(year2027Classes, hasLength(1));
    expect(year2027Classes.first.room, '15');
  });

  test('legacy schoolYearId metadata remains compatible for assignment records',
      () async {
    final legacyClass = ClassModel.fromJson({
      'id': 'CL_LEGACY',
      'name': '5e A',
      'schoolId': 'ET014',
      'schoolYearId': 'AY_2026_2027',
    });
    final legacySubject = SubjectModel.fromJson({
      'id': 'SUB_LEGACY',
      'name': 'Mathématiques',
      'schoolId': 'ET014',
      'schoolYearId': 'AY_2026_2027',
    });
    final legacyAffectation = AffectationModel.fromJson({
      'id': 'AF_LEGACY',
      'teacherId': 'T1',
      'subjectId': 'SUB_LEGACY',
      'classId': 'CL_LEGACY',
      'schoolId': 'ET014',
      'schoolYearId': 'AY_2026_2027',
      'type': 'teaching',
    });

    expect(legacyClass.academicYearId, 'AY_2026_2027');
    expect(legacySubject.academicYearId, 'AY_2026_2027');
    expect(legacyAffectation.academicYearId, 'AY_2026_2027');
  });

  test(
      'teaching assignments stay separate from the class principal teacher assignment',
      () async {
    final store = await createLegacyStore(withSeedData: true);
    await store.login('admin@edupro.com', legacyTestPassword);

    const yearId = 'AY_2026_2027';
    final classModel = ClassModel(
      id: 'CL_SEPARATE',
      name: '3e A',
      cycle: 'Collège',
      level: '3e',
      schoolId: 'ET014',
      academicYearId: yearId,
    );
    final teacher = TeacherModel(
      id: 'T_SEPARATE',
      firstName: 'Jean',
      lastName: 'Dupont',
      schoolId: 'ET014',
    );
    final math = SubjectModel(
      id: 'SUB_MATH',
      name: 'Mathématiques',
      coefficient: 4,
      schoolId: 'ET014',
      academicYearId: yearId,
    );
    final fr = SubjectModel(
      id: 'SUB_FR',
      name: 'Français',
      coefficient: 3,
      schoolId: 'ET014',
      academicYearId: yearId,
    );

    store.addClass(classModel);
    store.addTeacher(teacher);
    store.addSubject(math);
    store.addSubject(fr);

    final teaching = AffectationModel(
      id: 'AF_TEACHING',
      teacherId: teacher.id,
      teacherName: teacher.fullName,
      subjectId: math.id,
      subject: math.name,
      classId: classModel.id,
      className: classModel.name,
      schoolId: teacher.schoolId,
      academicYearId: yearId,
      type: 'teaching',
    );
    final principal = AffectationModel(
      id: 'AF_PRINCIPAL',
      teacherId: teacher.id,
      teacherName: teacher.fullName,
      classId: classModel.id,
      className: classModel.name,
      schoolId: teacher.schoolId,
      academicYearId: yearId,
      type: 'main_teacher',
    );

    expect(store.addAffectation(teaching), isTrue);
    expect(store.addAffectation(principal), isTrue);

    final classAffectations = store
        .getAffectations()
        .where((a) => a.classId == classModel.id && a.academicYearId == yearId)
        .toList();
    expect(classAffectations.where((a) => a.type == 'teaching'), hasLength(1));
    expect(
        classAffectations.where((a) => a.type == 'main_teacher'), hasLength(1));
    expect(store.getClassById(classModel.id)?.mainTeacher,
        equals(teacher.fullName));

    final frenchTeaching = AffectationModel(
      id: 'AF_FR',
      teacherId: teacher.id,
      teacherName: teacher.fullName,
      subjectId: fr.id,
      subject: fr.name,
      classId: classModel.id,
      className: classModel.name,
      schoolId: teacher.schoolId,
      academicYearId: yearId,
      type: 'teaching',
    );

    expect(store.addAffectation(frenchTeaching), isTrue);
    expect(
        store
            .getAffectations()
            .where(
                (a) => a.type == 'main_teacher' && a.classId == classModel.id)
            .length,
        equals(1));
    expect(
        store
            .getAffectations()
            .where((a) => a.type == 'teaching' && a.classId == classModel.id)
            .length,
        equals(2));
  });
}
