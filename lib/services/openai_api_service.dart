import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/api_config.dart';

class OpenAiApiService {
  const OpenAiApiService();

  Future<List<String>> fetchModels(ApiConfig config) async {
    final response = await _request(
      config: config,
      method: 'GET',
      path: '/models',
    );
    final data = response['data'];
    if (data is! List) {
      throw const ApiRequestException(message: '响应中没有 data 模型列表。');
    }

    final modelIds = data
        .map((item) {
          if (item is Map<String, Object?>) {
            return item['id'];
          }
          if (item is Map) {
            return item['id'];
          }
          return null;
        })
        .whereType<String>()
        .toList()
      ..sort();

    if (modelIds.isEmpty) {
      throw const ApiRequestException(message: '模型列表为空，或响应格式不兼容。');
    }
    return modelIds;
  }

  Future<ApiTestResult> testChat(ApiConfig config) async {
    final response = await _request(
      config: config,
      method: 'POST',
      path: '/chat/completions',
      body: {
        'model': config.chatModel,
        'messages': const [
          {
            'role': 'user',
            'content': '请只回复：绘云轩API测试成功',
          },
        ],
      },
    );

    final choices = response['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const ApiRequestException(message: '请求成功，但响应中没有 choices。');
    }

    final firstChoice = choices.first;
    Object? content;
    if (firstChoice is Map<String, Object?>) {
      final message = firstChoice['message'];
      if (message is Map<String, Object?>) {
        content = message['content'];
      }
    } else if (firstChoice is Map) {
      final message = firstChoice['message'];
      if (message is Map) {
        content = message['content'];
      }
    }

    return ApiTestResult(
      model: (response['model'] as String?) ?? config.chatModel,
      message: _readContent(content),
    );
  }

  Future<String> createChatCompletion({
    required ApiConfig config,
    required List<Map<String, String>> messages,
    double temperature = 0.2,
  }) async {
    final response = await _request(
      config: config,
      method: 'POST',
      path: '/chat/completions',
      body: {
        'model': config.chatModel,
        'messages': messages,
        'temperature': temperature,
      },
    );

    final choices = response['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const ApiRequestException(message: '请求成功，但响应中没有 choices。');
    }

    final firstChoice = choices.first;
    Object? content;
    if (firstChoice is Map<String, Object?>) {
      final message = firstChoice['message'];
      if (message is Map<String, Object?>) {
        content = message['content'];
      }
    } else if (firstChoice is Map) {
      final message = firstChoice['message'];
      if (message is Map) {
        content = message['content'];
      }
    }

    return _readContent(content);
  }

  Future<Map<String, Object?>> _request({
    required ApiConfig config,
    required String method,
    required String path,
    Map<String, Object?>? body,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .openUrl(method, _buildUri(config.baseUrl, path))
          .timeout(const Duration(seconds: 15));
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer ${config.apiKey}')
        ..set(HttpHeaders.acceptHeader, 'application/json');

      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(
            const Duration(seconds: 45),
          );
      final responseText = await response.transform(utf8.decoder).join();
      final decoded = _decodeObject(responseText);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiRequestException(
          statusCode: response.statusCode,
          message: _extractErrorMessage(decoded) ??
              'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          details: responseText,
        );
      }

      return decoded;
    } on ApiRequestException {
      rethrow;
    } on TimeoutException catch (error) {
      throw ApiRequestException(message: '请求超时：$error');
    } on SocketException catch (error) {
      throw ApiRequestException(message: '网络连接失败：${error.message}');
    } on HandshakeException catch (error) {
      throw ApiRequestException(message: 'TLS/证书握手失败：$error');
    } on FormatException catch (error) {
      throw ApiRequestException(message: '响应不是有效 JSON：${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  Uri _buildUri(String baseUrl, String path) {
    var normalizedBase = baseUrl.trim();
    while (normalizedBase.endsWith('/')) {
      normalizedBase = normalizedBase.substring(0, normalizedBase.length - 1);
    }

    final uri = Uri.parse('$normalizedBase$path');
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw const ApiRequestException(message: 'API 基础 URL 无效。');
    }
    return uri;
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
    return null;
  }

  String _readContent(Object? content) {
    if (content is String && content.trim().isNotEmpty) {
      return content.trim();
    }
    if (content is List) {
      final parts = content
          .map((part) {
            if (part is Map<String, Object?>) {
              return part['text'];
            }
            if (part is Map) {
              return part['text'];
            }
            return null;
          })
          .whereType<String>()
          .where((part) => part.trim().isNotEmpty)
          .toList();
      if (parts.isNotEmpty) {
        return parts.join('\n').trim();
      }
    }
    return '请求成功，但响应中没有文本内容。';
  }
}

class ApiTestResult {
  const ApiTestResult({required this.model, required this.message});

  final String model;
  final String message;
}

class ApiRequestException implements Exception {
  const ApiRequestException({
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
