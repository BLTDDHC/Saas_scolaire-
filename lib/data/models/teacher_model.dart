/// Modèle Enseignant
class TeacherModel {
  final String id;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final String? subject;
  final String? status;
  final String schoolId;
  final String? sex;
  final String? birthDate;
  final String? address;
  final String? diploma;
  final String? hireDate;
  final String? userId;
  final String? employeeNumber;

  TeacherModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
    this.subject,
    this.status = 'active',
    required this.schoolId,
    this.sex,
    this.birthDate,
    this.address,
    this.diploma,
    this.hireDate,
    this.userId,
    this.employeeNumber,
  });

  String get fullName => '$lastName $firstName';
  String get initials {
    final f = firstName.isNotEmpty ? firstName[0] : '';
    final l = lastName.isNotEmpty ? lastName[0] : '';
    return '$f$l'.toUpperCase();
  }

  factory TeacherModel.fromJson(Map<String, dynamic> json) {
    return TeacherModel(
      id: json['id'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      email: json['email'],
      phone: json['phone'],
      subject: json['subject'],
      status: json['status'] ?? 'active',
      schoolId: json['schoolId'] ?? '',
      sex: json['sex'],
      birthDate: json['birthDate'],
      address: json['address'],
      diploma: json['diploma'],
      hireDate: json['hireDate'],
      userId: json['userId'],
      employeeNumber: json['employeeNumber'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'subject': subject,
        'status': status,
        'schoolId': schoolId,
        'sex': sex,
        'birthDate': birthDate,
        'address': address,
        'diploma': diploma,
        'hireDate': hireDate,
        'userId': userId,
        'employeeNumber': employeeNumber,
      };
}
