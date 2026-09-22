class PlanModel {
  const PlanModel({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.durationDays,
    required this.currency,
    required this.status,
    required this.features,
    required this.limits,
    required this.subscriptionCount,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final int price;
  final int durationDays;
  final String currency;
  final String status;
  final List<String> features;
  final Map<String, dynamic> limits;
  final int subscriptionCount;
  final String? createdAt;
  final String? updatedAt;

  bool get isActive => status == 'active';

  static int _intFromJson(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final normalized = value.trim().replaceAll(RegExp(r'[^0-9,.-]'), '').replaceAll(',', '.');
      if (normalized.isEmpty || normalized == '-' || normalized == '.') return 0;
      return num.tryParse(normalized)?.toInt() ?? 0;
    }
    return 0;
  }

  static List<String> _stringListFromJson(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String) {
      return value
          .split(RegExp(r'[\n,;]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static Map<String, dynamic> _mapFromJson(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  factory PlanModel.fromJson(Map<String, dynamic> json) => PlanModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        price: _intFromJson(json['price']),
        durationDays: _intFromJson(json['durationDays'] ?? json['duration_days']),
        currency: json['currency']?.toString() ?? 'FCFA',
        status: json['status']?.toString() ?? 'inactive',
        features: _stringListFromJson(json['features']),
        limits: _mapFromJson(json['limits']),
        subscriptionCount: _intFromJson(json['subscriptionCount'] ?? json['subscription_count']),
        createdAt: json['createdAt']?.toString(),
        updatedAt: json['updatedAt']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'price': price,
        'duration_days': durationDays,
        'currency': currency,
        'status': status,
        'features': features,
        'limits': limits,
      };

  PlanModel copyWith({
    String? name,
    String? description,
    int? price,
    int? durationDays,
    String? currency,
    String? status,
    List<String>? features,
    Map<String, dynamic>? limits,
    int? subscriptionCount,
  }) =>
      PlanModel(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        price: price ?? this.price,
        durationDays: durationDays ?? this.durationDays,
        currency: currency ?? this.currency,
        status: status ?? this.status,
        features: features ?? this.features,
        limits: limits ?? this.limits,
        subscriptionCount: subscriptionCount ?? this.subscriptionCount,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
