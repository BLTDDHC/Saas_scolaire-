/// School level model (primary/college/highschool)
class SchoolLevelModel {
  final String id;
  final String name; // e.g. 'CM2', '6e', 'Seconde', 'Première'
  final String cycle; // 'Primaire', 'Collège', 'Lycée'
  final String cycleId;
  final String code;
  final String schoolId;
  final String status;
  final int sortOrder;

  SchoolLevelModel({
    required this.id,
    required this.name,
    required this.cycle,
    this.cycleId = '',
    this.code = '',
    required this.schoolId,
    this.status = 'active',
    this.sortOrder = 0,
  });

  factory SchoolLevelModel.fromJson(Map<String, dynamic> json) {
    return SchoolLevelModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      cycle: json['cycle'] ?? '',
      cycleId: json['cycleId']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      schoolId: json['schoolId'] ?? '',
      status: json['status']?.toString() ?? 'active',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cycle': cycle,
        'cycleId': cycleId,
        'code': code,
        'schoolId': schoolId,
        'status': status,
        'sortOrder': sortOrder,
      };
}
