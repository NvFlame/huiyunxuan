import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/api_config.dart';

class WebSearchService {
  const WebSearchService();

  Future<WebSearchResult> search({
    required ApiConfig config,
    required String query,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      throw const SearchRequestException(message: '搜索关键词为空。');
    }
    if (!config.isSearchEnabled) {
      throw const SearchRequestException(message: '当前 API 配置没有启用联网搜索。');
    }

    try {
      final authorityResult = await _searchWithProvider(
        config: config,
        query: trimmedQuery,
        authorityOnly: true,
      );
      final prioritizedAuthorityResult =
          authorityResult.prioritizeAuthoritySources(query: trimmedQuery);
      if (prioritizedAuthorityResult.hasAuthorityDocuments) {
        return _enrichAuthorityDocuments(prioritizedAuthorityResult);
      }
    } on SearchRequestException {
      // If the authority-only pass fails, fall back to the normal web search.
    }

    final fallbackResult = await _searchWithProvider(
      config: config,
      query: trimmedQuery,
    );
    final prioritizedFallbackResult = WebSearchResult.merge(
      query: trimmedQuery,
      results: [
        fallbackResult,
      ],
    ).prioritizeAuthoritySources(query: trimmedQuery);
    return _enrichAuthorityDocuments(prioritizedFallbackResult);
  }

  Future<WebSearchResult> _searchWithProvider({
    required ApiConfig config,
    required String query,
    bool authorityOnly = false,
  }) {
    switch (config.searchProvider) {
      case ApiConfig.searchProviderTavily:
        return _searchTavily(
          config: config,
          query: query,
          authorityOnly: authorityOnly,
        );
      case ApiConfig.searchProviderBocha:
        if (authorityOnly) {
          return _searchBochaAuthority(config: config, query: query);
        }
        return _searchBocha(
          config: config,
          query: query,
          authorityOnly: authorityOnly,
        );
      default:
        throw SearchRequestException(
          message: '暂不支持搜索服务：${config.searchProvider}',
        );
    }
  }

  Future<WebSearchResult> _searchTavily({
    required ApiConfig config,
    required String query,
    bool authorityOnly = false,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);

    try {
      final request = await client
          .postUrl(Uri.parse('https://api.tavily.com/search'))
          .timeout(const Duration(seconds: 15));
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer ${config.searchApiKey}')
        ..set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.contentType = ContentType.json;

      final payload = <String, Object?>{
        'query': query,
        'topic': 'general',
        'search_depth': 'basic',
        'include_answer': true,
        'include_raw_content': config.searchIncludeRawContent,
        'include_images': false,
        'max_results': config.searchMaxResults,
        if (authorityOnly) 'include_domains': _authorityDomains,
      };

      request.write(jsonEncode(payload));

      final response = await request.close().timeout(
            const Duration(seconds: 45),
          );
      final responseText = await response.transform(utf8.decoder).join();
      final decoded = _decodeObject(responseText);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SearchRequestException(
          statusCode: response.statusCode,
          message: _extractErrorMessage(decoded) ??
              'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          details: responseText,
        );
      }

      return WebSearchResult.fromMap(query: query, map: decoded);
    } on SearchRequestException {
      rethrow;
    } on TimeoutException catch (error) {
      throw SearchRequestException(message: '搜索请求超时：$error');
    } on SocketException catch (error) {
      throw SearchRequestException(message: '搜索网络连接失败：${error.message}');
    } on HandshakeException catch (error) {
      throw SearchRequestException(message: '搜索 TLS/证书握手失败：$error');
    } on FormatException catch (error) {
      throw SearchRequestException(message: '搜索响应不是有效 JSON：${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<WebSearchResult> _searchBocha({
    required ApiConfig config,
    required String query,
    bool authorityOnly = false,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);

    try {
      final request = await client
          .postUrl(Uri.parse('https://api.bochaai.com/v1/web-search'))
          .timeout(const Duration(seconds: 15));
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer ${config.searchApiKey}')
        ..set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.contentType = ContentType.json;

      request.write(
        jsonEncode({
          'query': authorityOnly ? _authorityQuery(query) : query,
          'summary': true,
          'count': config.searchMaxResults,
        }),
      );

      final response = await request.close().timeout(
            const Duration(seconds: 45),
          );
      final responseText = await response.transform(utf8.decoder).join();
      final decoded = _decodeObject(responseText);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SearchRequestException(
          statusCode: response.statusCode,
          message: _extractErrorMessage(decoded) ??
              'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          details: responseText,
        );
      }

      final rawCode = decoded['code'];
      final code = _readInt(rawCode);
      if (rawCode != null && code != 200) {
        throw SearchRequestException(
          statusCode: code,
          message: _extractErrorMessage(decoded) ?? '博查搜索请求失败。',
          details: responseText,
        );
      }

      return WebSearchResult.fromBochaMap(
        query: authorityOnly ? _authorityQuery(query) : query,
        map: decoded,
      );
    } on SearchRequestException {
      rethrow;
    } on TimeoutException catch (error) {
      throw SearchRequestException(message: '搜索请求超时：$error');
    } on SocketException catch (error) {
      throw SearchRequestException(message: '搜索网络连接失败：${error.message}');
    } on HandshakeException catch (error) {
      throw SearchRequestException(message: '搜索 TLS/证书握手失败：$error');
    } on FormatException catch (error) {
      throw SearchRequestException(message: '搜索响应不是有效 JSON：${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<WebSearchResult> _searchBochaAuthority({
    required ApiConfig config,
    required String query,
  }) async {
    final results = <WebSearchResult>[];
    SearchRequestException? lastError;

    for (final domain in _bochaAuthorityDomains) {
      try {
        final result = await _searchBocha(
          config: config,
          query: '$query site:$domain',
        );
        results.add(result);
        if (result.hasAuthorityDocuments) {
          break;
        }
      } on SearchRequestException catch (error) {
        lastError = error;
      }
    }

    if (results.isEmpty && lastError != null) {
      throw lastError;
    }

    return WebSearchResult.merge(query: query, results: results);
  }

  Future<WebSearchResult> _enrichAuthorityDocuments(
    WebSearchResult result,
  ) async {
    var fetchedCount = 0;
    final documents = <WebSearchDocument>[];

    for (final document in result.documents) {
      if (_authorityPriority(document.url) <= 0 ||
          fetchedCount >= _authorityFetchLimit) {
        documents.add(document);
        continue;
      }

      fetchedCount += 1;
      final fetchedText = await _fetchReadablePageText(document.url);
      if (fetchedText.trim().isEmpty ||
          fetchedText.length <= document.bestContent.length) {
        documents.add(document);
        continue;
      }

      documents.add(document.copyWith(rawContent: fetchedText));
    }

    return result.copyWith(documents: List.unmodifiable(documents));
  }

  Future<String> _fetchReadablePageText(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return '';
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.getUrl(uri).timeout(
            const Duration(seconds: 10),
          );
      request.headers
        ..set(
          HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
        )
        ..set(
          HttpHeaders.acceptHeader,
          'text/html,application/xhtml+xml,application/xml;q=0.9,text/plain;q=0.8,*/*;q=0.7',
        );

      final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return '';
      }

      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (bytes.length >= _authorityFetchMaxBytes) {
          break;
        }
        final remaining = _authorityFetchMaxBytes - bytes.length;
        bytes.add(chunk.length <= remaining ? chunk : chunk.sublist(0, remaining));
      }

      final html = utf8.decode(bytes.takeBytes(), allowMalformed: true);
      return _htmlToReadableText(html);
    } on Object {
      return '';
    } finally {
      client.close(force: true);
    }
  }
}

class WebSearchResult {
  const WebSearchResult({
    required this.query,
    this.answer = '',
    this.documents = const <WebSearchDocument>[],
  });

  final String query;
  final String answer;
  final List<WebSearchDocument> documents;

  bool get isEmpty => answer.trim().isEmpty && documents.isEmpty;

  WebSearchResult copyWith({
    String? query,
    String? answer,
    List<WebSearchDocument>? documents,
  }) {
    return WebSearchResult(
      query: query ?? this.query,
      answer: answer ?? this.answer,
      documents: documents ?? this.documents,
    );
  }

  bool get hasAuthorityDocuments {
    return documents.any((document) => _authorityPriority(document.url) > 0);
  }

  WebSearchResult prioritizeAuthoritySources({required String query}) {
    final indexedDocuments = [
      for (var index = 0; index < documents.length; index += 1)
        MapEntry(index, documents[index]),
    ];
    indexedDocuments.sort((left, right) {
      final leftPriority = _authorityPriority(left.value.url);
      final rightPriority = _authorityPriority(right.value.url);
      if (leftPriority != rightPriority) {
        return rightPriority.compareTo(leftPriority);
      }
      final leftScore = left.value.score ?? 0;
      final rightScore = right.value.score ?? 0;
      if (leftScore != rightScore) {
        return rightScore.compareTo(leftScore);
      }
      return left.key.compareTo(right.key);
    });

    return WebSearchResult(
      query: query,
      answer: answer,
      documents: List.unmodifiable([
        for (final entry in indexedDocuments) entry.value,
      ]),
    );
  }

  factory WebSearchResult.merge({
    required String query,
    required List<WebSearchResult> results,
  }) {
    final documents = <WebSearchDocument>[];
    final seenUrls = <String>{};
    final answers = <String>[];

    for (final result in results) {
      final answer = result.answer.trim();
      if (answer.isNotEmpty && !answers.contains(answer)) {
        answers.add(answer);
      }
      for (final document in result.documents) {
        final normalizedUrl = document.url.trim().toLowerCase();
        if (normalizedUrl.isEmpty || seenUrls.add(normalizedUrl)) {
          documents.add(document);
        }
      }
    }

    return WebSearchResult(
      query: query,
      answer: answers.join('\n'),
      documents: List.unmodifiable(documents),
    );
  }

  String toPromptText() {
    final lines = <String>[
      '搜索关键词：$query',
      '来源优先级：优先采信古文岛、古诗文库、百度百科、百度汉语、维基文库、中华诗词等资料；新闻、论坛、泛内容站只能作辅助，不能与权威来源冲突。',
      if (answer.trim().isNotEmpty) '搜索摘要：$answer',
    ];

    for (var index = 0; index < documents.length; index += 1) {
      final document = documents[index];
      final content = document.bestContent;
      final sourceLabel = _authorityLabel(document.url);
      final maxLength = sourceLabel == null
          ? _normalPromptContentMaxLength
          : _authorityPromptContentMaxLength;
      lines
        ..add('')
        ..add(
          '来源 ${index + 1}${sourceLabel == null ? '' : '（$sourceLabel）'}：${document.title}',
        )
        ..add('URL：${document.url}');
      if (content.isNotEmpty) {
        lines.add('内容：${_compact(content, maxLength: maxLength)}');
      }
    }

    return lines.join('\n');
  }

  List<String> get sourceLines {
    return [
      for (final document in documents)
        if (document.url.trim().isNotEmpty)
          document.title.trim().isEmpty
              ? document.url.trim()
              : '${document.title.trim()}：${document.url.trim()}',
    ];
  }

  factory WebSearchResult.fromMap({
    required String query,
    required Map<String, Object?> map,
  }) {
    final rawResults = map['results'];
    final documents = <WebSearchDocument>[];
    if (rawResults is List) {
      for (final item in rawResults) {
        final itemMap = _readObjectMap(item);
        if (itemMap == null) {
          continue;
        }
        documents.add(WebSearchDocument.fromMap(itemMap));
      }
    }

    return WebSearchResult(
      query: query,
      answer: (map['answer'] as String?)?.trim() ?? '',
      documents: List.unmodifiable(documents),
    );
  }

  factory WebSearchResult.fromBochaMap({
    required String query,
    required Map<String, Object?> map,
  }) {
    final data = _readObjectMap(map['data']);
    final payload = data ?? map;
    final webPages = _readObjectMap(payload['webPages']);
    final rawValues = webPages?['value'];
    final documents = <WebSearchDocument>[];
    if (rawValues is List) {
      for (final item in rawValues) {
        final itemMap = _readObjectMap(item);
        if (itemMap == null) {
          continue;
        }
        documents.add(WebSearchDocument.fromBochaMap(itemMap));
      }
    }

    return WebSearchResult(
      query: query,
      documents: List.unmodifiable(documents),
    );
  }
}

class WebSearchDocument {
  const WebSearchDocument({
    required this.title,
    required this.url,
    this.content = '',
    this.rawContent = '',
    this.score,
  });

  final String title;
  final String url;
  final String content;
  final String rawContent;
  final double? score;

  String get bestContent {
    if (rawContent.trim().isNotEmpty) {
      return rawContent.trim();
    }
    return content.trim();
  }

  WebSearchDocument copyWith({
    String? title,
    String? url,
    String? content,
    String? rawContent,
    double? score,
  }) {
    return WebSearchDocument(
      title: title ?? this.title,
      url: url ?? this.url,
      content: content ?? this.content,
      rawContent: rawContent ?? this.rawContent,
      score: score ?? this.score,
    );
  }

  factory WebSearchDocument.fromMap(Map<String, Object?> map) {
    return WebSearchDocument(
      title: (map['title'] as String?)?.trim() ?? '',
      url: (map['url'] as String?)?.trim() ?? '',
      content: (map['content'] as String?)?.trim() ?? '',
      rawContent: (map['raw_content'] as String?)?.trim() ?? '',
      score: _readDouble(map['score']),
    );
  }

  factory WebSearchDocument.fromBochaMap(Map<String, Object?> map) {
    final summary = (map['summary'] as String?)?.trim() ?? '';
    final snippet = (map['snippet'] as String?)?.trim() ?? '';
    final siteName = (map['siteName'] as String?)?.trim() ?? '';
    final datePublished = (map['datePublished'] as String?)?.trim() ?? '';
    final contentParts = <String>[
      if (siteName.isNotEmpty) '站点：$siteName',
      if (datePublished.isNotEmpty) '发布时间：$datePublished',
      if (snippet.isNotEmpty) snippet,
    ];

    return WebSearchDocument(
      title: (map['name'] as String?)?.trim() ?? '',
      url: (map['url'] as String?)?.trim() ?? '',
      content: contentParts.join('\n'),
      rawContent: summary,
    );
  }
}

class SearchRequestException implements Exception {
  const SearchRequestException({
    required this.message,
    this.statusCode,
    this.details = '',
  });

  final String message;
  final int? statusCode;
  final String details;

  @override
  String toString() {
    final code = statusCode == null ? '' : 'HTTP $statusCode\n';
    return '$code$message';
  }
}

Map<String, Object?> _decodeObject(String responseText) {
  final decoded = jsonDecode(responseText);
  if (decoded is Map<String, Object?>) {
    return decoded;
  }
  if (decoded is Map) {
    return Map<String, Object?>.from(decoded);
  }
  throw const FormatException('顶层响应不是 JSON 对象');
}

Map<String, Object?>? _readObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return {
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return null;
}

String? _extractErrorMessage(Map<String, Object?> decoded) {
  final error = decoded['error'];
  if (error is Map<String, Object?>) {
    final message = error['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message;
    }
  }
  if (error is Map) {
    final message = error['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message;
    }
  }
  final message = decoded['message'];
  if (message is String && message.trim().isNotEmpty) {
    return message;
  }
  final msg = decoded['msg'];
  if (msg is String && msg.trim().isNotEmpty) {
    return msg;
  }
  return null;
}

double? _readDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

String _compact(String value, {required int maxLength}) {
  final compacted = value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join(' / ');

  if (compacted.length <= maxLength) {
    return compacted;
  }
  return '${compacted.substring(0, maxLength)}...';
}

String _htmlToReadableText(String html) {
  var text = html;
  text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
  text = text.replaceAll(
    RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false),
    ' ',
  );
  text = text.replaceAll(
    RegExp(r'<style\b[^>]*>[\s\S]*?</style>', caseSensitive: false),
    ' ',
  );
  text = text.replaceAll(
    RegExp(r'<noscript\b[^>]*>[\s\S]*?</noscript>', caseSensitive: false),
    ' ',
  );
  text = text.replaceAll(
    RegExp(r'<br\s*/?>', caseSensitive: false),
    '\n',
  );
  text = text.replaceAll(
    RegExp(
      r'</(p|div|section|article|h[1-6]|li|tr|table|blockquote|pre)>',
      caseSensitive: false,
    ),
    '\n',
  );
  text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
  text = _decodeHtmlEntities(text);
  text = text.replaceAll(RegExp(r'[ \t\u00A0]+'), ' ');
  return text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join('\n');
}

String _decodeHtmlEntities(String value) {
  var text = value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");

  text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
    final codePoint = int.tryParse(match.group(1) ?? '');
    if (codePoint == null) {
      return match.group(0) ?? '';
    }
    return String.fromCharCode(codePoint);
  });
  text = text.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
    final codePoint = int.tryParse(match.group(1) ?? '', radix: 16);
    if (codePoint == null) {
      return match.group(0) ?? '';
    }
    return String.fromCharCode(codePoint);
  });

  return text;
}

const _authorityFetchLimit = 3;
const _authorityFetchMaxBytes = 768 * 1024;
const _authorityPromptContentMaxLength = 6500;
const _normalPromptContentMaxLength = 1200;

const _authoritySources = <_AuthoritySource>[
  _AuthoritySource(label: '古文岛', domains: ['gushiwen.cn']),
  _AuthoritySource(label: '古诗文库', domains: ['gushiwenku.com']),
  _AuthoritySource(label: '百度百科', domains: ['baike.baidu.com']),
  _AuthoritySource(label: '百度汉语', domains: ['hanyu.baidu.com']),
  _AuthoritySource(label: '维基文库', domains: ['zh.wikisource.org']),
  _AuthoritySource(label: '中华诗词', domains: ['zhsc.net']),
  _AuthoritySource(label: '搜韵', domains: ['sou-yun.cn']),
  _AuthoritySource(label: '中国哲学书电子化计划', domains: ['ctext.org']),
];

final _authorityDomains = List.unmodifiable([
  for (final source in _authoritySources) ...source.domains,
]);

const _bochaAuthorityDomains = <String>[
  'gushiwen.cn',
  'baike.baidu.com',
  'hanyu.baidu.com',
  'sou-yun.cn',
  'zh.wikisource.org',
  'gushiwenku.com',
];

String _authorityQuery(String query) {
  final domainQuery = _authorityDomains
      .map((domain) => 'site:$domain')
      .join(' OR ');
  return '$query ($domainQuery)';
}

int _authorityPriority(String url) {
  final host = _hostFromUrl(url);
  if (host == null) {
    return 0;
  }

  for (var index = 0; index < _authoritySources.length; index += 1) {
    final source = _authoritySources[index];
    if (source.domains.any((domain) => _hostMatchesDomain(host, domain))) {
      return _authoritySources.length - index;
    }
  }
  return 0;
}

String? _authorityLabel(String url) {
  final host = _hostFromUrl(url);
  if (host == null) {
    return null;
  }

  for (final source in _authoritySources) {
    if (source.domains.any((domain) => _hostMatchesDomain(host, domain))) {
      return source.label;
    }
  }
  return null;
}

String? _hostFromUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(trimmed);
  final host = uri?.host.toLowerCase();
  if (host != null && host.isNotEmpty) {
    return host;
  }

  final withScheme = Uri.tryParse('https://$trimmed');
  final fallbackHost = withScheme?.host.toLowerCase();
  return fallbackHost == null || fallbackHost.isEmpty ? null : fallbackHost;
}

bool _hostMatchesDomain(String host, String domain) {
  final normalizedDomain = domain.toLowerCase();
  return host == normalizedDomain || host.endsWith('.$normalizedDomain');
}

class _AuthoritySource {
  const _AuthoritySource({required this.label, required this.domains});

  final String label;
  final List<String> domains;
}
