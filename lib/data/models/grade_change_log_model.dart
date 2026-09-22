class GradeChangeLogModel {
  final String id;
  final String gradeId;
  final String evaluationId;
  final String studentId;
  final double? oldValue;
  final double? newValue;
  final String changedBy; // user id
  final String changedAt; // ISO date
  final String? note; // optional note or reason

  GradeChangeLogModel({
    required this.id,
    required this.gradeId,
    required this.evaluationId,
    required this.studentId,
    this.oldValue,
    this.newValue,
    required this.changedBy,
    required this.changedAt,
    this.note,
  });

  factory GradeChangeLogModel.fromJson(Map<String, dynamic> json) {
    return GradeChangeLogModel(
      id: json['id'] ?? '',
      gradeId: json['gradeId'] ?? '',
      evaluationId: json['evaluationId'] ?? '',
      studentId: json['studentId'] ?? '',
      oldValue: json['oldValue'] != null ? (json['oldValue'] as num).toDouble() : null,
      newValue: json['newValue'] != null ? (json['newValue'] as num).toDouble() : null,
      changedBy: json['changedBy'] ?? '',
      changedAt: json['changedAt'] ?? '',
      note: json['note'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'gradeId': gradeId,
    'evaluationId': evaluationId,
    'studentId': studentId,
    'oldValue': oldValue,
    'newValue': newValue,
    'changedBy': changedBy,
    'changedAt': changedAt,
    'note': note,
  };
}
