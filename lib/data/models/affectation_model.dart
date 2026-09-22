/// Modèle Affectation — liaison Enseignant → Matière → Classe
class AffectationModel {
  final String id;
  final String teacherId;
  final String? teacherName;
  final String? subjectId;
  final String? subject;
  final String? classId;
  final String? className;
  final String schoolId;
  final String? institutionId;
  final String? academicYearId;
  final String type; // 'teaching', 'main_teacher'

  AffectationModel({
    required this.id,
    required this.teacherId,
    this.teacherName,
    this.subjectId,
    this.subject,
    this.classId,
    this.className,
    required this.schoolId,
    this.institutionId,
    this.academicYearId,
    this.type = 'teaching',
  });

  factory AffectationModel.fromJson(Map<String, dynamic> json) {
    return AffectationModel(
      id: json['id'] ?? '',
      teacherId: json['teacherId'] ?? '',
      teacherName: json['teacherName'],
      subjectId: json['subjectId'],
      subject: json['subject'],
      classId: json['classId'],
      className: json['className'],
      schoolId: json['schoolId'] ?? '',
      institutionId: json['institutionId'],
      academicYearId: json['academicYearId'] ?? json['schoolYearId'],
      type: json['type'] ?? 'teaching',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'teacherId': teacherId, 'teacherName': teacherName,
    'subjectId': subjectId, 'subject': subject, 'classId': classId,
    'className': className, 'schoolId': schoolId, 'institutionId': institutionId,
    'academicYearId': academicYearId, 'schoolYearId': academicYearId,
    'type': type,
  };
}
