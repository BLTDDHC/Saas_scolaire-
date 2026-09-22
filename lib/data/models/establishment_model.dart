import '../../core/constants/establishment_types.dart';
import 'education/school_cycle_model.dart';

/// Modèle Établissement — reproduction exacte de la structure JS
class EstablishmentModel {
  final String id;
  final String name;
  final String? code;
  final String type;
  final InstitutionType institutionType;
  final String? address;
  final String city;
  final String? country;
  final String? phone;
  final String? email;
  final String admin;
  final EstablishmentAdmin? administrator;
  final EstablishmentSubscription? subscription;
  final List<String> enabledModules;
  final List<String> planFeatures;
  final List<String> planFeatureLabels;
  final List<String> enabledModuleLabels;
  final List<SchoolCycleModel> cycles;
  int students;
  final String plan;
  String status;
  final String date;
  final String? createdAt;

  EstablishmentModel({
    required this.id,
    required this.name,
    this.code,
    required this.type,
    required this.institutionType,
    this.address,
    this.city = 'Brazzaville',
    this.country,
    this.phone,
    this.email,
    this.admin = 'Non renseigné',
    this.administrator,
    this.subscription,
    this.enabledModules = const [],
    this.planFeatures = const [],
    this.planFeatureLabels = const [],
    this.enabledModuleLabels = const [],
    this.cycles = const [],
    this.students = 0,
    this.plan = 'pro',
    this.status = 'active',
    String? date,
    this.createdAt,
  }) : date = date ?? DateTime.now().toIso8601String().split('T')[0];

  bool get isHigherEducation => institutionType.isHigherEducation;

  factory EstablishmentModel.fromJson(Map<String, dynamic> json) {
    final typeLabel = json['type'] ?? '';
    final instType = json['institutionType'] != null
        ? InstitutionType.fromValue(json['institutionType'])
        : InstitutionType.fromTypeLabel(typeLabel);

    return EstablishmentModel(
      id: json['id'] ?? json['schoolId'] ?? '',
      name: json['name'] ?? '',
      code: json['code']?.toString(),
      type: typeLabel.isNotEmpty ? typeLabel : instType.label,
      institutionType: instType,
      address: json['address'],
      city: json['city'] ?? 'Brazzaville',
      country: json['country'],
      phone: json['phone'],
      email: json['email'],
      admin: json['admin'] ??
          (json['administrator'] is Map
              ? json['administrator']['name']
              : null) ??
          'Non renseigné',
      administrator: json['administrator'] != null
          ? EstablishmentAdmin.fromJson(json['administrator'])
          : null,
      subscription: json['subscription'] != null
          ? EstablishmentSubscription.fromJson(json['subscription'])
          : null,
      enabledModules: List<String>.from(json['enabledModules'] ?? const []),
      planFeatures: List<String>.from(json['planFeatures'] ?? const []),
      planFeatureLabels:
          List<String>.from(json['planFeatureLabels'] ?? const []),
      enabledModuleLabels:
          List<String>.from(json['enabledModuleLabels'] ?? const []),
      cycles: (json['cycles'] as List? ?? const [])
          .map((item) =>
              SchoolCycleModel.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      students: json['students'] ?? 0,
      plan: json['plan'] ?? 'pro',
      status: json['status'] ?? 'active',
      date: json['date'],
      createdAt: json['createdAt'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'type': type,
      'institutionType': institutionType.value,
      'address': address,
      'city': city,
      'country': country,
      'phone': phone,
      'email': email,
      'admin': admin,
      'administrator': administrator?.toJson(),
      'subscription': subscription?.toJson(),
      'enabledModules': enabledModules,
      'planFeatures': planFeatures,
      'planFeatureLabels': planFeatureLabels,
      'enabledModuleLabels': enabledModuleLabels,
      'cycles': cycles.map((cycle) => cycle.toJson()).toList(),
      'students': students,
      'plan': plan,
      'status': status,
      'date': date,
      'createdAt': createdAt,
    };
  }

  EstablishmentModel copyWith({
    String? name,
    String? code,
    String? type,
    InstitutionType? institutionType,
    String? address,
    String? city,
    String? country,
    String? phone,
    String? email,
    String? admin,
    EstablishmentAdmin? administrator,
    EstablishmentSubscription? subscription,
    List<String>? enabledModules,
    List<String>? planFeatures,
    List<String>? planFeatureLabels,
    List<String>? enabledModuleLabels,
    List<SchoolCycleModel>? cycles,
    int? students,
    String? plan,
    String? status,
  }) {
    return EstablishmentModel(
      id: id,
      name: name ?? this.name,
      code: code ?? this.code,
      type: type ?? this.type,
      institutionType: institutionType ?? this.institutionType,
      address: address ?? this.address,
      city: city ?? this.city,
      country: country ?? this.country,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      admin: admin ?? this.admin,
      administrator: administrator ?? this.administrator,
      subscription: subscription ?? this.subscription,
      enabledModules: enabledModules ?? this.enabledModules,
      planFeatures: planFeatures ?? this.planFeatures,
      planFeatureLabels: planFeatureLabels ?? this.planFeatureLabels,
      enabledModuleLabels: enabledModuleLabels ?? this.enabledModuleLabels,
      cycles: cycles ?? this.cycles,
      students: students ?? this.students,
      plan: plan ?? this.plan,
      status: status ?? this.status,
      date: date,
      createdAt: createdAt,
    );
  }
}

/// Sous-modèle : administrateur d'un établissement
class EstablishmentAdmin {
  final String? id;
  final String name;
  final String email;
  final String? phone;
  final String status;
  final bool mustChangePassword;
  final String? createdAt;

  const EstablishmentAdmin({
    this.id,
    required this.name,
    required this.email,
    this.phone,
    this.status = 'active',
    this.mustChangePassword = false,
    this.createdAt,
  });

  factory EstablishmentAdmin.fromJson(Map<String, dynamic> json) {
    return EstablishmentAdmin(
      id: json['id'],
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'],
      status: json['status'] ?? 'active',
      mustChangePassword: json['mustChangePassword'] ?? false,
      createdAt: json['createdAt'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'status': status,
        'mustChangePassword': mustChangePassword,
        'createdAt': createdAt,
      };
}

class EstablishmentSubscription {
  const EstablishmentSubscription({
    required this.id,
    required this.plan,
    required this.status,
    required this.price,
    this.startDate,
    this.endDate,
  });

  final String id;
  final String plan;
  final String status;
  final String price;
  final String? startDate;
  final String? endDate;

  factory EstablishmentSubscription.fromJson(Map<String, dynamic> json) =>
      EstablishmentSubscription(
        id: json['id'] ?? '',
        plan: json['plan'] ?? '',
        status: json['status'] ?? '',
        price: json['price']?.toString() ?? '0',
        startDate: json['startDate'],
        endDate: json['endDate'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'plan': plan,
        'status': status,
        'price': price,
        'startDate': startDate,
        'endDate': endDate,
      };
}
