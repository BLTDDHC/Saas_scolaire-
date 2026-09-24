// Modèles pour le module Finance

// Frais scolaires / universitaires
class FeeModel {
  final String id;
  final String name;
  final double amount;
  // Backwards-compatible fields
  final String? className; // legacy: human name of class
  final String? level; // legacy

  // New explicit scope fields
  final String? scope; // 'establishment'|'cycle'|'level'|'class'
  final String? cycle; // cycle name (e.g., 'Lycée') or id if available
  final String? levelId; // reference to SchoolLevelModel.id
  final String? classId; // reference to ClassModel.id
  final String? schoolRegime; // part_time|full_time for Maternelle/Primaire tuition

  String? get schoolYearId => academicYearId;
  set schoolYearId(String? value) => academicYearId = value;

  final String? description;
  final String? schoolId;
  final String? institutionId;
  String? academicYearId;
  String status;
  final String? type; // exemple: 'registration','tuition','other'
  final bool isMandatoryAtRegistration;
  final bool isOccasional;
  final String? frequency; // e.g., 'annual','monthly'
  final String? applicableTo; // additional applicability hint

  FeeModel({
    required this.id,
    required this.name,
    required this.amount,
    this.className,
    this.level,
    this.scope,
    this.cycle,
    this.levelId,
    this.classId,
    this.schoolRegime,
    this.description,
    this.schoolId,
    this.institutionId,
    this.academicYearId,
    this.type,
    this.isMandatoryAtRegistration = false,
    this.isOccasional = false,
    this.frequency,
    this.applicableTo,
    this.status = 'active',
  });

  factory FeeModel.fromJson(Map<String, dynamic> json) {
    // Backwards compatibility: if older data used 'class' as name, interpret as scope=class
    String? scope = json['scope'] ?? json['applicableTo'];
    final legacyClass = json['class'];
    if ((scope == null || scope == '') && legacyClass != null) {
      scope = 'class';
    }

    return FeeModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      className: legacyClass,
      level: json['level'],
      scope: scope,
      cycle: json['cycle'] ?? json['cycleId'],
      levelId: json['levelId'] ?? json['schoolLevelId'] ?? json['levelId'],
      classId: json['classId'] ?? json['class_id'],
      schoolRegime: json['schoolRegime'],
      description: json['description'],
      schoolId: json['schoolId'] ?? json['institutionId'],
      institutionId: json['institutionId'] ?? json['schoolId'],
      academicYearId: json['academicYearId'] ?? json['schoolYearId'],
      type: json['type'],
      isMandatoryAtRegistration: json['isMandatoryAtRegistration'] == true,
      isOccasional: json['isOccasional'] == true,
      frequency: json['frequency'],
      applicableTo: json['applicableTo'],
      status: json['status'] ?? 'active',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'amount': amount,
    'class': className,
    'level': level,
    'scope': scope,
    'cycle': cycle,
    'levelId': levelId,
    'classId': classId,
    'schoolRegime': schoolRegime,
    'description': description,
    'type': type,
    'isMandatoryAtRegistration': isMandatoryAtRegistration,
    'isOccasional': isOccasional,
    'frequency': frequency,
    'applicableTo': applicableTo,
    'schoolId': schoolId,
    'institutionId': institutionId,
    'academicYearId': academicYearId,
    'schoolYearId': academicYearId,
    'status': status,
  };
}

/// Inscription financière
class FinanceRegistrationModel {
  final String id;
  final String studentId;
  final String? studentName;
  final String? className;
  final String? classId;
  final List<String> feeIds;
  final String? schoolId;
  final String? institutionId;
  String? academicYearId;

  String? get schoolYearId => academicYearId;
  set schoolYearId(String? value) => academicYearId = value;
  final String? type;
  final String? createdAt;
  // Champs universitaires
  final String? facultyId;
  final String? departmentId;
  final String? programId;
  final String? optionId;
  final String? levelId;
  String status;

  FinanceRegistrationModel({
    required this.id,
    required this.studentId,
    this.studentName,
    this.className,
    this.classId,
    this.feeIds = const [],
    this.schoolId,
    this.institutionId,
    this.academicYearId,
    this.type,
    this.createdAt,
    this.facultyId,
    this.departmentId,
    this.programId,
    this.optionId,
    this.levelId,
    this.status = 'active',
  });

  factory FinanceRegistrationModel.fromJson(Map<String, dynamic> json) {
    return FinanceRegistrationModel(
      id: json['id'] ?? '',
      studentId: json['studentId'] ?? '',
      studentName: json['studentName'],
      className: json['className'] ?? json['class'],
      classId: json['classId'] ?? json['class_id'],
      feeIds: json['feeIds'] != null ? List<String>.from(json['feeIds']) : [],
      schoolId: json['schoolId'] ?? json['institutionId'],
      institutionId: json['institutionId'] ?? json['schoolId'],
      academicYearId: json['academicYearId'] ?? json['schoolYearId'],
      type: json['type'],
      createdAt: json['createdAt'],
      facultyId: json['facultyId'] ?? json['faculty'],
      departmentId: json['departmentId'],
      programId: json['programId'] ?? json['program'],
      optionId: json['optionId'],
      levelId: json['levelId'] ?? json['level'],
      status: json['status'] ?? 'active',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'studentId': studentId,
    'studentName': studentName,
    'className': className,
    'class': className,
    'classId': classId,
    'feeIds': feeIds,
    'type': type,
    'createdAt': createdAt,
    'schoolId': schoolId,
    'institutionId': institutionId,
    'academicYearId': academicYearId,
    'schoolYearId': academicYearId,
    'facultyId': facultyId,
    'departmentId': departmentId,
    'programId': programId,
    'optionId': optionId,
    'levelId': levelId,
    'status': status,
  };
}

/// Affectation de frais à une inscription
class FinanceFeeAssignmentModel {
  final String id;
  final String registrationId;
  final String feeId;
  final String studentId;
  final String? studentName;
  final double amount;
  final String? dueDate;
  final String? schoolId;
  final String? institutionId;
  String? academicYearId;
  String status;

  String? get schoolYearId => academicYearId;
  set schoolYearId(String? value) => academicYearId = value;

  FinanceFeeAssignmentModel({
    required this.id,
    required this.registrationId,
    required this.feeId,
    required this.studentId,
    this.studentName,
    required this.amount,
    this.dueDate,
    this.schoolId,
    this.institutionId,
    this.academicYearId,
    this.status = 'assigned',
  });

  factory FinanceFeeAssignmentModel.fromJson(Map<String, dynamic> json) {
    return FinanceFeeAssignmentModel(
      id: json['id'] ?? '',
      registrationId: json['registrationId'] ?? '',
      feeId: json['feeId'] ?? '',
      studentId: json['studentId'] ?? '',
      studentName: json['studentName'],
      amount: (json['amount'] ?? 0).toDouble(),
      dueDate: json['dueDate'],
      schoolId: json['schoolId'] ?? json['institutionId'],
      institutionId: json['institutionId'] ?? json['schoolId'],
      academicYearId: json['academicYearId'] ?? json['schoolYearId'],
      status: json['status'] ?? 'assigned',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'registrationId': registrationId,
    'feeId': feeId,
    'studentId': studentId,
    'studentName': studentName,
    'amount': amount,
    'dueDate': dueDate,
    'schoolId': schoolId,
    'institutionId': institutionId,
    'academicYearId': academicYearId,
    'schoolYearId': academicYearId,
    'status': status,
  };
}

/// Paiement financier
class FinancePaymentModel {
  final String id;
  final String registrationId;
  final String? feeAssignmentId;
  final String studentId;
  final String? studentName;
  final double amount;
  final String date;
  final String paymentMethod; // 'cash', 'card', 'transfer', 'mobile'
  final String? reference;
  final String? receivedBy;
  String? note;
  final String? schoolId;
  final String? institutionId;
  String? academicYearId;
  String status; // 'active'|'cancelled'

  String? get schoolYearId => academicYearId;
  set schoolYearId(String? value) => academicYearId = value;

  FinancePaymentModel({
    required this.id,
    required this.registrationId,
    this.feeAssignmentId,
    required this.studentId,
    this.studentName,
    required this.amount,
    required this.date,
    this.paymentMethod = 'cash',
    this.reference,
    this.receivedBy,
    this.note,
    this.schoolId,
    this.institutionId,
    this.academicYearId,
    this.status = 'active',
  });

  factory FinancePaymentModel.fromJson(Map<String, dynamic> json) {
    return FinancePaymentModel(
      id: json['id'] ?? '',
      registrationId: json['registrationId'] ?? '',
      feeAssignmentId: json['feeAssignmentId'],
      studentId: json['studentId'] ?? '',
      studentName: json['studentName'],
      amount: (json['amount'] ?? 0).toDouble(),
      date: json['date'] ?? '',
      paymentMethod: json['paymentMethod'] ?? json['method'] ?? 'cash',
      reference: json['reference'],
      receivedBy: json['receivedBy'],
      note: json['note'],
      schoolId: json['schoolId'] ?? json['institutionId'],
      institutionId: json['institutionId'] ?? json['schoolId'],
      academicYearId: json['academicYearId'] ?? json['schoolYearId'],
      status: json['status'] ?? 'active',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'registrationId': registrationId,
    'feeAssignmentId': feeAssignmentId,
    'studentId': studentId,
    'studentName': studentName,
    'amount': amount,
    'date': date,
    'paymentMethod': paymentMethod,
    'reference': reference,
    'receivedBy': receivedBy,
    'note': note,
    'schoolId': schoolId,
    'institutionId': institutionId,
    'academicYearId': academicYearId,
    'schoolYearId': academicYearId,
    'status': status,
  };
}

/// Reçu de paiement
class FinanceReceiptModel {
  final String id;
  final String paymentId;
  final String receiptNumber;
  final String date;
  final String? studentId;
  final String? studentName;
  final double amount;
  final String? schoolId;
  final String? institutionId;
  final String? academicYearId;
  final String status;

  FinanceReceiptModel({
    required this.id,
    required this.paymentId,
    required this.receiptNumber,
    required this.date,
    this.studentId,
    this.studentName,
    required this.amount,
    this.schoolId,
    this.institutionId,
    this.academicYearId,
    this.status = 'active',
  });

  factory FinanceReceiptModel.fromJson(Map<String, dynamic> json) {
    return FinanceReceiptModel(
      id: json['id'] ?? '',
      paymentId: json['paymentId'] ?? '',
      receiptNumber: json['receiptNumber'] ?? '',
      date: json['date'] ?? '',
      studentId: json['studentId'],
      studentName: json['studentName'],
      amount: (json['amount'] ?? 0).toDouble(),
      schoolId: json['schoolId'] ?? json['institutionId'],
      institutionId: json['institutionId'] ?? json['schoolId'],
      academicYearId: json['academicYearId'],
      status: json['status'] ?? 'active',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'paymentId': paymentId,
    'receiptNumber': receiptNumber,
    'date': date,
    'studentId': studentId,
    'studentName': studentName,
    'amount': amount,
    'schoolId': schoolId,
    'institutionId': institutionId,
    'academicYearId': academicYearId,
    'status': status,
  };
}

// --- New explicit Financial Account models (separate from FinanceRegistration / Assignment)
class FinancialAccountModel {
  final String id;
  final String studentId;
  final String? studentName;
  final String? registrationId;
  final String? schoolId;
  String? academicYearId;
  String status; // 'active'|'closed'

  FinancialAccountModel({
    required this.id,
    required this.studentId,
    this.studentName,
    this.registrationId,
    this.schoolId,
    this.academicYearId,
    this.status = 'active',
  });

  factory FinancialAccountModel.fromJson(Map<String, dynamic> json) {
    return FinancialAccountModel(
      id: json['id'] ?? '',
      studentId: json['studentId'] ?? '',
      studentName: json['studentName'],
      registrationId: json['registrationId'],
      schoolId: json['schoolId'] ?? json['institutionId'],
      academicYearId: json['academicYearId'] ?? json['schoolYearId'],
      status: json['status'] ?? 'active',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'studentId': studentId,
    'studentName': studentName,
    'registrationId': registrationId,
    'schoolId': schoolId,
    'academicYearId': academicYearId,
    'status': status,
  };
}

class FinancialLineModel {
  final String id;
  final String financialAccountId;
  final String feeId;
  final String label;
  final double amountDue;
  String status; // 'open'|'paid'|'cancelled'

  FinancialLineModel({
    required this.id,
    required this.financialAccountId,
    required this.feeId,
    required this.label,
    required this.amountDue,
    this.status = 'open',
  });

  factory FinancialLineModel.fromJson(Map<String, dynamic> json) {
    return FinancialLineModel(
      id: json['id'] ?? '',
      financialAccountId: json['financialAccountId'] ?? '',
      feeId: json['feeId'] ?? '',
      label: json['label'] ?? '',
      amountDue: (json['amountDue'] ?? 0).toDouble(),
      status: json['status'] ?? 'open',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'financialAccountId': financialAccountId,
    'feeId': feeId,
    'label': label,
    'amountDue': amountDue,
    'status': status,
  };
}

class FinancialPaymentRecord {
  final String id;
  final String financialLineId;
  final String studentId;
  final double amount;
  final String date; // ISO date
  final String paymentMethod;
  final String? reference;
  String status; // 'active'|'cancelled'

  FinancialPaymentRecord({
    required this.id,
    required this.financialLineId,
    required this.studentId,
    required this.amount,
    required this.date,
    this.paymentMethod = 'cash',
    this.reference,
    this.status = 'active',
  });

  factory FinancialPaymentRecord.fromJson(Map<String, dynamic> json) {
    return FinancialPaymentRecord(
      id: json['id'] ?? '',
      financialLineId: json['financialLineId'] ?? json['feeAssignmentId'],
      studentId: json['studentId'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      date: json['date'] ?? '',
      paymentMethod: json['paymentMethod'] ?? json['method'] ?? 'cash',
      reference: json['reference'],
      status: json['status'] ?? 'active',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'financialLineId': financialLineId,
    'studentId': studentId,
    'amount': amount,
    'date': date,
    'paymentMethod': paymentMethod,
    'reference': reference,
    'status': status,
  };
}
