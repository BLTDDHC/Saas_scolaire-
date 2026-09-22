import '../../core/constants/establishment_types.dart';

/// Modèle utilisateur — reproduction exacte de la structure JS
class UserModel {
  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String roleName;
  final String initials;
  final String? schoolId;
  final String? establishment;
  final String? phone;
  final String? establishmentStatus;
  final String? directionId;
  final String? directionName;
  final List<String> directionCycleIds;
  final bool legacyDirectionScope;
  final String? createdAt;
  final String? lastLoginAt;
  final String? subject;
  final String? className;
  final List<String>? childrenIds;
  AccountStatus status;
  bool passwordSet;
  bool mustChangePassword;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    String? roleName,
    String? initials,
    this.schoolId,
    this.establishment,
    this.phone,
    this.establishmentStatus,
    this.directionId,
    this.directionName,
    this.directionCycleIds = const [],
    this.legacyDirectionScope = false,
    this.createdAt,
    this.lastLoginAt,
    this.subject,
    this.className,
    this.childrenIds,
    this.status = AccountStatus.active,
    this.passwordSet = true,
    this.mustChangePassword = false,
  })  : roleName = roleName ?? role.label,
        initials = initials ?? _computeInitials(name);

  static String _computeInitials(String name) {
    if (name.isEmpty) return 'U';
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  /// Créer depuis un Map JSON (compatible localStorage JS)
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      role: UserRole.fromValue(json['role']),
      roleName: json['roleName'],
      initials: json['initials'],
      schoolId: json['schoolId'],
      establishment: json['establishment'] is Map
          ? json['establishment']['name']
          : json['establishment'],
      phone: json['phone'],
      establishmentStatus: json['establishment'] is Map
          ? json['establishment']['status']
          : json['establishmentStatus'],
      directionId: json['directionId']?.toString(),
      directionName: json['direction'] is Map
          ? json['direction']['name']?.toString()
          : null,
      directionCycleIds: json['direction'] is Map
          ? List<String>.from((json['direction']['cycles'] as List? ?? const [])
              .map((cycle) => (cycle as Map)['id'].toString()))
          : const [],
      legacyDirectionScope: json['legacyDirectionScope'] == true,
      createdAt: json['createdAt'],
      lastLoginAt: json['lastLoginAt'],
      subject: json['subject'],
      className: json['class'],
      childrenIds:
          json['children'] != null ? List<String>.from(json['children']) : null,
      status: AccountStatus.fromValue(json['status']),
      passwordSet: json['passwordSet'] ?? true,
      mustChangePassword: json['mustChangePassword'] ?? false,
    );
  }

  /// Convertir en Map JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'role': role.value,
      'roleName': roleName,
      'initials': initials,
      'schoolId': schoolId,
      'establishment': establishment,
      'phone': phone,
      'establishmentStatus': establishmentStatus,
      'directionId': directionId,
      'direction': directionId == null
          ? null
          : {
              'id': directionId,
              'name': directionName,
              'cycles': directionCycleIds.map((id) => {'id': id}).toList(),
            },
      'legacyDirectionScope': legacyDirectionScope,
      'createdAt': createdAt,
      'lastLoginAt': lastLoginAt,
      'subject': subject,
      'class': className,
      'children': childrenIds,
      'status': status.value,
      'passwordSet': passwordSet,
      'mustChangePassword': mustChangePassword,
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    UserRole? role,
    String? roleName,
    String? initials,
    String? schoolId,
    String? establishment,
    String? phone,
    String? establishmentStatus,
    String? directionId,
    String? directionName,
    List<String>? directionCycleIds,
    bool? legacyDirectionScope,
    String? createdAt,
    String? lastLoginAt,
    String? subject,
    String? className,
    List<String>? childrenIds,
    AccountStatus? status,
    bool? passwordSet,
    bool? mustChangePassword,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      roleName: roleName ?? this.roleName,
      initials: initials ?? this.initials,
      schoolId: schoolId ?? this.schoolId,
      establishment: establishment ?? this.establishment,
      phone: phone ?? this.phone,
      establishmentStatus: establishmentStatus ?? this.establishmentStatus,
      directionId: directionId ?? this.directionId,
      directionName: directionName ?? this.directionName,
      directionCycleIds: directionCycleIds ?? this.directionCycleIds,
      legacyDirectionScope: legacyDirectionScope ?? this.legacyDirectionScope,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      subject: subject ?? this.subject,
      className: className ?? this.className,
      childrenIds: childrenIds ?? this.childrenIds,
      status: status ?? this.status,
      passwordSet: passwordSet ?? this.passwordSet,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    );
  }
}
