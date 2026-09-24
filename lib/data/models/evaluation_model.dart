/// Modèle Evaluation (Devoir / Composition)
class EvaluationModel {
  final String id;
  final String title; // 'Devoir 1', 'Composition'
  final String type; // devoir | composition | test | exam | exam_blanc
  final String? examCode;
  final String? programId;
  final int? number; // for devoirs (1,2,3...)
  final String academicYearId;
  final String? periodId; // canonical academic period (trimester/month/custom)
  final String classId;
  final String subjectId;
  final String? date;
  final String
      status; // 'draft' | 'submitted' | 'rejected' | 'validated' | 'locked'
  final double maxScore; // Barème de notation (par défaut 20.0)
  final String createdBy;
  final String createdAt;
  final String? submittedAt;
  final String? validatedAt;
  final String? validatedBy;
  final String? rejectedAt;
  final String? rejectedBy;
  final String? rejectionReason;
  final String schoolId;

  EvaluationModel({
    required this.id,
    required this.title,
    required this.type,
    this.examCode,
    this.programId,
    this.number,
    required this.academicYearId,
    this.periodId,
    required this.classId,
    required this.subjectId,
    this.date,
    this.status = 'draft',
    this.maxScore = 20.0,
    required this.createdBy,
    required this.createdAt,
    this.submittedAt,
    this.validatedAt,
    this.validatedBy,
    this.rejectedAt,
    this.rejectedBy,
    this.rejectionReason,
    required this.schoolId,
  });

  bool get isOpen => status == 'draft';
  bool get isClosed => status == 'submitted';
  bool get isRejected => status == 'rejected';
  bool get isValidated => status == 'validated';
  bool get isLocked => status == 'locked';

  factory EvaluationModel.fromJson(Map<String, dynamic> json) {
    return EvaluationModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      type: json['type'] ?? 'devoir',
      examCode: json['examCode'],
      programId: json['programId'],
      number: json['number'],
      academicYearId: json['academicYearId'] ?? '',
      periodId: json['periodId'],
      classId: json['classId'] ?? '',
      subjectId: json['subjectId'] ?? '',
      date: json['date'],
      status: json['status'] ?? 'draft',
      maxScore: (json['maxScore'] as num?)?.toDouble() ?? 20.0,
      createdBy: json['createdBy'] ?? '',
      createdAt: json['createdAt'] ?? '',
      submittedAt: json['submittedAt'],
      validatedAt: json['validatedAt'],
      validatedBy: json['validatedBy'],
      rejectedAt: json['rejectedAt'],
      rejectedBy: json['rejectedBy'],
      rejectionReason: json['rejectionReason'],
      schoolId: json['schoolId'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type,
        'examCode': examCode,
        'programId': programId,
        'number': number,
        'academicYearId': academicYearId,
        'periodId': periodId,
        'classId': classId,
        'subjectId': subjectId,
        'date': date,
        'status': status,
        'maxScore': maxScore,
        'createdBy': createdBy,
        'createdAt': createdAt,
        'submittedAt': submittedAt,
        'validatedAt': validatedAt,
        'validatedBy': validatedBy,
        'rejectedAt': rejectedAt,
        'rejectedBy': rejectedBy,
        'rejectionReason': rejectionReason,
        'schoolId': schoolId,
      };

  EvaluationModel copyWith({
    String? id,
    String? title,
    String? type,
    String? examCode,
    String? programId,
    int? number,
    String? academicYearId,
    String? periodId,
    String? classId,
    String? subjectId,
    String? date,
    String? status,
    double? maxScore,
    String? createdBy,
    String? createdAt,
    String? submittedAt,
    String? validatedAt,
    String? validatedBy,
    String? rejectedAt,
    String? rejectedBy,
    String? rejectionReason,
    String? schoolId,
  }) {
    return EvaluationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      examCode: examCode ?? this.examCode,
      programId: programId ?? this.programId,
      number: number ?? this.number,
      academicYearId: academicYearId ?? this.academicYearId,
      periodId: periodId ?? this.periodId,
      classId: classId ?? this.classId,
      subjectId: subjectId ?? this.subjectId,
      date: date ?? this.date,
      status: status ?? this.status,
      maxScore: maxScore ?? this.maxScore,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      submittedAt: submittedAt ?? this.submittedAt,
      validatedAt: validatedAt ?? this.validatedAt,
      validatedBy: validatedBy ?? this.validatedBy,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      rejectedBy: rejectedBy ?? this.rejectedBy,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      schoolId: schoolId ?? this.schoolId,
    );
  }
}
