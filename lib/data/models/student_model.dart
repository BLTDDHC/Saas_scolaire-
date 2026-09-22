/// Modèle Élève — reproduction exacte des champs data.js
class StudentModel {
  final String id;
  final String firstName;
  final String lastName;
  final String? classId;
  final String? className;
  final String? cycle;
  final String? levelId;
  final String? level;
  final String? grade;
  final String? series;
  final String? seriesId;
  final String? matricule;
  final String? email;
  final String? phone;
  final String? sex;
  final String? birthDate;
  final String? nationality;
  final String? address;
  String status;
  final String? parent;
  final String? parentPhone;
  final String? parentEmail;
  final List<Map<String, dynamic>> guardians;
  final String schoolId;
  final String? institutionId;
  final String? academicYearId;
  // Champs universitaires
  final String? facultyId;
  final String? departmentId;
  final String? programId;
  final String? optionId;
  final String? userId;
  final String? parentUserId;
  final String? photoUrl;

  StudentModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.classId,
    this.className,
    this.cycle,
    this.levelId,
    this.level,
    this.grade,
    this.series,
    this.seriesId,
    this.matricule,
    this.email,
    this.phone,
    this.sex,
    this.birthDate,
    this.nationality,
    this.address,
    this.status = 'active',
    this.parent,
    this.parentPhone,
    this.parentEmail,
    this.guardians = const [],
    required this.schoolId,
    this.institutionId,
    this.academicYearId,
    this.facultyId,
    this.departmentId,
    this.programId,
    this.optionId,
    this.userId,
    this.parentUserId,
    this.photoUrl,
  });

  String get fullName => '$lastName $firstName';
  String get initials {
    final f = firstName.isNotEmpty ? firstName[0] : '';
    final l = lastName.isNotEmpty ? lastName[0] : '';
    return '$f$l'.toUpperCase();
  }

  factory StudentModel.fromJson(Map<String, dynamic> json) {
    return StudentModel(
      id: json['id'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      classId: json['classId'],
      className: json['class'],
      cycle: json['cycle'],
      levelId: json['levelId'],
      level: json['level'],
      grade: json['grade'],
      series: json['series'],
      seriesId: json['seriesId'],
      matricule: json['matricule'],
      email: json['email'],
      phone: json['phone'],
      sex: json['sex'],
      birthDate: json['birthDate'],
      nationality: json['nationality'],
      address: json['address'],
      status: json['status'] ?? 'active',
      parent: json['parent'],
      parentPhone: json['parentPhone'],
      parentEmail: json['parentEmail'],
      guardians: (json['guardians'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
      schoolId: json['schoolId'] ?? json['institutionId'] ?? '',
      institutionId: json['institutionId'],
      academicYearId: json['academicYearId'],
      facultyId: json['facultyId'],
      departmentId: json['departmentId'],
      programId: json['programId'],
      optionId: json['optionId'],
      userId: json['userId'],
      parentUserId: json['parentUserId'],
      photoUrl: json['photoUrl']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'classId': classId,
        'class': className,
        'cycle': cycle,
        'levelId': levelId,
        'level': level,
        'grade': grade,
        'series': series,
        'seriesId': seriesId,
        'matricule': matricule,
        'email': email,
        'phone': phone,
        'sex': sex,
        'birthDate': birthDate,
        'nationality': nationality,
        'address': address,
        'status': status,
        'parent': parent,
        'parentPhone': parentPhone,
        'parentEmail': parentEmail,
        'guardians': guardians,
        'schoolId': schoolId,
        'institutionId': institutionId,
        'academicYearId': academicYearId,
        'facultyId': facultyId,
        'departmentId': departmentId,
        'programId': programId,
        'optionId': optionId,
        'userId': userId,
        'parentUserId': parentUserId,
        'photoUrl': photoUrl,
      };

  StudentModel copyWith({
    String? classId,
    String? className,
    String? cycle,
    String? levelId,
    String? level,
    String? grade,
    String? series,
    String? seriesId,
    String? email,
    String? phone,
    String? address,
    String? status,
    String? parent,
    String? parentPhone,
    String? parentEmail,
    List<Map<String, dynamic>>? guardians,
    String? academicYearId,
    String? facultyId,
    String? departmentId,
    String? programId,
    String? optionId,
    String? userId,
    String? parentUserId,
    String? photoUrl,
  }) {
    return StudentModel(
      id: id,
      firstName: firstName,
      lastName: lastName,
      classId: classId ?? this.classId,
      className: className ?? this.className,
      cycle: cycle ?? this.cycle,
      levelId: levelId ?? this.levelId,
      level: level ?? this.level,
      grade: grade ?? this.grade,
      series: series ?? this.series,
      seriesId: seriesId ?? this.seriesId,
      matricule: matricule,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      sex: sex,
      birthDate: birthDate,
      nationality: nationality,
      address: address ?? this.address,
      status: status ?? this.status,
      parent: parent ?? this.parent,
      parentPhone: parentPhone ?? this.parentPhone,
      parentEmail: parentEmail ?? this.parentEmail,
      guardians: guardians ?? this.guardians,
      schoolId: schoolId,
      institutionId: institutionId,
      academicYearId: academicYearId ?? this.academicYearId,
      facultyId: facultyId ?? this.facultyId,
      departmentId: departmentId ?? this.departmentId,
      programId: programId ?? this.programId,
      optionId: optionId ?? this.optionId,
      userId: userId ?? this.userId,
      parentUserId: parentUserId ?? this.parentUserId,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }
}
