import 'package:test/test.dart';
import 'package:edupro_flutter_web/data/models/grade_model.dart';
import 'package:edupro_flutter_web/data/models/evaluation_model.dart';
import 'package:edupro_flutter_web/data/models/subject_model.dart';
import 'package:edupro_flutter_web/data/models/student_model.dart';
import 'package:edupro_flutter_web/data/services/result_service.dart';

void main() {
  group('ResultService pure calculations', () {
    test('TEST 1: D1=12,D2=14,D3=16 -> MC=14', () {
      final evaluations = [
        EvaluationModel(id: 'E1', title: 'D1', type: 'devoir', academicYearId: 'AY', classId: 'C1', subjectId: 'S1', createdBy: '', createdAt: '', schoolId: ''),
        EvaluationModel(id: 'E2', title: 'D2', type: 'devoir', academicYearId: 'AY', classId: 'C1', subjectId: 'S1', createdBy: '', createdAt: '', schoolId: ''),
        EvaluationModel(id: 'E3', title: 'D3', type: 'devoir', academicYearId: 'AY', classId: 'C1', subjectId: 'S1', createdBy: '', createdAt: '', schoolId: ''),
      ];

      final grades = [
        GradeModel(id: 'G1', studentId: 'ST1', subjectId: 'S1', eval: 'D1', grade: 12, evaluationId: 'E1'),
        GradeModel(id: 'G2', studentId: 'ST1', subjectId: 'S1', eval: 'D2', grade: 14, evaluationId: 'E2'),
        GradeModel(id: 'G3', studentId: 'ST1', subjectId: 'S1', eval: 'D3', grade: 16, evaluationId: 'E3'),
      ];

      final mc = ResultService.calculateHomeworkAverageFromGrades(grades, evaluations, 'ST1', 'C1', 'S1', null, 'AY');
      expect(mc, 14.0);
    });

    test('TEST 2: D1=12,D2 non saisi,D3=16 -> MC=14', () {
      final evaluations = [
        EvaluationModel(id: 'E1', title: 'D1', type: 'devoir', academicYearId: 'AY', classId: 'C1', subjectId: 'S1', createdBy: '', createdAt: '', schoolId: ''),
        EvaluationModel(id: 'E2', title: 'D2', type: 'devoir', academicYearId: 'AY', classId: 'C1', subjectId: 'S1', createdBy: '', createdAt: '', schoolId: ''),
        EvaluationModel(id: 'E3', title: 'D3', type: 'devoir', academicYearId: 'AY', classId: 'C1', subjectId: 'S1', createdBy: '', createdAt: '', schoolId: ''),
      ];

      final grades = [
        GradeModel(id: 'G1', studentId: 'ST1', subjectId: 'S1', eval: 'D1', grade: 12, evaluationId: 'E1'),
        // E2 missing
        GradeModel(id: 'G3', studentId: 'ST1', subjectId: 'S1', eval: 'D3', grade: 16, evaluationId: 'E3'),
      ];

      final mc = ResultService.calculateHomeworkAverageFromGrades(grades, evaluations, 'ST1', 'C1', 'S1', null, 'AY');
      expect(mc, 14.0);
    });

    test('TEST 3: D1=0, D2=10 -> MC=5', () {
      final evaluations = [
        EvaluationModel(id: 'E1', title: 'D1', type: 'devoir', academicYearId: 'AY', classId: 'C1', subjectId: 'S1', createdBy: '', createdAt: '', schoolId: ''),
        EvaluationModel(id: 'E2', title: 'D2', type: 'devoir', academicYearId: 'AY', classId: 'C1', subjectId: 'S1', createdBy: '', createdAt: '', schoolId: ''),
      ];

      final grades = [
        GradeModel(id: 'G1', studentId: 'ST1', subjectId: 'S1', eval: 'D1', grade: 0, evaluationId: 'E1'),
        GradeModel(id: 'G2', studentId: 'ST1', subjectId: 'S1', eval: 'D2', grade: 10, evaluationId: 'E2'),
      ];

      final mc = ResultService.calculateHomeworkAverageFromGrades(grades, evaluations, 'ST1', 'C1', 'S1', null, 'AY');
      expect(mc, 5.0);
    });

    test('TEST 4: MC=14, Composition=16 -> moyenne matière=15', () {
      final evaluations = [
        EvaluationModel(id: 'E1', title: 'D1', type: 'devoir', academicYearId: 'AY', classId: 'C1', subjectId: 'S1', createdBy: '', createdAt: '', schoolId: ''),
        EvaluationModel(id: 'EC', title: 'Comp', type: 'composition', academicYearId: 'AY', classId: 'C1', subjectId: 'S1', createdBy: '', createdAt: '', schoolId: ''),
      ];

      final grades = [
        GradeModel(id: 'G1', studentId: 'ST1', subjectId: 'S1', eval: 'D1', grade: 14, evaluationId: 'E1'),
        GradeModel(id: 'GC', studentId: 'ST1', subjectId: 'S1', eval: 'Comp', grade: 16, evaluationId: 'EC'),
      ];

      final student = StudentModel(id: 'ST1', firstName: 'A', lastName: 'B', schoolId: '');
      final subject = SubjectModel(id: 'S1', name: 'Maths', coefficient: 4, schoolId: '');
      final sr = ResultService.calculateSubjectResultFromLists(grades, evaluations, subject, student, 'C1', null, 'AY');
      expect(sr.homeworkAverage, 14.0);
      expect(sr.compositionGrade, 16.0);
      expect(sr.subjectAverage, 15.0);
    });

    test('TEST 5: moyenne générale pondérée', () {
      // Maths 15 coef4, Francais 13 coef3, Anglais 14 coef2
      final sr1 = SubjectResult(studentId: 'ST1', subjectId: 'M', homeworkAverage: 14, compositionGrade: 16, subjectAverage: 15, coefficient: 4, isCalculable: true);
      final sr2 = SubjectResult(studentId: 'ST1', subjectId: 'F', homeworkAverage: 12, compositionGrade: 14, subjectAverage: 13, coefficient: 3, isCalculable: true);
      final sr3 = SubjectResult(studentId: 'ST1', subjectId: 'A', homeworkAverage: 13, compositionGrade: 15, subjectAverage: 14, coefficient: 2, isCalculable: true);

      final studentResult = ResultService.calculateGeneralAverageFromSubjectResults([sr1, sr2, sr3]);
      // (15*4 + 13*3 + 14*2) / 9 = (60 + 39 + 28) /9 = 127/9 = 14.111... -> 14.11
      expect(studentResult.generalAverage, 14.11);
    });
  });
}
