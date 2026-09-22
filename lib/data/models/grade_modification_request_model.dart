class GradeModificationRequestModel {
  final String id;
  final String gradeId;
  final String evaluationId;
  final String studentId;
  final String requestedBy; // user id
  final String requestedAt; // ISO date
  final double? oldValue;
  final double? newValue;
  final String reason;
  String status; // 'pending' | 'approved' | 'rejected' | 'completed'
  String? handledBy;
  String? handledAt;
  String? handledReason;

  GradeModificationRequestModel({
    required this.id,
    required this.gradeId,
    required this.evaluationId,
    required this.studentId,
    required this.requestedBy,
    required this.requestedAt,
    this.oldValue,
    this.newValue,
    required this.reason,
    this.status = 'pending',
    this.handledBy,
    this.handledAt,
    this.handledReason,
  });

  factory GradeModificationRequestModel.fromJson(Map<String, dynamic> json) {
    return GradeModificationRequestModel(
      id: json['id'] ?? '',
      gradeId: json['gradeId'] ?? '',
      evaluationId: json['evaluationId'] ?? '',
      studentId: json['studentId'] ?? '',
      requestedBy: json['requestedBy'] ?? '',
      requestedAt: json['requestedAt'] ?? '',
      oldValue: json['oldValue'] != null ? (json['oldValue'] as num).toDouble() : null,
      newValue: json['newValue'] != null ? (json['newValue'] as num).toDouble() : null,
      reason: json['reason'] ?? '',
      status: json['status'] ?? 'pending',
      handledBy: json['handledBy'],
      handledAt: json['handledAt'],
      handledReason: json['handledReason'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'gradeId': gradeId,
    'evaluationId': evaluationId,
    'studentId': studentId,
    'requestedBy': requestedBy,
    'requestedAt': requestedAt,
    'oldValue': oldValue,
    'newValue': newValue,
    'reason': reason,
    'status': status,
    'handledBy': handledBy,
    'handledAt': handledAt,
    'handledReason': handledReason,
  };
}
