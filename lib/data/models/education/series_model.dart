/// Series model for high school (e.g., A, B, C)
class SeriesModel {
  final String id;
  final String name; // 'A', 'B', 'C'
  final String schoolId;

  SeriesModel({required this.id, required this.name, required this.schoolId});

  factory SeriesModel.fromJson(Map<String, dynamic> json) {
    return SeriesModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      schoolId: json['schoolId'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'schoolId': schoolId,
  };
}
