class AnnualSubjectResult {
  final String subjectId;
  final String subjectName;
  final double? t1;
  final double? t2;
  final double? t3;
  final double? annualAverage;
  final double coefficient;
  final bool isCalculable;

  AnnualSubjectResult({
    required this.subjectId,
    required this.subjectName,
    this.t1,
    this.t2,
    this.t3,
    this.annualAverage,
    required this.coefficient,
    required this.isCalculable,
  });

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'subjectName': subjectName,
        't1': t1,
        't2': t2,
        't3': t3,
        'annualAverage': annualAverage,
        'coefficient': coefficient,
        'isCalculable': isCalculable,
      };

  factory AnnualSubjectResult.fromJson(Map<String, dynamic> j) => AnnualSubjectResult(
        subjectId: j['subjectId'] ?? '',
        subjectName: j['subjectName'] ?? '',
        t1: j['t1'] != null ? (j['t1'] as num).toDouble() : null,
        t2: j['t2'] != null ? (j['t2'] as num).toDouble() : null,
        t3: j['t3'] != null ? (j['t3'] as num).toDouble() : null,
        annualAverage: j['annualAverage'] != null ? (j['annualAverage'] as num).toDouble() : null,
        coefficient: (j['coefficient'] ?? 1).toDouble(),
        isCalculable: j['isCalculable'] ?? false,
      );
}

class AnnualBulletinModel {
  final String id;
  final String establishmentId;
  final String academicYearId;
  final String studentId;
  final String classId;
  final List<AnnualSubjectResult> subjectResults;
  final double? generalAverage;
  final int? rank;
  final int classSize;
  String status; // draft, calculated, validated, locked
  String? decision; // adm decision (ADMIS/REDOUBLE etc.)
  final String createdAt;
  String? validatedAt;
  String? validatedBy;

  AnnualBulletinModel({
    required this.id,
    required this.establishmentId,
    required this.academicYearId,
    required this.studentId,
    required this.classId,
    required this.subjectResults,
    this.generalAverage,
    this.rank,
    required this.classSize,
    this.status = 'calculated',
    this.decision,
    required this.createdAt,
    this.validatedAt,
    this.validatedBy,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'establishmentId': establishmentId,
        'academicYearId': academicYearId,
        'studentId': studentId,
        'classId': classId,
        'subjectResults': subjectResults.map((s) => s.toJson()).toList(),
        'generalAverage': generalAverage,
        'rank': rank,
        'classSize': classSize,
        'status': status,
        'decision': decision,
        'createdAt': createdAt,
        'validatedAt': validatedAt,
        'validatedBy': validatedBy,
      };

  factory AnnualBulletinModel.fromJson(Map<String, dynamic> j) => AnnualBulletinModel(
        id: j['id'] ?? '',
        establishmentId: j['establishmentId'] ?? '',
        academicYearId: j['academicYearId'] ?? '',
        studentId: j['studentId'] ?? '',
        classId: j['classId'] ?? '',
        subjectResults: (j['subjectResults'] as List? ?? []).map((e) => AnnualSubjectResult.fromJson(Map<String, dynamic>.from(e))).toList(),
        generalAverage: j['generalAverage'] != null ? (j['generalAverage'] as num).toDouble() : null,
        rank: j['rank'] != null ? (j['rank'] as int) : null,
        classSize: j['classSize'] ?? 0,
        status: j['status'] ?? 'calculated',
        decision: j['decision'],
        createdAt: j['createdAt'] ?? '',
        validatedAt: j['validatedAt'],
        validatedBy: j['validatedBy'],
      );
}
