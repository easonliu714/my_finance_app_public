class MerchantRecord {
  MerchantRecord({
    required this.id,
    required this.name,
    this.alias = '',
    this.sellerIdentifier = '',
    this.note = '',
    this.isArchived = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? _defaultEpoch,
        updatedAt = updatedAt ?? _defaultEpoch;

  static final DateTime _defaultEpoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  final String id;
  final String name;
  final String alias;
  final String sellerIdentifier;
  final String note;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayName => alias.trim().isEmpty ? name.trim() : '${name.trim()}・${alias.trim()}';

  MerchantRecord copyWith({
    String? id,
    String? name,
    String? alias,
    String? sellerIdentifier,
    String? note,
    bool? isArchived,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MerchantRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      alias: alias ?? this.alias,
      sellerIdentifier: sellerIdentifier ?? this.sellerIdentifier,
      note: note ?? this.note,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'alias': alias,
      'seller_identifier': sellerIdentifier,
      'note': note,
      'is_archived': isArchived,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory MerchantRecord.fromJson(Map<String, Object?> json) {
    return MerchantRecord(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      alias: json['alias'] as String? ?? '',
      sellerIdentifier: json['seller_identifier'] as String? ?? '',
      note: json['note'] as String? ?? '',
      isArchived: json['is_archived'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? _defaultEpoch,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? _defaultEpoch,
    );
  }
}
