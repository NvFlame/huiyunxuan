class PoemCollection {
  const PoemCollection({
    this.id,
    required this.name,
    this.description = '',
    this.isFavorites = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final String description;
  final bool isFavorites;
  final DateTime createdAt;
  final DateTime updatedAt;

  PoemCollection copyWith({
    int? id,
    String? name,
    String? description,
    bool? isFavorites,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PoemCollection(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isFavorites: isFavorites ?? this.isFavorites,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'description': description,
      'is_favorites': isFavorites ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory PoemCollection.fromMap(Map<String, Object?> map) {
    return PoemCollection(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: (map['description'] as String?) ?? '',
      isFavorites: _boolFromMap(map['is_favorites']),
      createdAt: _dateFromMap(map['created_at']),
      updatedAt: _dateFromMap(map['updated_at']),
    );
  }
}

bool _boolFromMap(Object? value) {
  if (value is int) {
    return value != 0;
  }
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return value == '1' || value.toLowerCase() == 'true';
  }
  return false;
}

DateTime _dateFromMap(Object? value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  return DateTime.now();
}
