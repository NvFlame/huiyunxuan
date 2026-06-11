import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

    switch (config.searchProvider) {
      case ApiConfig.searchProviderTavily:
        return _searchTavily(config: config, query: trimmedQuery);
      case ApiConfig.searchProviderBocha:
        return _searchBocha(config: config, query: trimmedQuery);
      default:
        throw SearchRequestException(
          message: '暂不支持搜索服务：${config.searchProvider}',
        );
    }
  }

  Future<WebSearchResult> _searchTavily({
    required ApiConfig config,
    required String query,
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

      request.write(
        jsonEncode({
          'query': query,
          'topic': 'general',
          'search_depth': 'basic',
          'include_answer': true,
          'include_raw_content': config.searchIncludeRawContent,
          'include_images': false,
          'max_results': config.searchMaxResults,
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
          'query': query,
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

      return WebSearchResult.fromBochaMap(query: query, map: decoded);
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

  String toPromptText() {
    final lines = <String>[
      '搜索关键词：$query',
      if (answer.trim().isNotEmpty) '搜索摘要：$answer',
    ];

    for (var index = 0; index < documents.length; index += 1) {
      final document = documents[index];
      final content = document.bestContent;
      lines
        ..add('')
        ..add('来源 ${index + 1}：${document.title}')
        ..add('URL：${document.url}');
      if (content.isNotEmpty) {
        lines.add('内容：${_compact(content, maxLength: 900)}');
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
