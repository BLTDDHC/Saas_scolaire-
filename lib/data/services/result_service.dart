import '../models/grade_model.dart';
import '../models/evaluation_model.dart';
import '../models/subject_model.dart';
import '../models/student_model.dart';
import 'store_service.dart';

/// Result objects
class SubjectResult {
  final String studentId;
  final String subjectId;
  final double? homeworkAverage; // MC
  final double? compositionGrade;
  final double? subjectAverage;
  final double coefficient;
  final bool isCalculable;

  SubjectResult({
    required this.studentId,
    required this.subjectId,
    this.homeworkAverage,
    this.compositionGrade,
    this.subjectAverage,
    required this.coefficient,
    required this.isCalculable,
  });
}

class StudentResult {
  final String studentId;
  final double? generalAverage;
  final double totalCoefficients;
  final bool isCalculable;

  StudentResult({
    required this.studentId,
    this.generalAverage,
    required this.totalCoefficients,
    required this.isCalculable,
  });
}

class RankingEntry {
  final String studentId;
  final double? average;
  final int? rank; // null if non-classified
  final bool isClassified;

  RankingEntry(
      {required this.studentId,
      this.average,
      this.rank,
      required this.isClassified});
}

class HomeworkSummary {
  final List<double?> gradesOrdered;
  final int totalDevoirs;
  final int missingCount;
  final int absentCount;
  final int presentCount;
  final double? average;

  HomeworkSummary({
    required this.gradesOrdered,
    required this.totalDevoirs,
    required this.missingCount,
    required this.absentCount,
    required this.presentCount,
    this.average,
  });
}

class ResultService {
  // pure functions that operate on lists so they're easy to test

  static double? calculateHomeworkAverageFromGrades(
    List<GradeModel> grades,
    List<EvaluationModel> evaluations,
    String studentId,
    String classId,
    String subjectId,
    String? periodId,
    String academicYearId,
  ) {
    // select evaluations of type 'devoir' matching class/subject/period/year
    final evalIds = evaluations
        .where((e) =>
            e.type == 'devoir' &&
            e.classId == classId &&
            e.subjectId == subjectId &&
            e.academicYearId == academicYearId &&
            (periodId == null || e.periodId == periodId))
        .map((e) => e.id)
        .toSet();

    final studentGrades = grades
        .where((g) =>
            g.studentId == studentId &&
            g.evaluationId != null &&
            evalIds.contains(g.evaluationId))
        .toList();

    // include grades that are explicitly entered (grade != null). Include zero.
    final considered = studentGrades
        .where((g) => g.grade != null)
        .map((g) => g.grade!)
        .toList();
    if (considered.isEmpty) return null;
    final sum = considered.fold<double>(0, (a, b) => a + b);
    final avg = sum / considered.length;
    return _round(avg);
  }

  static double? getCompositionGradeFromGrades(
    List<GradeModel> grades,
    List<EvaluationModel> evaluations,
    String studentId,
    String classId,
    String subjectId,
    String? periodId,
    String academicYearId,
  ) {
    final comps = evaluations
        .where((e) =>
            e.type == 'composition' &&
            e.classId == classId &&
            e.subjectId == subjectId &&
            e.academicYearId == academicYearId &&
            (periodId == null || e.periodId == periodId))
        .toList();
    if (comps.isEmpty) return null;
    // take first composition (there should be at most one per pair)
    final compId = comps.first.id;
    final g = grades.firstWhere(
        (gr) => gr.studentId == studentId && gr.evaluationId == compId,
        orElse: () => GradeModel(
            id: '', studentId: '', subjectId: '', eval: '', grade: null));
    if (g.id.isEmpty || g.grade == null) return null;
    return _round(g.grade!);
  }

  static SubjectResult calculateSubjectResultFromLists(
    List<GradeModel> grades,
    List<EvaluationModel> evaluations,
    SubjectModel subject,
    StudentModel student,
    String classId,
    String? periodId,
    String academicYearId,
  ) {
    // If subject belongs to a higher education establishment, do not apply secondary rules here
    final homeworkAvg = calculateHomeworkAverageFromGrades(grades, evaluations,
        student.id, classId, subject.id, periodId, academicYearId);
    final comp = getCompositionGradeFromGrades(grades, evaluations, student.id,
        classId, subject.id, periodId, academicYearId);

    // Centralized subject average calculation (configurable point)
    double? subjAvg;
    bool calculable = false;
    if (homeworkAvg != null && comp != null) {
      subjAvg =
          calculateSubjectAverageStandalone(homeworkAvg, comp, null, periodId);
      calculable = subjAvg != null;
    }

    return SubjectResult(
      studentId: student.id,
      subjectId: subject.id,
      homeworkAverage: homeworkAvg,
      compositionGrade: comp,
      subjectAverage: subjAvg,
      coefficient: subject.coefficient.toDouble(),
      isCalculable: calculable,
    );
  }

  /// Centralized standalone subject average calculator.
  /// Can be replaced by institution-specific logic in the future.
  static double? calculateSubjectAverageStandalone(
      double? homeworkAverage,
      double? compositionGrade,
      String? institutionType,
      String? academicPeriod) {
    if (homeworkAverage == null || compositionGrade == null) return null;
    return _round((homeworkAverage + compositionGrade) / 2.0);
  }

  static StudentResult calculateGeneralAverageFromSubjectResults(
      List<SubjectResult> subjectResults) {
    final valid = subjectResults.where((s) => s.isCalculable).toList();
    if (valid.isEmpty)
      return StudentResult(
          studentId:
              subjectResults.isNotEmpty ? subjectResults.first.studentId : '',
          generalAverage: null,
          totalCoefficients: 0,
          isCalculable: false);
    double numerator = 0;
    double denom = 0;
    for (final s in valid) {
      numerator += (s.subjectAverage ?? 0) * s.coefficient;
      denom += s.coefficient;
    }
    if (denom == 0)
      return StudentResult(
          studentId: valid.first.studentId,
          generalAverage: null,
          totalCoefficients: 0,
          isCalculable: false);
    final gen = _round(numerator / denom);
    return StudentResult(
        studentId: valid.first.studentId,
        generalAverage: gen,
        totalCoefficients: denom,
        isCalculable: true);
  }

  // Wrapper that uses StoreService to fetch lists and compute
  final StoreService store;
  ResultService(this.store);

  SubjectResult calculateSubjectResult(
      String studentId, String classId, String subjectId, String? periodId) {
    final subject = store.getSubjects().firstWhere((s) => s.id == subjectId,
        orElse: () =>
            SubjectModel(id: '', name: '', coefficient: 1, schoolId: ''));
    if (subject.id.isEmpty)
      return SubjectResult(
          studentId: studentId,
          subjectId: subjectId,
          homeworkAverage: null,
          compositionGrade: null,
          subjectAverage: null,
          coefficient: 1,
          isCalculable: false);

    // If subject's establishment is higher education, do not compute here
    final school = store.getEstablishmentById(subject.schoolId);
    if (school != null && school.isHigherEducation) {
      return SubjectResult(
          studentId: studentId,
          subjectId: subjectId,
          homeworkAverage: null,
          compositionGrade: null,
          subjectAverage: null,
          coefficient: subject.coefficient.toDouble(),
          isCalculable: false);
    }

    final selectedYear = store.getSelectedAcademicYearId() ?? '';
    final grades = store
        .getGrades()
        .where((g) =>
            selectedYear.isEmpty ||
            g.academicYearId == null ||
            g.academicYearId!.isEmpty ||
            g.academicYearId == selectedYear)
        .toList();
    final evaluations = store
        .getEvaluations()
        .where((e) =>
            selectedYear.isEmpty ||
            e.academicYearId.isEmpty ||
            e.academicYearId == selectedYear)
        .toList();

    final studentModel = store.getStudents().firstWhere(
        (st) => st.id == studentId,
        orElse: () =>
            StudentModel(id: '', firstName: '', lastName: '', schoolId: ''));
    if (studentModel.id.isEmpty)
      return SubjectResult(
          studentId: studentId,
          subjectId: subjectId,
          homeworkAverage: null,
          compositionGrade: null,
          subjectAverage: null,
          coefficient: subject.coefficient.toDouble(),
          isCalculable: false);

    return calculateSubjectResultFromLists(grades, evaluations, subject,
        studentModel, classId, periodId, selectedYear);
  }

  StudentResult calculateGeneralAverage(
      String studentId, String classId, String? periodId) {
    final subjects = store.getSubjectsByYear(store.getSelectedAcademicYearId());
    final subjectResults = <SubjectResult>[];
    final student = store.getStudents().firstWhere((s) => s.id == studentId,
        orElse: () =>
            StudentModel(id: '', firstName: '', lastName: '', schoolId: ''));
    if (student.id.isEmpty)
      return StudentResult(
          studentId: studentId,
          generalAverage: null,
          totalCoefficients: 0,
          isCalculable: false);

    for (final subj in subjects) {
      // only consider subjects relevant to the class: for simplicity include all subjects (UI may filter)
      final sr = calculateSubjectResultFromLists(
          store.getGrades(),
          store.getEvaluations(),
          subj,
          student,
          classId,
          periodId,
          store.getSelectedAcademicYearId() ?? '');
      subjectResults.add(sr);
    }

    return calculateGeneralAverageFromSubjectResults(subjectResults);
  }

  /// Official helpers: use only validated/locked evaluations (for official bulletins)
  SubjectResult calculateSubjectResultOfficial(
      String studentId, String classId, String subjectId, String? periodId) {
    final yearId = store.getSelectedAcademicYearId() ?? '';
    final subject = store.getSubjects().firstWhere((s) => s.id == subjectId,
        orElse: () =>
            SubjectModel(id: '', name: '', coefficient: 1, schoolId: ''));
    if (subject.id.isEmpty)
      return SubjectResult(
          studentId: studentId,
          subjectId: subjectId,
          homeworkAverage: null,
          compositionGrade: null,
          subjectAverage: null,
          coefficient: 1,
          isCalculable: false);
    final school = store.getEstablishmentById(subject.schoolId);
    if (school != null && school.isHigherEducation)
      return SubjectResult(
          studentId: studentId,
          subjectId: subjectId,
          homeworkAverage: null,
          compositionGrade: null,
          subjectAverage: null,
          coefficient: subject.coefficient.toDouble(),
          isCalculable: false);

    final evals = store
        .getEvaluations()
        .where((e) =>
            (yearId.isEmpty ||
                e.academicYearId.isEmpty ||
                e.academicYearId == yearId) &&
            e.classId == classId &&
            e.subjectId == subjectId &&
            (periodId == null || e.periodId == periodId) &&
            (e.status == 'validated' || e.status == 'locked'))
        .toList();
    final grades = store
        .getGrades()
        .where((g) =>
            yearId.isEmpty ||
            g.academicYearId == null ||
            g.academicYearId!.isEmpty ||
            g.academicYearId == yearId)
        .toList();
    final studentModel = store.getStudents().firstWhere(
        (s) => s.id == studentId,
        orElse: () =>
            StudentModel(id: '', firstName: '', lastName: '', schoolId: ''));
    if (studentModel.id.isEmpty)
      return SubjectResult(
          studentId: studentId,
          subjectId: subjectId,
          homeworkAverage: null,
          compositionGrade: null,
          subjectAverage: null,
          coefficient: subject.coefficient.toDouble(),
          isCalculable: false);

    return calculateSubjectResultFromLists(
        grades, evals, subject, studentModel, classId, periodId, yearId);
  }

  StudentResult calculateGeneralAverageOfficial(
      String studentId, String classId, String? periodId) {
    final student = store.getStudents().firstWhere((s) => s.id == studentId,
        orElse: () =>
            StudentModel(id: '', firstName: '', lastName: '', schoolId: ''));
    if (student.id.isEmpty)
      return StudentResult(
          studentId: studentId,
          generalAverage: null,
          totalCoefficients: 0,
          isCalculable: false);
    final yearId = student.academicYearId ??
        store.getClassById(classId)?.academicYearId ??
        store.getSelectedAcademicYearId() ??
        '';
    final subjects = store
        .getSubjectsByYear(yearId)
        .where((subject) => subject.schoolId == student.schoolId)
        .toList();
    final subjectResults = <SubjectResult>[];

    for (final subj in subjects) {
      final evals = store
          .getEvaluations()
          .where((e) =>
              (yearId.isEmpty ||
                  e.academicYearId.isEmpty ||
                  e.academicYearId == yearId) &&
              e.classId == classId &&
              e.subjectId == subj.id &&
              (periodId == null || e.periodId == periodId) &&
              (e.status == 'validated' || e.status == 'locked'))
          .toList();
      final grades = store
          .getGrades()
          .where((g) =>
              yearId.isEmpty ||
              g.academicYearId == null ||
              g.academicYearId!.isEmpty ||
              g.academicYearId == yearId)
          .toList();
      final sr = calculateSubjectResultFromLists(
          grades, evals, subj, student, classId, periodId, yearId);
      subjectResults.add(sr);
    }

    return calculateGeneralAverageFromSubjectResults(subjectResults);
  }

  // ---- Homework summary helper ----
  // Represents homework (devoir) breakdown for a student in a class/subject/period/year
  // gradesOrdered contains values for each devoir evaluation in ascending number order; null = not entered, NaN not used

  static HomeworkSummary getHomeworkSummaryFromGrades(
    List<GradeModel> grades,
    List<EvaluationModel> evaluations,
    String studentId,
    String classId,
    String subjectId,
    String? periodId,
    String academicYearId,
  ) {
    final devoirs = evaluations
        .where((e) =>
            e.type == 'devoir' &&
            e.classId == classId &&
            e.subjectId == subjectId &&
            e.academicYearId == academicYearId &&
            (periodId == null || e.periodId == periodId))
        .toList()
      ..sort((a, b) => (a.number ?? 0).compareTo(b.number ?? 0));

    final gradesList = <double?>[];
    int missing = 0;
    int absent = 0;
    int present = 0;
    for (final d in devoirs) {
      final g = grades.firstWhere(
          (gr) => gr.studentId == studentId && gr.evaluationId == d.id,
          orElse: () => GradeModel(
              id: '', studentId: '', subjectId: '', eval: '', grade: null));
      if (g.id.isEmpty) {
        gradesList.add(null);
        missing++;
      } else if (g.presence == 'absent') {
        gradesList.add(null);
        absent++;
      } else if (g.grade == null) {
        gradesList.add(null);
        missing++;
      } else {
        gradesList.add(_round(g.grade!));
        present++;
      }
    }

    double? avg;
    final considered =
        gradesList.where((v) => v != null).cast<double>().toList();
    if (considered.isNotEmpty) {
      avg = _round(
          considered.fold<double>(0, (a, b) => a + b) / considered.length);
    }

    return HomeworkSummary(
      gradesOrdered: gradesList,
      totalDevoirs: devoirs.length,
      missingCount: missing,
      absentCount: absent,
      presentCount: present,
      average: avg,
    );
  }

  /// Compute class ranking for a single period (or null for overall trimester)
  /// Returns a map {'ranking': List<RankingEntry>, 'classifiedCount': int}
  Map<String, dynamic> computeClassRanking(String classId, String? periodId) {
    final yearId = store.getClassById(classId)?.academicYearId ??
        store.getSelectedAcademicYearId();
    final students = store
        .getStudents()
        .where((s) =>
            s.classId == classId &&
            (yearId == null ||
                yearId.isEmpty ||
                s.academicYearId == null ||
                s.academicYearId!.isEmpty ||
                s.academicYearId == yearId))
        .toList();
    final entries = <RankingEntry>[];
    for (final s in students) {
      final gen = calculateGeneralAverageOfficial(s.id, classId, periodId)
          .generalAverage;
      if (gen != null) {
        entries.add(RankingEntry(
            studentId: s.id, average: gen, rank: null, isClassified: true));
      } else {
        entries.add(RankingEntry(
            studentId: s.id, average: null, rank: null, isClassified: false));
      }
    }

    final ranked = computeRankingFromAverages(entries);
    final classifiedCount = entries.where((e) => e.isClassified).length;
    return {'ranking': ranked, 'classifiedCount': classifiedCount};
  }

  /// Generate a trimestrial bulletin data structure for a student in a class and period.
  /// Returns a Map with header info and subject rows.
  Map<String, dynamic> generateTrimesterBulletin(
      String classId, String studentId, String? periodId) {
    final student = store.getStudents().firstWhere((s) => s.id == studentId,
        orElse: () =>
            StudentModel(id: '', firstName: '', lastName: '', schoolId: ''));
    final yearId = student.academicYearId ??
        store.getClassById(classId)?.academicYearId ??
        store.getSelectedAcademicYearId() ??
        '';
    final school = store.getEstablishmentById(student.schoolId);
    final cls = store.getClassById(classId);

    // class ranking
    final rankingMap = computeClassRanking(classId, periodId);
    final ranking = rankingMap['ranking'] as List<RankingEntry>;
    final classifiedCount = rankingMap['classifiedCount'] as int;
    final entry = ranking.firstWhere((r) => r.studentId == studentId,
        orElse: () => RankingEntry(
            studentId: studentId,
            average: null,
            rank: null,
            isClassified: false));

    // subjects relevant to this school/year
    final subjects = store
        .getSubjectsByYear(yearId)
        .where((subject) => subject.schoolId == student.schoolId)
        .toList();

    // For official trimester bulletin we consider only validated/locked evaluations
    final evals = store
        .getEvaluations()
        .where((e) =>
            e.academicYearId == yearId &&
            e.classId == classId &&
            (periodId == null || e.periodId == periodId) &&
            (e.status == 'validated' || e.status == 'locked'))
        .toList();
    final grades =
        store.getGrades().where((g) => g.academicYearId == yearId).toList();

    final subjectRows = <Map<String, dynamic>>[];
    for (final subj in subjects) {
      // Use HomeworkSummary to build ordered devoir list and counts
      final hwSummary = getHomeworkSummaryFromGrades(
          grades, evals, studentId, classId, subj.id, periodId, yearId);
      final devoirGrades = hwSummary.gradesOrdered;

      final mc = hwSummary.average; // MC calculated from present devoirs
      final compGrade = getCompositionGradeFromGrades(
          grades, evals, studentId, classId, subj.id, periodId, yearId);
      final subjResult = calculateSubjectResultFromLists(
          grades, evals, subj, student, classId, periodId, yearId);

      subjectRows.add({
        'subjectId': subj.id,
        'subjectName': subj.name,
        'devoirs': devoirGrades,
        'mc': mc,
        'composition': compGrade,
        'coefficient': subj.coefficient,
        'subjectAverage': subjResult.subjectAverage,
        'isCalculable': subjResult.isCalculable,
        'devoirsMissingCount': hwSummary.missingCount,
        'devoirsAbsentCount': hwSummary.absentCount,
        'devoirsPresentCount': hwSummary.presentCount,
      });
    }

    // Use the official general average (validated/locked evaluations only)
    final genAvg =
        calculateGeneralAverageOfficial(studentId, classId, periodId);

    return {
      'school': school?.toJson(),
      'academicYearId': yearId,
      'periodId': periodId,
      'cycle': cls?.cycle ?? cls?.institutionType,
      'level': cls?.level ?? cls?.grade,
      'series': cls?.series,
      'student': student.toJson(),
      'class': cls?.toJson(),
      'ranking': {'rank': entry.rank, 'effectif': classifiedCount},
      'generalAverage': genAvg.generalAverage,
      'subjects': subjectRows,
    };
  }

  /// Generate an annual bulletin for a student by aggregating the three trimester periods.
  /// Uses only evaluations that are validated or locked (official results).
  Map<String, dynamic> generateAnnualBulletin(String classId, String studentId,
      {List<String>? periodIds}) {
    final student = store.getStudents().firstWhere((s) => s.id == studentId,
        orElse: () =>
            StudentModel(id: '', firstName: '', lastName: '', schoolId: ''));
    final yearId = student.academicYearId ??
        store.getClassById(classId)?.academicYearId ??
        store.getSelectedAcademicYearId() ??
        '';
    final school = store.getEstablishmentById(student.schoolId);

    final periods = periodIds ?? ['T1', 'T2', 'T3'];

    // subjects relevant to this school/year
    final subjects = store
        .getSubjectsByYear(yearId)
        .where((subject) => subject.schoolId == student.schoolId)
        .toList();

    // consider only official evaluations
    final allEvals = store
        .getEvaluations()
        .where((e) =>
            e.academicYearId == yearId &&
            (e.status == 'validated' || e.status == 'locked'))
        .toList();
    final allGrades =
        store.getGrades().where((g) => g.academicYearId == yearId).toList();

    final subjectRows = <Map<String, dynamic>>[];

    for (final subj in subjects) {
      final perPeriod = <String, SubjectResult>{};
      bool allCalculable = true;
      for (final p in periods) {
        final sr = _calculateSubjectResultForPeriod(
            allGrades, allEvals, subj, student, p, yearId);
        perPeriod[p] = sr;
        if (!sr.isCalculable || sr.subjectAverage == null)
          allCalculable = false;
      }

      double? annualSubjectAverage;
      if (allCalculable) {
        final sums = periods
            .map((p) => perPeriod[p]!.subjectAverage ?? 0.0)
            .fold<double>(0.0, (a, b) => a + b);
        annualSubjectAverage = _round(sums / periods.length);
      } else {
        annualSubjectAverage = null; // Non calculable
      }

      subjectRows.add({
        'subjectId': subj.id,
        'subjectName': subj.name,
        'periodAverages':
            periods.map((p) => perPeriod[p]!.subjectAverage).toList(),
        'moyenneAnnuel': annualSubjectAverage,
        'coefficient': subj.coefficient,
        'appreciation': null, // To be provided by centralized configuration
        'isCalculable': allCalculable,
      });
    }

    // compute general annual average
    final annualSubjectResults = subjectRows
        .where((r) => r['moyenneAnnuel'] != null)
        .map((r) => SubjectResult(
              studentId: studentId,
              subjectId: r['subjectId'] as String,
              homeworkAverage: null,
              compositionGrade: null,
              subjectAverage: r['moyenneAnnuel'] as double?,
              coefficient: (r['coefficient'] as num).toDouble(),
              isCalculable: r['moyenneAnnuel'] != null,
            ))
        .toList();

    final gen = calculateGeneralAverageFromSubjectResults(annualSubjectResults);

    // ranking within the class for the year
    final rankingMap = computeAnnualClassRanking(classId, periods);
    final ranking = rankingMap['ranking'] as List<RankingEntry>;
    final classifiedCount = rankingMap['classifiedCount'] as int;
    final entry = ranking.firstWhere((r) => r.studentId == studentId,
        orElse: () => RankingEntry(
            studentId: studentId,
            average: null,
            rank: null,
            isClassified: false));

    return {
      'school': school?.toJson(),
      'academicYearId': yearId,
      'student': student.toJson(),
      'classId': classId,
      'ranking': {'rank': entry.rank, 'effectif': classifiedCount},
      'generalAverage': gen.generalAverage,
      'subjects': subjectRows,
    };
  }

  /// Compute annual class ranking based on annual averages computed over periodIds.
  /// Returns the same structure as computeClassRanking
  Map<String, dynamic> computeAnnualClassRanking(
      String classId, List<String> periodIds) {
    final yearId = store.getClassById(classId)?.academicYearId ??
        store.getSelectedAcademicYearId();
    final students = store
        .getStudents()
        .where((s) => s.classId == classId && s.academicYearId == yearId)
        .toList();
    final entries = <RankingEntry>[];
    for (final s in students) {
      final gen = _calculateAnnualGeneralAverage(s.id, classId, periodIds);
      if (gen != null) {
        entries.add(RankingEntry(
            studentId: s.id, average: gen, rank: null, isClassified: true));
      } else {
        entries.add(RankingEntry(
            studentId: s.id, average: null, rank: null, isClassified: false));
      }
    }

    final ranked = computeRankingFromAverages(entries);
    final classifiedCount = entries.where((e) => e.isClassified).length;
    return {'ranking': ranked, 'classifiedCount': classifiedCount};
  }

  /// Helper: compute a subject result for a specific period using only provided grades/evaluations
  SubjectResult _calculateSubjectResultForPeriod(
      List<GradeModel> grades,
      List<EvaluationModel> evaluations,
      SubjectModel subject,
      StudentModel student,
      String? periodId,
      String academicYearId) {
    // consider evaluations matching subject, period and official status
    final evals = evaluations
        .where((e) =>
            e.subjectId == subject.id &&
            (periodId == null || e.periodId == periodId) &&
            (e.status == 'validated' || e.status == 'locked'))
        .toList();

    // homework average
    final devoirIds =
        evals.where((e) => e.type == 'devoir').map((e) => e.id).toSet();
    final studentGrades = grades
        .where((g) =>
            g.studentId == student.id &&
            g.evaluationId != null &&
            devoirIds.contains(g.evaluationId))
        .toList();
    final considered = studentGrades
        .where((g) => g.grade != null)
        .map((g) => g.grade!)
        .toList();
    double? homeworkAvg;
    if (considered.isNotEmpty) {
      final sum = considered.fold<double>(0, (a, b) => a + b);
      homeworkAvg = _round(sum / considered.length);
    }

    // composition
    final compEval = evals.firstWhere(
      (evaluation) =>
          evaluation.type == 'composition' &&
          grades.any((grade) =>
              grade.studentId == student.id &&
              grade.evaluationId == evaluation.id),
      orElse: () => EvaluationModel(
          id: '',
          title: '',
          type: '',
          number: 0,
          academicYearId: academicYearId,
          classId: '',
          subjectId: '',
          createdBy: '',
          createdAt: DateTime.now().toIso8601String(),
          schoolId: ''),
    );
    double? compGrade;
    if (compEval.id.isNotEmpty) {
      final g = grades.firstWhere(
          (gr) => gr.studentId == student.id && gr.evaluationId == compEval.id,
          orElse: () => GradeModel(
              id: '', studentId: '', subjectId: '', eval: '', grade: null));
      if (g.id.isNotEmpty && g.grade != null) compGrade = _round(g.grade!);
    }

    double? subjAvg;
    bool calculable = false;
    if (homeworkAvg != null && compGrade != null) {
      subjAvg = calculateSubjectAverageStandalone(
          homeworkAvg, compGrade, null, periodId);
      calculable = subjAvg != null;
    }

    return SubjectResult(
      studentId: student.id,
      subjectId: subject.id,
      homeworkAverage: homeworkAvg,
      compositionGrade: compGrade,
      subjectAverage: subjAvg,
      coefficient: subject.coefficient.toDouble(),
      isCalculable: calculable,
    );
  }

  /// Helper: compute annual general average for a student, returns null if non-calculable
  double? _calculateAnnualGeneralAverage(
      String studentId, String classId, List<String> periodIds) {
    final student = store.getStudents().firstWhere(
          (item) => item.id == studentId,
          orElse: () =>
              StudentModel(id: '', firstName: '', lastName: '', schoolId: ''),
        );
    final yearId = student.academicYearId ??
        store.getClassById(classId)?.academicYearId ??
        store.getSelectedAcademicYearId() ??
        '';
    final subjects = store
        .getSubjectsByYear(yearId)
        .where((subject) => subject.schoolId == student.schoolId)
        .toList();

    final allEvals = store
        .getEvaluations()
        .where((e) =>
            e.academicYearId == yearId &&
            (e.status == 'validated' || e.status == 'locked'))
        .toList();
    final allGrades =
        store.getGrades().where((g) => g.academicYearId == yearId).toList();

    final annualSubjectResults = <SubjectResult>[];
    for (final subj in subjects) {
      bool allOK = true;
      final per = <double>[];
      for (final p in periodIds) {
        final sr = _calculateSubjectResultForPeriod(
            allGrades, allEvals, subj, student, p, yearId);
        if (!sr.isCalculable || sr.subjectAverage == null) {
          allOK = false;
          break;
        }
        per.add(sr.subjectAverage!);
      }
      if (allOK) {
        final avg = _round(per.fold<double>(0, (a, b) => a + b) / per.length);
        annualSubjectResults.add(SubjectResult(
            studentId: studentId,
            subjectId: subj.id,
            homeworkAverage: null,
            compositionGrade: null,
            subjectAverage: avg,
            coefficient: subj.coefficient.toDouble(),
            isCalculable: true));
      }
    }

    if (annualSubjectResults.isEmpty) return null;
    final gen = calculateGeneralAverageFromSubjectResults(annualSubjectResults);
    return gen.isCalculable ? gen.generalAverage : null;
  }

  /// Pure helper: compute ranking from a list of (studentId, average) pairs.
  /// averages may be null (non-classified). Returns list ordered with classified first.
  static List<RankingEntry> computeRankingFromAverages(
      List<RankingEntry> inputs) {
    final classified = inputs.where((e) => e.average != null).toList()
      ..sort((a, b) => (b.average ?? 0).compareTo(a.average ?? 0));
    final result = <RankingEntry>[];
    int currentRank = 1;
    int i = 0;
    while (i < classified.length) {
      final groupAvg = classified[i].average;
      final sameGroup = classified.where((c) => c.average == groupAvg).toList();
      final groupSize = sameGroup.length;
      for (final m in sameGroup) {
        result.add(RankingEntry(
            studentId: m.studentId,
            average: m.average,
            rank: currentRank,
            isClassified: true));
      }
      currentRank += groupSize;
      i += groupSize;
    }
    final nonClassified = inputs.where((e) => e.average == null).toList();
    for (final nc in nonClassified) {
      result.add(RankingEntry(
          studentId: nc.studentId,
          average: null,
          rank: null,
          isClassified: false));
    }
    return result;
  }

  static double _round(double v) => double.parse(v.toStringAsFixed(2));
}
