/// Modèle Matière
class SubjectModel {
  final String id;
  final String name;
  final int coefficient;
  String? teacher;
  final List<String> classes;
  final String? color;
  final String? icon;
  final String schoolId;
  final String? institutionId;
  final String? academicYearId;
  final String? institutionType;
  final String status;
  final List<Map<String, dynamic>> levelSettings;
  final double? eliminationGrade; // Note éliminatoire (université)

  SubjectModel({
    required this.id,
    required this.name,
    this.coefficient = 1,
    this.teacher,
    this.classes = const [],
    this.color,
    this.icon,
    required this.schoolId,
    this.institutionId,
    this.academicYearId,
    this.institutionType,
    this.status = 'active',
    this.levelSettings = const [],
    this.eliminationGrade = 8.0,
  });

  factory SubjectModel.fromJson(Map<String, dynamic> json) {
    return SubjectModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      coefficient: json['coefficient'] ?? 1,
      teacher: json['teacher'],
      classes:
          json['classes'] != null ? List<String>.from(json['classes']) : [],
      color: json['color'],
      icon: json['icon'],
      schoolId: json['schoolId'] ?? json['institutionId'] ?? '',
      institutionId: json['institutionId'],
      academicYearId: json['academicYearId'] ?? json['schoolYearId'],
      institutionType: json['institutionType'],
      status: json['status']?.toString() ?? 'active',
      levelSettings: (json['levelSettings'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
      eliminationGrade: (json['eliminationGrade'] ?? 8).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'coefficient': coefficient,
        'teacher': teacher,
        'classes': classes,
        'color': color,
        'icon': icon,
        'schoolId': schoolId,
        'institutionId': institutionId,
        'academicYearId': academicYearId,
        'schoolYearId': academicYearId,
        'institutionType': institutionType,
        'status': status,
        'levelSettings': levelSettings,
        'eliminationGrade': eliminationGrade,
      };

  SubjectModel copyWith(
      {String? name,
      int? coefficient,
      String? teacher,
      List<String>? classes,
      String? color,
      String? icon,
      String? status,
      double? eliminationGrade,
      List<Map<String, dynamic>>? levelSettings}) {
    return SubjectModel(
      id: id,
      name: name ?? this.name,
      coefficient: coefficient ?? this.coefficient,
      teacher: teacher ?? this.teacher,
      classes: classes ?? this.classes,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      schoolId: schoolId,
      institutionId: institutionId,
      academicYearId: academicYearId,
      institutionType: institutionType,
      status: status ?? this.status,
      eliminationGrade: eliminationGrade ?? this.eliminationGrade,
      levelSettings: levelSettings ?? this.levelSettings,
    );
  }
}
