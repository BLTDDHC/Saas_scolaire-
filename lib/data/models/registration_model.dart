/// Modèle Inscription (Scolarité) — distinct du modèle financier
class StudentRegistrationModel {
  final String id;
  final String studentId;
  final String? studentName;
  final String? schoolId;
  final String? institutionId;
  final String? academicYearId;
  final String? classId;
  final String? className;
  final String? levelId;
  final String? seriesId;
  final String? registrationDate; // ISO date
  String status; // 'pending'|'validated'|'cancelled'
  final List<String> feeIds;
  final String? type;
  final String? createdAt;
  final String? schoolRegime;
  final List<Map<String, dynamic>> regimeHistory;
  // Optional academic/university fields for compatibility
  final String? facultyId;
  final String? departmentId;
  final String? programId;
  final String? optionId;

  StudentRegistrationModel({
    required this.id,
    required this.studentId,
    this.studentName,
    this.schoolId,
    this.institutionId,
    this.academicYearId,
    this.classId,
    this.className,
    this.levelId,
    this.seriesId,
    this.registrationDate,
    this.status = 'pending',
    this.feeIds = const [],
    this.type,
    this.createdAt,
    this.schoolRegime,
    this.regimeHistory = const [],
    this.facultyId,
    this.departmentId,
    this.programId,
    this.optionId,
  });

  factory StudentRegistrationModel.fromJson(Map<String, dynamic> json) {
    return StudentRegistrationModel(
      id: json['id'] ?? '',
      studentId: json['studentId'] ?? '',
      studentName: json['studentName'],
      schoolId: json['schoolId'] ?? json['institutionId'],
      institutionId: json['institutionId'] ?? json['schoolId'],
      academicYearId: json['academicYearId'] ?? json['schoolYearId'],
      classId: json['classId'] ?? json['class_id'],
      className: json['className'] ?? json['class'],
      levelId: json['levelId'] ?? json['level'],
      seriesId: json['seriesId'] ?? json['series'],
      registrationDate: json['registrationDate'] ?? json['createdAt'],
      status: json['status'] ?? 'pending',
      feeIds: json['feeIds'] != null ? List<String>.from(json['feeIds']) : [],
      type: json['type'],
      createdAt: json['createdAt'],
      schoolRegime: json['schoolRegime'],
      regimeHistory: List<Map<String, dynamic>>.from(
        (json['regimeHistory'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map)),
      ),
      facultyId: json['facultyId'],
      departmentId: json['departmentId'],
      programId: json['programId'],
      optionId: json['optionId'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'studentId': studentId,
    'studentName': studentName,
    'schoolId': schoolId,
    'institutionId': institutionId,
    'academicYearId': academicYearId,
    'schoolYearId': academicYearId,
    'classId': classId,
    'class': className,
    'className': className,
    'levelId': levelId,
    'seriesId': seriesId,
    'registrationDate': registrationDate,
    'status': status,
    'feeIds': feeIds,
    'type': type,
    'createdAt': createdAt,
    'schoolRegime': schoolRegime,
    'regimeHistory': regimeHistory,
    'facultyId': facultyId,
    'departmentId': departmentId,
    'programId': programId,
    'optionId': optionId,
  };
}
