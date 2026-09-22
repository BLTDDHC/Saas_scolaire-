/// Modèle Absence
class AbsenceModel {
  final String id;
  final String studentId;
  final String? studentName;
  final String date;
  final String status; // 'present', 'absent', 'late', 'justified'
  final String? className;
  final String? subject;
  final String? period;
  final String? reason;
  final String? schoolId;
  final String? academicYearId;
  final String? classId;
  final String? scheduleId;
  final String? teacherId;
  final String? subjectId;
  final String? startTime;
  final String? endTime;

  AbsenceModel({
    required this.id,
    required this.studentId,
    this.studentName,
    required this.date,
    required this.status,
    this.className,
    this.subject,
    this.period,
    this.reason,
    this.schoolId,
    this.academicYearId,
    this.classId,
    this.scheduleId,
    this.teacherId,
    this.subjectId,
    this.startTime,
    this.endTime,
  });

  factory AbsenceModel.fromJson(Map<String, dynamic> json) {
    return AbsenceModel(
      id: json['id'] ?? '',
      studentId: json['studentId'] ?? '',
      studentName: json['studentName'],
      date: json['date'] ?? '',
      status: json['status'] ?? 'absent',
      className: json['class'],
      subject: json['subject'],
      period: json['period'],
      reason: json['reason'],
      schoolId: json['schoolId'],
      academicYearId: json['academicYearId'],
      classId: json['classId'],
      scheduleId: json['scheduleId'],
      teacherId: json['teacherId'],
      subjectId: json['subjectId'],
      startTime: json['startTime'],
      endTime: json['endTime'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'studentId': studentId,
        'studentName': studentName,
        'date': date,
        'status': status,
        'class': className,
        'subject': subject,
        'period': period,
        'reason': reason,
        'schoolId': schoolId,
        'academicYearId': academicYearId,
        'classId': classId,
        'scheduleId': scheduleId,
        'teacherId': teacherId,
        'subjectId': subjectId,
        'startTime': startTime,
        'endTime': endTime,
      };
}

/// Modèle Devoir
class AssignmentModel {
  final String id;
  final String title;
  final String? description;
  final String? subject;
  final String? className;
  final String dueDate;
  final String? status;
  final String schoolId;

  AssignmentModel({
    required this.id,
    required this.title,
    this.description,
    this.subject,
    this.className,
    required this.dueDate,
    this.status = 'active',
    required this.schoolId,
  });

  factory AssignmentModel.fromJson(Map<String, dynamic> json) {
    return AssignmentModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      subject: json['subject'],
      className: json['class'],
      dueDate: json['dueDate'] ?? json['date'] ?? '',
      status: json['status'],
      schoolId: json['schoolId'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'subject': subject,
        'class': className,
        'dueDate': dueDate,
        'status': status,
        'schoolId': schoolId,
      };
}

/// Modèle Notification
class NotificationModel {
  final String id;
  final String title;
  final String? message;
  final String? type;
  final String? icon;
  final String?
      targetUserId; // optional: notification intended for a specific user
  final String? schoolId; // optional: notification scoped to a school
  bool read;
  final String time;

  NotificationModel({
    required this.id,
    required this.title,
    this.message,
    this.type,
    this.icon,
    this.targetUserId,
    this.schoolId,
    this.read = false,
    this.time = "À l'instant",
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      message: json['message'],
      type: json['type'],
      icon: json['icon'],
      targetUserId: json['targetUserId'],
      schoolId: json['schoolId'],
      read: json['read'] ?? false,
      time: json['time'] ?? "À l'instant",
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'message': message,
        'type': type,
        'icon': icon,
        'targetUserId': targetUserId,
        'schoolId': schoolId,
        'read': read,
        'time': time,
      };
}

/// Modèle Abonnement
class SubscriptionModel {
  final String id;
  final String? schoolId;
  final String client;
  final String plan;
  final String price;
  final String startDate;
  final String endDate;
  final String status;

  SubscriptionModel({
    this.id = '',
    this.schoolId,
    required this.client,
    required this.plan,
    required this.price,
    required this.startDate,
    required this.endDate,
    required this.status,
  });

  SubscriptionModel copyWith({
    String? id,
    String? schoolId,
    String? client,
    String? plan,
    String? price,
    String? startDate,
    String? endDate,
    String? status,
  }) {
    return SubscriptionModel(
      id: id ?? this.id,
      schoolId: schoolId ?? this.schoolId,
      client: client ?? this.client,
      plan: plan ?? this.plan,
      price: price ?? this.price,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
    );
  }

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    return SubscriptionModel(
      id: json['id'] ?? '',
      schoolId: json['schoolId'],
      client: json['client'] ?? '',
      plan: json['plan'] ?? '',
      price: json['price'] ?? '',
      startDate: json['startDate'] ?? '',
      endDate: json['endDate'] ?? '—',
      status: json['status'] ?? 'active',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'schoolId': schoolId,
        'client': client,
        'plan': plan,
        'price': price,
        'startDate': startDate,
        'endDate': endDate,
        'status': status,
      };
}

/// Modèle Conversation / Annonce
class ConversationModel {
  final String id;
  final String name;
  final String? lastMessage;
  final String? time;
  final bool? unread;

  ConversationModel({
    required this.id,
    required this.name,
    this.lastMessage,
    this.time,
    this.unread,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      lastMessage: json['lastMessage'],
      time: json['time'],
      unread: json['unread'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lastMessage': lastMessage,
        'time': time,
        'unread': unread,
      };
}

/// Modèle Annonce
class AnnouncementModel {
  final String id;
  final String title;
  final String? content;
  final String? author;
  final String? date;
  final String? priority;
  final String? schoolId;
  final String? classId;
  final String? cycle;
  final String? levelId;
  final String? targetRole;
  final String? authorUserId;
  final Map<String, String> reactions;

  AnnouncementModel({
    required this.id,
    required this.title,
    this.content,
    this.author,
    this.date,
    this.priority,
    this.schoolId,
    this.classId,
    this.cycle,
    this.levelId,
    this.targetRole,
    this.authorUserId,
    this.reactions = const {},
  });

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
    return AnnouncementModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      content: json['content'],
      author: json['author'],
      date: json['date'],
      priority: json['priority'],
      schoolId: json['schoolId'],
      classId: json['classId'],
      cycle: json['cycle'],
      levelId: json['levelId'],
      targetRole: json['targetRole'],
      authorUserId: json['authorUserId'],
      reactions: Map<String, String>.from(json['reactions'] ?? const {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'author': author,
        'date': date,
        'priority': priority,
        'schoolId': schoolId,
        'classId': classId,
        'cycle': cycle,
        'levelId': levelId,
        'targetRole': targetRole,
        'authorUserId': authorUserId,
        'reactions': reactions,
      };
}

/// Modèle Document

/// Modèle d'entrée d'audit / journal des actions
class AuditLogModel {
  final String id;
  final String
      action; // e.g., 'SUBMIT_EVALUATION', 'VALIDATE_EVALUATION', 'REQUEST_GRADE_MOD', 'APPROVE_GRADE_MOD'
  final String objectType; // 'evaluation', 'grade', 'request', 'decision'
  final String objectId;
  final String userId;
  final String userRole;
  final String schoolId;
  final String timestamp;
  final Map<String, dynamic>? oldValue;
  final Map<String, dynamic>? newValue;
  final String? reason;

  AuditLogModel({
    required this.id,
    required this.action,
    required this.objectType,
    required this.objectId,
    required this.userId,
    required this.userRole,
    required this.schoolId,
    required this.timestamp,
    this.oldValue,
    this.newValue,
    this.reason,
  });

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    return AuditLogModel(
      id: json['id'] ?? '',
      action: json['action'] ?? '',
      objectType: json['objectType'] ?? '',
      objectId: json['objectId'] ?? '',
      userId: json['userId'] ?? '',
      userRole: json['userRole'] ?? '',
      schoolId: json['schoolId'] ?? '',
      timestamp: json['timestamp'] ?? '',
      oldValue: json['oldValue'] != null
          ? Map<String, dynamic>.from(json['oldValue'])
          : null,
      newValue: json['newValue'] != null
          ? Map<String, dynamic>.from(json['newValue'])
          : null,
      reason: json['reason'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'action': action,
        'objectType': objectType,
        'objectId': objectId,
        'userId': userId,
        'userRole': userRole,
        'schoolId': schoolId,
        'timestamp': timestamp,
        'oldValue': oldValue,
        'newValue': newValue,
        'reason': reason,
      };
}

/// Modèle Document
class DocumentModel {
  final String id;
  final String title;
  final String? type;
  final String? date;
  final String schoolId;
  final String? entityId;
  final String? academicYearId;
  final String? createdBy;
  final String status;
  final Map<String, dynamic> metadata;

  DocumentModel({
    required this.id,
    required this.title,
    this.type,
    this.date,
    required this.schoolId,
    this.entityId,
    this.academicYearId,
    this.createdBy,
    this.status = 'generated',
    this.metadata = const {},
  });

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      type: json['type'],
      date: json['date'],
      schoolId: json['schoolId'] ?? '',
      entityId: json['entityId'],
      academicYearId: json['academicYearId'],
      createdBy: json['createdBy'],
      status: json['status'] ?? 'generated',
      metadata: Map<String, dynamic>.from(json['metadata'] ?? const {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type,
        'date': date,
        'schoolId': schoolId,
        'entityId': entityId,
        'academicYearId': academicYearId,
        'createdBy': createdBy,
        'status': status,
        'metadata': metadata,
      };
}

/// Modèle Emploi du temps
class ScheduleItemModel {
  final String? day;
  final String? time;
  final String? subject;
  final String? teacher;
  final String? room;
  final String? className;

  ScheduleItemModel({
    this.day,
    this.time,
    this.subject,
    this.teacher,
    this.room,
    this.className,
  });

  factory ScheduleItemModel.fromJson(Map<String, dynamic> json) {
    return ScheduleItemModel(
      day: json['day'],
      time: json['time'],
      subject: json['subject'],
      teacher: json['teacher'],
      room: json['room'],
      className: json['class'],
    );
  }

  Map<String, dynamic> toJson() => {
        'day': day,
        'time': time,
        'subject': subject,
        'teacher': teacher,
        'room': room,
        'class': className,
      };
}
