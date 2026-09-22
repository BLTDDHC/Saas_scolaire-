import 'package:test/test.dart';
import 'package:edupro_flutter_web/data/models/class_model.dart';
import 'package:edupro_flutter_web/data/models/student_model.dart';

void main() {
  group('School hierarchy models', () {
    test('Primary class CM2 A has correct cycle and level and null series', () {
      final cls = ClassModel(
        id: 'CL001',
        name: 'CM2 A',
        cycle: 'Primaire',
        level: 'CM2',
        levelId: 'SL_P_CM2',
        series: null,
        seriesId: null,
        schoolId: 'ET013',
      );

      expect(cls.cycle, 'Primaire');
      expect(cls.level, 'CM2');
      expect(cls.series, isNull);
    });

    test('College class 3e A has correct cycle and level and null series', () {
      final cls = ClassModel(
        id: 'CL002',
        name: '3e A',
        cycle: 'Collège',
        level: '3e',
        levelId: 'SL_C_3E',
        series: null,
        seriesId: null,
        schoolId: 'ET014',
      );

      expect(cls.cycle, 'Collège');
      expect(cls.level, '3e');
      expect(cls.series, isNull);
    });

    test('Highschool class 1ère A1 with series A', () {
      final cls = ClassModel(
        id: 'CL003',
        name: '1ère A1',
        cycle: 'Lycée',
        level: 'Première',
        levelId: 'SL_L_1ERE',
        series: 'A',
        seriesId: 'SR_A',
        schoolId: 'ET015',
      );

      final s1 = StudentModel(
        id: 'EL001',
        firstName: 'Jean',
        lastName: 'Dupont',
        classId: cls.id,
        className: cls.name,
        cycle: cls.cycle,
        level: cls.level,
        levelId: cls.levelId,
        series: cls.series,
        seriesId: cls.seriesId,
        schoolId: cls.schoolId,
      );

      expect(s1.classId, cls.id);
      expect(s1.level, 'Première');
      expect(s1.series, 'A');
      expect(s1.levelId, 'SL_L_1ERE');
      expect(s1.seriesId, 'SR_A');
    });

    test('ClassModel keeps room number and school year separate from the class name', () {
      final original = ClassModel(
        id: 'CL004',
        name: 'Première C',
        cycle: 'Lycée',
        level: 'Première',
        levelId: 'SL_L_1ERE',
        series: 'C',
        seriesId: 'SR_C',
        room: '12',
        schoolId: 'ET015',
        academicYearId: 'AY_2026_2027',
      );

      expect(original.name, 'Première C');
      expect(original.room, '12');
      expect(original.roomNumber, '12');
      expect(original.schoolYearId, 'AY_2026_2027');
      expect(original.name.contains('12'), isFalse);

      final json = original.toJson();
      final restored = ClassModel.fromJson(json);

      expect(restored.name, 'Première C');
      expect(restored.room, '12');
      expect(restored.roomNumber, '12');
      expect(restored.academicYearId, 'AY_2026_2027');
      expect(restored.schoolYearId, 'AY_2026_2027');
    });
  });
}
