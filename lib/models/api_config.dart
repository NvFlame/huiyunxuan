class ApiConfig {
  const ApiConfig({
    this.id,
    required this.name,
    this.apiSpec = openAiSpec,
    required this.apiKey,
    required this.baseUrl,
    required this.chatModel,
    this.embeddingModel = '',
    this.searchProvider = searchProviderNone,
    this.tavilySearchApiKey = '',
    this.bochaSearchApiKey = '',
    this.searchMaxResults = 5,
    this.searchIncludeRawContent = false,
    this.isActive = false,
    required this.createdAt,
    required this.updatedAt,
  });

  static const openAiSpec = 'OpenAI';
  static const searchProviderNone = 'none';
  static const searchProviderTavily = 'Tavily';
  static const searchProviderBocha = 'Bocha';

  final int? id;
  final String name;
  final String apiSpec;
  final String apiKey;
  final String baseUrl;
  final String chatModel;
  final String embeddingModel;
  final String searchProvider;
  final String tavilySearchApiKey;
  final String bochaSearchApiKey;
  final int searchMaxResults;
  final bool searchIncludeRawContent;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isSearchEnabled {
    return (searchProvider == searchProviderTavily ||
            searchProvider == searchProviderBocha) &&
        searchApiKey.trim().isNotEmpty;
  }

  String get searchApiKey {
    switch (searchProvider) {
      case searchProviderTavily:
        return tavilySearchApiKey;
      case searchProviderBocha:
        return bochaSearchApiKey;
      default:
        return '';
    }
  }

  ApiConfig copyWith({
    int? id,
    String? name,
    String? apiSpec,
    String? apiKey,
    String? baseUrl,
    String? chatModel,
    String? embeddingModel,
    String? searchProvider,
    String? tavilySearchApiKey,
    String? bochaSearchApiKey,
    int? searchMaxResults,
    bool? searchIncludeRawContent,
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
      searchProvider: searchProvider ?? this.searchProvider,
      tavilySearchApiKey: tavilySearchApiKey ?? this.tavilySearchApiKey,
      bochaSearchApiKey: bochaSearchApiKey ?? this.bochaSearchApiKey,
      searchMaxResults: searchMaxResults ?? this.searchMaxResults,
      searchIncludeRawContent:
          searchIncludeRawContent ?? this.searchIncludeRawContent,
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

  String get maskedSearchApiKey {
    final trimmed = searchApiKey.trim();
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
      'search_provider': searchProvider,
      'search_api_key': searchApiKey,
      'tavily_search_api_key': tavilySearchApiKey,
      'bocha_search_api_key': bochaSearchApiKey,
      'search_max_results': searchMaxResults,
      'search_include_raw_content': searchIncludeRawContent ? 1 : 0,
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
      searchProvider:
          (map['search_provider'] as String?) ?? searchProviderNone,
      tavilySearchApiKey: (map['tavily_search_api_key'] as String?) ??
          _legacySearchApiKeyForProvider(map, searchProviderTavily),
      bochaSearchApiKey: (map['bocha_search_api_key'] as String?) ??
          _legacySearchApiKeyForProvider(map, searchProviderBocha),
      searchMaxResults: (map['search_max_results'] as int?) ?? 5,
      searchIncludeRawContent:
          ((map['search_include_raw_content'] as int?) ?? 0) == 1,
      isActive: ((map['is_active'] as int?) ?? 0) == 1,
      createdAt: _dateFromMap(map['created_at']),
      updatedAt: _dateFromMap(map['updated_at']),
    );
  }
}

String _legacySearchApiKeyForProvider(
  Map<String, Object?> map,
  String provider,
) {
  final searchProvider = (map['search_provider'] as String?) ??
      ApiConfig.searchProviderNone;
  if (searchProvider != provider) {
    return '';
  }
  return (map['search_api_key'] as String?) ?? '';
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
