class BehaviorAssessmentModel {
  final String id;
  final String studentId;
  final String teacherId;
  final String schoolId;
  final String? academicYearId;
  final String? classId;
  final String? periodId;
  final String? period;
  final double score;
  final String date;
  final String? comment;
  final String? studentUserId;
  final String? parentUserId;
  final String? teacherUserId;
  final String status;
  final String? recordedBy;
  String get contextKey => '$schoolId|$academicYearId|$classId|$periodId|$teacherId|$studentId';

  const BehaviorAssessmentModel(
      {required this.id,
      required this.studentId,
      required this.teacherId,
      required this.schoolId,
      this.academicYearId,
      this.classId,
      this.periodId,
      this.period,
      required this.score,
      required this.date,
      this.comment,
      this.studentUserId,
      this.parentUserId,
      this.teacherUserId,
      this.status = 'locked',
      this.recordedBy});
  factory BehaviorAssessmentModel.fromJson(Map<String, dynamic> json) =>
      BehaviorAssessmentModel(
          id: json['id'] ?? '',
          studentId: json['studentId'] ?? '',
          teacherId: json['teacherId'] ?? '',
          schoolId: json['schoolId'] ?? '',
          academicYearId: json['academicYearId'],
          classId: json['classId'],
          periodId: json['periodId'],
          period: json['period'],
          score: (json['score'] as num?)?.toDouble() ?? 0,
          date: json['date'] ?? '',
          comment: json['comment'],
          studentUserId: json['studentUserId'],
          parentUserId: json['parentUserId'],
          teacherUserId: json['teacherUserId'],
          status: json['status'] ?? 'locked',
          recordedBy: json['recordedBy']);
  Map<String, dynamic> toJson() => {
        'id': id,
        'studentId': studentId,
        'teacherId': teacherId,
        'schoolId': schoolId,
        'academicYearId': academicYearId,
        'classId': classId,
        'periodId': periodId,
        'period': period,
        'score': score,
        'date': date,
        'comment': comment,
        'studentUserId': studentUserId,
        'parentUserId': parentUserId,
        'teacherUserId': teacherUserId,
        'status': status,
        'recordedBy': recordedBy
      };
}
