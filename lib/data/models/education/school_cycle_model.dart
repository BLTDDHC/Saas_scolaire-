class SchoolCycleModel {
  final String id;
  final String schoolId;
  final String code;
  final String name;
  final String status;
  final int sortOrder;

  const SchoolCycleModel({
    required this.id,
    required this.schoolId,
    required this.code,
    required this.name,
    this.status = 'active',
    this.sortOrder = 0,
  });

  bool get isActive => status == 'active';

  factory SchoolCycleModel.fromJson(Map<String, dynamic> json) =>
      SchoolCycleModel(
        id: json['id']?.toString() ?? '',
        schoolId: json['schoolId']?.toString() ?? '',
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        status: json['status']?.toString() ?? 'active',
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'schoolId': schoolId,
        'code': code,
        'name': name,
        'status': status,
        'sortOrder': sortOrder,
      };
}
