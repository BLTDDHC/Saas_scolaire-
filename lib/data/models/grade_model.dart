/// Modèle Note
class GradeModel {
  final String id;
  final String studentId;
  final String subjectId;
  final String? subsubjectId;
  final String eval; // 'Devoir 1', 'Examen', 'Rattrapage', etc.
  final double? grade; // nullable: null = non renseigné
  final double coef;
  // Link to the canonical evaluation entity (Devoir N / Composition)
  final String? evaluationId;
  // presence: 'present' | 'absent' | 'not_recorded'
  final String? presence;
  // user who entered the grade
  final String? enteredBy;
  final String? date;
  final String? comment;
  final String? academicYearId;
  final String? semesterId;

  GradeModel({
    required this.id,
    required this.studentId,
    required this.subjectId,
    this.subsubjectId,
    required this.eval,
    this.grade,
    this.coef = 1,
    this.evaluationId,
    this.presence,
    this.enteredBy,
    this.date,
    this.comment,
    this.academicYearId,
    this.semesterId,
  });

  factory GradeModel.fromJson(Map<String, dynamic> json) {
    return GradeModel(
      id: json['id'] ?? '',
      studentId: json['studentId'] ?? '',
      subjectId: json['subjectId'] ?? '',
      subsubjectId: json['subsubjectId'],
      eval: json['eval'] ?? '',
      grade: json.containsKey('grade') && json['grade'] != null ? (json['grade'] as num).toDouble() : null,
      coef: (json['coef'] ?? 1).toDouble(),
      evaluationId: json['evaluationId'],
      presence: json['presence'],
      enteredBy: json['enteredBy'],
      date: json['date'],
      comment: json['comment'],
      academicYearId: json['academicYearId'],
      semesterId: json['semesterId'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'studentId': studentId, 'subjectId': subjectId,
    'subsubjectId': subsubjectId, 'eval': eval, 'grade': grade,
    'coef': coef, 'evaluationId': evaluationId, 'presence': presence, 'enteredBy': enteredBy, 'date': date, 'comment': comment,
    'academicYearId': academicYearId, 'semesterId': semesterId,
  };
}
