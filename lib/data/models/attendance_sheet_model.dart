import 'other_models.dart';

class AttendanceStudent {
  final String id;
  final String fullName;
  AttendanceStudent(Map<String, dynamic> json)
      : id = json['id'] as String, fullName = json['fullName'] as String;
}

class AttendanceSheetModel {
  final bool locked;
  final List<AttendanceStudent> students;
  final List<AbsenceModel> records;
  AttendanceSheetModel(Map<String, dynamic> json)
      : locked = json['sheetStatus'] == 'locked',
        students = (json['students'] as List).map((s) => AttendanceStudent(Map<String, dynamic>.from(s))).toList(),
        records = (json['records'] as List).map((r) => AbsenceModel.fromJson(Map<String, dynamic>.from(r))).toList();
}
