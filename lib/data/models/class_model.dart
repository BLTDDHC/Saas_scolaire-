/// Modèle Classe
class ClassModel {
  final String id;
  final String name;
  final String? cycle;
  final String? cycleId;
  final String? level;
  final String? levelId;
  final String? structuredLevelId;
  final String? grade;
  final String? series;
  final String? seriesId;
  int students;
  String? mainTeacher;
  String? mainTeacherId;
  int? subjects;
  String? room;
  final String schoolId;
  final String? institutionId;
  String? academicYearId;
  final String? institutionType;
  String? academicYearName;
  final String? createdAt;

  ClassModel({
    required this.id,
    required this.name,
    this.cycle,
    this.cycleId,
    this.level,
    this.levelId,
    this.structuredLevelId,
    this.grade,
    this.series,
    this.seriesId,
    this.students = 0,
    this.mainTeacher,
    this.mainTeacherId,
    this.subjects,
    this.room,
    required this.schoolId,
    this.institutionId,
    this.academicYearId,
    this.institutionType,
    this.academicYearName,
    this.createdAt,
  });

  String? get schoolYearId => academicYearId;
  set schoolYearId(String? value) => academicYearId = value;

  String? get roomNumber => room;
  set roomNumber(String? value) => room = value;

  factory ClassModel.fromJson(Map<String, dynamic> json) {
    return ClassModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      cycle: json['cycle'],
      cycleId: json['cycleId']?.toString(),
      level: json['level'],
      levelId: json['levelId'],
      structuredLevelId: json['structuredLevelId']?.toString(),
      grade: json['grade'],
      series: json['series'],
      seriesId: json['seriesId'] ?? json['series_id'],
      students: json['students'] ?? 0,
      mainTeacher: json['mainTeacher'],
      mainTeacherId: json['mainTeacherId']?.toString(),
      subjects: json['subjects'],
      room: json['room'] ?? json['roomNumber'],
      schoolId: json['schoolId'] ?? json['institutionId'] ?? '',
      institutionId: json['institutionId'],
      academicYearId: json['academicYearId'] ?? json['schoolYearId'],
      institutionType: json['institutionType'],
      academicYearName: json['academicYearName'],
      createdAt: json['createdAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cycle': cycle,
        'cycleId': cycleId,
        'level': level,
        'levelId': levelId,
        'structuredLevelId': structuredLevelId,
        'grade': grade,
        'series': series,
        'seriesId': seriesId,
        'students': students,
        'mainTeacher': mainTeacher,
        'mainTeacherId': mainTeacherId,
        'subjects': subjects,
        'room': room,
        'roomNumber': room,
        'schoolId': schoolId,
        'institutionId': institutionId,
        'academicYearId': academicYearId,
        'schoolYearId': academicYearId,
        'institutionType': institutionType,
        'academicYearName': academicYearName,
        'createdAt': createdAt,
      };

  ClassModel copyWith({
    String? cycle,
    String? cycleId,
    String? name,
    String? level,
    String? levelId,
    String? structuredLevelId,
    String? grade,
    String? series,
    String? seriesId,
    int? students,
    String? mainTeacher,
    String? mainTeacherId,
    String? room,
    String? academicYearId,
    String? institutionId,
    String? academicYearName,
    String? createdAt,
  }) {
    return ClassModel(
      id: id,
      name: name ?? this.name,
      cycle: cycle ?? this.cycle,
      cycleId: cycleId ?? this.cycleId,
      level: level ?? this.level,
      levelId: levelId ?? this.levelId,
      structuredLevelId: structuredLevelId ?? this.structuredLevelId,
      grade: grade ?? this.grade,
      series: series ?? this.series,
      seriesId: seriesId ?? this.seriesId,
      students: students ?? this.students,
      mainTeacher: mainTeacher ?? this.mainTeacher,
      mainTeacherId: mainTeacherId ?? this.mainTeacherId,
      subjects: subjects,
      room: room ?? this.room,
      schoolId: schoolId,
      institutionId: institutionId ?? this.institutionId,
      academicYearId: academicYearId ?? this.academicYearId,
      institutionType: institutionType,
      academicYearName: academicYearName ?? this.academicYearName,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
