class ApiConfig {
  const ApiConfig({
    this.id,
    required this.name,
    this.apiSpec = openAiSpec,
    required this.apiKey,
    required this.baseUrl,
    required this.chatModel,
    this.embeddingModel = '',
    this.isActive = false,
    required this.createdAt,
    required this.updatedAt,
  });

  static const openAiSpec = 'OpenAI';

  final int? id;
  final String name;
  final String apiSpec;
  final String apiKey;
  final String baseUrl;
  final String chatModel;
  final String embeddingModel;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  ApiConfig copyWith({
    int? id,
    String? name,
    String? apiSpec,
    String? apiKey,
    String? baseUrl,
    String? chatModel,
    String? embeddingModel,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ApiConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      apiSpec: apiSpec ?? this.apiSpec,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      chatModel: chatModel ?? this.chatModel,
      embeddingModel: embeddingModel ?? this.embeddingModel,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get maskedApiKey {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      return '未填写';
    }
    if (trimmed.length <= 10) {
      return '••••••';
    }
    return '${trimmed.substring(0, 5)}...${trimmed.substring(trimmed.length - 4)}';
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'api_spec': apiSpec,
      'api_key': apiKey,
      'base_url': baseUrl,
      'chat_model': chatModel,
      'embedding_model': embeddingModel,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory ApiConfig.fromMap(Map<String, Object?> map) {
    return ApiConfig(
      id: map['id'] as int?,
      name: map['name'] as String,
      apiSpec: (map['api_spec'] as String?) ?? openAiSpec,
      apiKey: (map['api_key'] as String?) ?? '',
      baseUrl: (map['base_url'] as String?) ?? '',
      chatModel: (map['chat_model'] as String?) ?? '',
      embeddingModel: (map['embedding_model'] as String?) ?? '',
      isActive: ((map['is_active'] as int?) ?? 0) == 1,
      createdAt: _dateFromMap(map['created_at']),
      updatedAt: _dateFromMap(map['updated_at']),
    );
  }
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
