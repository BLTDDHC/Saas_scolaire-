/// Modèle de Configuration des Évaluations par Période (Définie par l'Établissement)
class EvaluationPeriodConfigModel {
  final String id;
  final String schoolId;
  final String academicYearId;
  final String periodId; // 'T1', 'T2', 'T3', etc.
  final String periodName; // 'Trimestre 1', 'Trimestre 2', etc.
  final int homeworkCount; // Nombre de devoirs prévus (ex: 2, 3, 4)
  final bool hasComposition; // Si une composition est prévue (par défaut true)
  final String status; // 'configured' | 'active' | 'closed' | 'locked'

  EvaluationPeriodConfigModel({
    required this.id,
    required this.schoolId,
    required this.academicYearId,
    required this.periodId,
    required this.periodName,
    this.homeworkCount = 2,
    this.hasComposition = true,
    this.status = 'configured',
  });

  bool get isActive => status == 'active';
  bool get isClosed => status == 'closed';
  bool get isLocked => status == 'locked' || status == 'configured';
  bool get isConfigured => status == 'configured';

  factory EvaluationPeriodConfigModel.fromJson(Map<String, dynamic> json) {
    return EvaluationPeriodConfigModel(
      id: json['id'] ?? '',
      schoolId: json['schoolId'] ?? '',
      academicYearId: json['academicYearId'] ?? '',
      periodId: json['periodId'] ?? 'T1',
      periodName: json['periodName'] ?? 'Trimestre 1',
      homeworkCount: (json['homeworkCount'] as num?)?.toInt() ?? 2,
      hasComposition: json['hasComposition'] ?? true,
      status: json['status'] ?? 'configured',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'schoolId': schoolId,
    'academicYearId': academicYearId,
    'periodId': periodId,
    'periodName': periodName,
    'homeworkCount': homeworkCount,
    'hasComposition': hasComposition,
    'status': status,
  };

  EvaluationPeriodConfigModel copyWith({
    String? id,
    String? schoolId,
    String? academicYearId,
    String? periodId,
    String? periodName,
    int? homeworkCount,
    bool? hasComposition,
    String? status,
  }) {
    return EvaluationPeriodConfigModel(
      id: id ?? this.id,
      schoolId: schoolId ?? this.schoolId,
      academicYearId: academicYearId ?? this.academicYearId,
      periodId: periodId ?? this.periodId,
      periodName: periodName ?? this.periodName,
      homeworkCount: homeworkCount ?? this.homeworkCount,
      hasComposition: hasComposition ?? this.hasComposition,
      status: status ?? this.status,
    );
  }
}

