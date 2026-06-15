import 'dart:convert';

import '../models/api_config.dart';
import '../models/poem.dart';
import 'openai_api_service.dart';
import 'prosody_override_service.dart';
import 'rhyme_book_data.dart';
import 'rhyme_service.dart';

class ProsodyAiService {
  const ProsodyAiService({this.apiService = const OpenAiApiService()});

  final OpenAiApiService apiService;

  Future<String> calibrate({
    required ApiConfig config,
    required Poem poem,
  }) async {
    final candidates = findProsodyCalibrationCandidates(poem);
    if (candidates.isEmpty) {
      return poem.prosodyOverridesJson;
    }

    final content = await apiService.createChatCompletion(
      config: config,
      temperature: 0,
      messages: [
        {
          'role': 'system',
          'content': _systemPrompt,
        },
        {
          'role': 'user',
          'content': _buildUserPrompt(poem, candidates),
        },
      ],
    );

    final overrides = _parseOverrides(content, candidates);
    final current = ProsodyOverrideStore.parse(poem.prosodyOverridesJson);
    return current.putAll(overrides).toJsonText();
  }

  String _buildUserPrompt(
    Poem poem,
    List<ProsodyCalibrationCandidate> candidates,
  ) {
    final candidateLines = candidates.map((candidate) {
      final options = candidate.matches.isEmpty
          ? '无本地韵书候选'
          : candidate.matches
              .map((entry) =>
                  '${entry.label}/${entry.tone == RhymeTone.level ? '平' : '仄'}')
              .join('，');
      return '- line=${candidate.lineNumber}, char_index=${candidate.charIndex}, '
          'char=${candidate.character}, is_rhyme_foot=${candidate.isRhymeFoot}, '
          'current=${candidate.currentTone}, options=$options';
    }).join('\n');

    return '''
请为这首诗词中平仄或韵部未定的候选字做校准。

标题：${poem.title}
作者：${poem.author}
朝代：${poem.dynasty}
体式：${poem.prosodyForm}
韵书：${poem.prosodyRhymeBook}

正文：
${poem.content}

候选字：
$candidateLines
''';
  }

  List<ProsodyCharacterOverride> _parseOverrides(
    String text,
    List<ProsodyCalibrationCandidate> candidates,
  ) {
    final jsonText = _extractJson(text);
    if (jsonText == null) {
      throw const FormatException('模型没有返回 JSON。');
    }
    final decoded = jsonDecode(jsonText);
    Object? rawItems;
    if (decoded is List) {
      rawItems = decoded;
    } else if (decoded is Map<String, Object?>) {
      rawItems = decoded['items'] ?? decoded['characters'];
    } else if (decoded is Map) {
      rawItems = decoded['items'] ?? decoded['characters'];
    }
    if (rawItems is! List) {
      throw const FormatException('JSON 中没有 items 数组。');
    }

    final candidatesByKey = {
      for (final candidate in candidates) candidate.key: candidate,
    };
    final overrides = <ProsodyCharacterOverride>[];
    for (final item in rawItems) {
      final override = ProsodyCharacterOverride.fromJson(item);
      if (override == null) {
        continue;
      }
      final candidate = candidatesByKey[override.key];
      if (candidate == null || candidate.character != override.character) {
        continue;
      }
      overrides.add(override);
    }
    if (overrides.isEmpty) {
      throw const FormatException('模型没有返回可用的校准项。');
    }
    return overrides;
  }

  String? _extractJson(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return trimmed;
    }
    final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(trimmed);
    if (fenced != null) {
      return fenced.group(1)?.trim();
    }
    final objectStart = trimmed.indexOf('{');
    final objectEnd = trimmed.lastIndexOf('}');
    if (objectStart >= 0 && objectEnd > objectStart) {
      return trimmed.substring(objectStart, objectEnd + 1);
    }
    final arrayStart = trimmed.indexOf('[');
    final arrayEnd = trimmed.lastIndexOf(']');
    if (arrayStart >= 0 && arrayEnd > arrayStart) {
      return trimmed.substring(arrayStart, arrayEnd + 1);
    }
    return null;
  }
}

const _systemPrompt = '''
你是古典诗词音韵校准助手。任务是根据字义、词法、上下文和古音知识，判断候选多音字的平仄和韵部。

重要原则：
1. 不能为了让韵脚统一而强行改变读音；必须先按字义和语法判断读音。
2. 如果候选字在该处语义明确，应给出 tone 和 rhyme；如果仍不能确定，tone 写“多”，rhyme 留空。
3. tone 只能写“平”“仄”“多”之一。
4. rhyme 使用候选韵部中的原文标签，例如“上声二十二养”“去声二十三漾”“十一尤”等；无法确定则留空。
5. 如果同一首诗的韵脚实际分属多个韵部，应按每个字自身读音分别填写，不要强行统一。
6. 例如“复照青苔上”中的“上”是方位词，应按“上面”的去声义处理，而不是为了押韵强行读上声。

只返回 JSON，不要 Markdown，不要解释 JSON 之外的文字。
格式：
{"items":[{"line":2,"char_index":5,"char":"字","tone":"仄","rhyme":"上声二十二养","note":"简短依据"}]}
''';
