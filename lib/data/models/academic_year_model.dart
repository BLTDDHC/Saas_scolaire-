/// Modèle Année Scolaire/Académique
class AcademicYearModel {
  final String id;
  final String name;
  final String start;
  final String end;
  final String? establishment;
  final String schoolId;
  final String? institutionId;
  final String? institutionType;
  String status;
  bool isActive;

  AcademicYearModel({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    this.establishment,
    required this.schoolId,
    this.institutionId,
    this.institutionType,
    this.status = 'active',
    this.isActive = true,
  });

  factory AcademicYearModel.fromJson(Map<String, dynamic> json) {
    return AcademicYearModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      start: json['start'] ?? '',
      end: json['end'] ?? '',
      establishment: json['establishment'],
      schoolId: json['schoolId'] ?? json['institutionId'] ?? '',
      institutionId: json['institutionId'],
      institutionType: json['institutionType'],
      status: json['status'] ?? 'active',
      isActive: json['isActive'] ?? (json['status'] == 'active'),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'start': start, 'end': end,
    'establishment': establishment, 'schoolId': schoolId,
    'institutionId': institutionId, 'institutionType': institutionType,
    'status': status, 'isActive': isActive,
  };

  AcademicYearModel copyWith({String? name, String? start, String? end, String? status, bool? isActive}) {
    return AcademicYearModel(
      id: id, name: name ?? this.name, start: start ?? this.start,
      end: end ?? this.end, establishment: establishment, schoolId: schoolId,
      institutionId: institutionId, institutionType: institutionType,
      status: status ?? this.status, isActive: isActive ?? this.isActive,
    );
  }
}
