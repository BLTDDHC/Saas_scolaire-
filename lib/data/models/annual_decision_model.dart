class DecisionChangeLogModel {
  final String id;
  final String decisionId;
  final String oldDecision;
  final String newDecision;
  final String changedBy;
  final String changedAt;
  final String? reason;

  DecisionChangeLogModel({
    required this.id,
    required this.decisionId,
    required this.oldDecision,
    required this.newDecision,
    required this.changedBy,
    required this.changedAt,
    this.reason,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'decisionId': decisionId,
        'oldDecision': oldDecision,
        'newDecision': newDecision,
        'changedBy': changedBy,
        'changedAt': changedAt,
        'reason': reason,
      };

  factory DecisionChangeLogModel.fromJson(Map<String, dynamic> j) => DecisionChangeLogModel(
        id: j['id'] ?? '',
        decisionId: j['decisionId'] ?? '',
        oldDecision: j['oldDecision'] ?? '',
        newDecision: j['newDecision'] ?? '',
        changedBy: j['changedBy'] ?? '',
        changedAt: j['changedAt'] ?? '',
        reason: j['reason'],
      );
}

class ReEnrollmentRequestModel {
  final String id;
  final String decisionId;
  final String studentId;
  final String fromAcademicYearId;
  final String toAcademicYearId;
  final String? fromClassId;
  final String? toClassId;
  final String createdAt;
  final String createdBy;

  ReEnrollmentRequestModel({
    required this.id,
    required this.decisionId,
    required this.studentId,
    required this.fromAcademicYearId,
    required this.toAcademicYearId,
    this.fromClassId,
    this.toClassId,
    required this.createdAt,
    required this.createdBy,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'decisionId': decisionId,
        'studentId': studentId,
        'fromAcademicYearId': fromAcademicYearId,
        'toAcademicYearId': toAcademicYearId,
        'fromClassId': fromClassId,
        'toClassId': toClassId,
        'createdAt': createdAt,
        'createdBy': createdBy,
      };

  factory ReEnrollmentRequestModel.fromJson(Map<String, dynamic> j) => ReEnrollmentRequestModel(
        id: j['id'] ?? '',
        decisionId: j['decisionId'] ?? '',
        studentId: j['studentId'] ?? '',
        fromAcademicYearId: j['fromAcademicYearId'] ?? '',
        toAcademicYearId: j['toAcademicYearId'] ?? '',
        fromClassId: j['fromClassId'],
        toClassId: j['toClassId'],
        createdAt: j['createdAt'] ?? '',
        createdBy: j['createdBy'] ?? '',
      );
}

class AnnualDecisionModel {
  final String id;
  final String establishmentId;
  final String academicYearId;
  final String studentId;
  final String currentClassId;
  String? nextClassId;
  final double? annualAverage;
  final int? rank;
  String decision; // ADMIS, REDOUBLE, EXCLU, ABANDON, DEPART, A_DECIDER
  String status; // draft, validated, locked
  String? reason;
  final String createdAt;
  String? decidedBy;
  String? decidedAt;
  String? updatedAt;

  AnnualDecisionModel({
    required this.id,
    required this.establishmentId,
    required this.academicYearId,
    required this.studentId,
    required this.currentClassId,
    this.nextClassId,
    this.annualAverage,
    this.rank,
    this.decision = 'A_DECIDER',
    this.status = 'draft',
    this.reason,
    required this.createdAt,
    this.decidedBy,
    this.decidedAt,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'establishmentId': establishmentId,
        'academicYearId': academicYearId,
        'studentId': studentId,
        'currentClassId': currentClassId,
        'nextClassId': nextClassId,
        'annualAverage': annualAverage,
        'rank': rank,
        'decision': decision,
        'status': status,
        'reason': reason,
        'createdAt': createdAt,
        'decidedBy': decidedBy,
        'decidedAt': decidedAt,
        'updatedAt': updatedAt,
      };

  factory AnnualDecisionModel.fromJson(Map<String, dynamic> j) => AnnualDecisionModel(
        id: j['id'] ?? '',
        establishmentId: j['establishmentId'] ?? '',
        academicYearId: j['academicYearId'] ?? '',
        studentId: j['studentId'] ?? '',
        currentClassId: j['currentClassId'] ?? '',
        nextClassId: j['nextClassId'],
        annualAverage: j['annualAverage'] != null ? (j['annualAverage'] as num).toDouble() : null,
        rank: j['rank'] != null ? (j['rank'] as int) : null,
        decision: j['decision'] ?? 'A_DECIDER',
        status: j['status'] ?? 'draft',
        reason: j['reason'],
        createdAt: j['createdAt'] ?? '',
        decidedBy: j['decidedBy'],
        decidedAt: j['decidedAt'],
        updatedAt: j['updatedAt'],
      );
}
