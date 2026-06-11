import 'dart:convert';

import '../models/api_config.dart';
import '../models/poem.dart';
import '../models/poem_collection.dart';
import 'openai_api_service.dart';
import 'web_search_service.dart';

class PoemAgentService {
  const PoemAgentService({
    this.apiService = const OpenAiApiService(),
    this.searchService = const WebSearchService(),
  });

  final OpenAiApiService apiService;
  final WebSearchService searchService;

  Future<PoemAgentResult> send({
    required ApiConfig config,
    required List<PoemAgentMessage> history,
    required List<PoemCollection> collections,
    required Map<int, List<Poem>> poemsByCollection,
    PoemCollection? currentCollection,
  }) async {
    final content = await apiService.createChatCompletion(
      config: config,
      messages: [
        {
          'role': 'system',
          'content': _buildSystemPrompt(
            collections: collections,
            poemsByCollection: poemsByCollection,
            currentCollection: currentCollection,
            searchAvailable: config.isSearchEnabled,
          ),
        },
        for (final message in history)
          {
            'role': message.role,
            'content': message.content,
          },
      ],
    );

    final initialResult = PoemAgentResult.fromJsonText(
      content,
      currentCollectionId: currentCollection?.id,
    );

    if (!initialResult.shouldSearch) {
      return initialResult;
    }

    if (!config.isSearchEnabled) {
      return const PoemAgentResult(
        type: 'ask',
        message: '当前 API 配置还没有启用联网搜索。请先在 API 管理中为当前配置填写 Tavily API Key，或补充可核验的资料。',
      );
    }

    final searchResult = await searchService.search(
      config: config,
      query: initialResult.searchQuery!,
    );
    if (searchResult.isEmpty) {
      return PoemAgentResult(
        type: 'not_found',
        message: '联网搜索没有返回可用结果，因此没有执行入库或修改。',
        searchQuery: initialResult.searchQuery,
        searchSources: searchResult.sourceLines,
      );
    }

    final finalContent = await apiService.createChatCompletion(
      config: config,
      messages: [
        {
          'role': 'system',
          'content': _buildSystemPrompt(
            collections: collections,
            poemsByCollection: poemsByCollection,
            currentCollection: currentCollection,
            searchAvailable: true,
            searchResult: searchResult,
          ),
        },
        for (final message in history)
          {
            'role': message.role,
            'content': message.content,
          },
        {
          'role': 'assistant',
          'content': content,
        },
        {
          'role': 'system',
          'content': 'App 已根据 query="${initialResult.searchQuery}" 完成联网搜索。'
              '请根据上方搜索结果返回最终 JSON，不要再次返回 search。',
        },
      ],
    );

    final finalResult = PoemAgentResult.fromJsonText(
      finalContent,
      currentCollectionId: currentCollection?.id,
      searchQuery: initialResult.searchQuery,
      searchSources: searchResult.sourceLines,
    );
    if (finalResult.shouldSearch) {
      return PoemAgentResult(
        type: 'ask',
        message: '我已经完成一次联网搜索，但仍无法唯一确认可执行结果。请补充作者、首句、目标诗词库或其它限定信息。',
        searchQuery: initialResult.searchQuery,
        searchSources: searchResult.sourceLines,
      );
    }
    return finalResult;
  }

  String _buildSystemPrompt({
    required List<PoemCollection> collections,
    required Map<int, List<Poem>> poemsByCollection,
    required PoemCollection? currentCollection,
    required bool searchAvailable,
    WebSearchResult? searchResult,
  }) {
    final collectionLines = collections.isEmpty
        ? '（暂无诗词库）'
        : collections.map((collection) {
            final description = collection.description.trim().isEmpty
                ? ''
                : '，说明：${collection.description.trim()}';
            return '- id=${collection.id}, 名称：${collection.name}$description';
          }).join('\n');

    final poemLines = _buildPoemLines(
      collections: collections,
      poemsByCollection: poemsByCollection,
      currentCollection: currentCollection,
    );

    final context = currentCollection == null
        ? '当前位于“诗词库管理”页面。用户若要添加诗词，必须明确目标诗词库；用户若要修改诗词，必须明确到一个本地 poem_id。'
        : '当前位于诗词库“${currentCollection.name}”（id=${currentCollection.id}）内部。添加诗词默认归入当前库；修改诗词只允许使用当前库清单中列出的 poem_id。';
    final searchState = searchResult == null
        ? searchAvailable
            ? '联网搜索已启用。若用户要求添加诗词、补充译文/注释/赏析或纠错，先确认目标库和诗词身份是否唯一；若仍不唯一则 ask，若已经唯一且本轮尚无搜索结果，则必须先返回 search 动作，让 App 先联网检索，不得直接 add_poem、add_poems 或 update_poem。'
            : '联网搜索未启用。不要声称已经联网搜索；如果需要外部核验，应 ask 用户配置联网搜索或补充资料。'
        : 'App 已完成联网搜索。你必须优先依据下方搜索结果返回最终动作，不得再次返回 search。若搜索结果不足、冲突或无法核验，应返回 ask 或 not_found。';
    final searchBlock = searchResult == null
        ? ''
        : '''

联网搜索结果：
${searchResult.toPromptText()}
''';

    return '''
你是“绘云轩”的诗词库助手，负责和用户反复确认诗词、目标诗词库与本地诗词元素，并在信息唯一时返回可执行动作。

$context

$searchState

可用诗词库：
$collectionLines

当前可编辑诗词清单（更新诗词时只能使用这里列出的 poem_id）：
$poemLines
$searchBlock

格式示例：
content:
岂无山歌与村笛？
呕哑嘲哳难为听。

translation:
难道没有山歌和村笛可以听吗？
只是那声音嘈杂刺耳，实在难以入耳。

annotation:
[1] 岂无：难道没有。
[1] 山歌与村笛：山野歌声和乡村笛声。
[2] 呕哑嘲哳：形容声音杂乱刺耳。

反例：如果 content 只有 4 个非空原文行，annotation 里绝不能出现 [5]、[6]、[7] 这类行号；也不能写成普通编号或省略行号。

你必须严格只返回一个 JSON 对象，不要使用 Markdown，不要输出 JSON 之外的任何文字。

JSON 格式只能是以下七类之一：
1. 需要追问：
{"type":"ask","message":"你的追问"}

2. 需要联网搜索：
{"type":"search","message":"我需要先联网核验","query":"作者 标题 全文 译文 注释 赏析"}

3. 可以添加诗词：
{"type":"add_poem","message":"简短说明","collection_id":1,"poem":{"title":"标题","author":"作者","dynasty":"朝代","content":"诗词全文，一行一句","remark":"","translation":"译文","annotation":"注释","appreciation":"赏析"}}

4. 可以一次添加多首诗词：
{"type":"add_poems","message":"简短说明","collection_id":1,"poems":[{"title":"标题","author":"作者","dynasty":"朝代","content":"诗词全文，一行一句","remark":"","translation":"译文","annotation":"注释","appreciation":"赏析"},{"title":"标题","author":"作者","dynasty":"朝代","content":"诗词全文，一行一句","remark":"","translation":"译文","annotation":"注释","appreciation":"赏析"}]}

5. 可以更新已有诗词元素：
{"type":"update_poem","message":"简短说明","poem_id":12,"updates":{"translation":"新的译文","appreciation":"新的赏析内容","annotation":"新的注释"}}

6. 确认不存在或无法查到：
{"type":"not_found","message":"说明为什么不执行操作"}

7. 普通回答：
{"type":"answer","message":"回答内容"}

规则：
- search 只能在联网搜索已启用且本轮没有搜索结果时返回；一旦已有搜索结果，不得再次返回 search。
- search.query 应包含作者、标题、首句、全文、译文、注释、赏析等能帮助检索的关键词；一次添加多首诗时，query 可以包含所有诗题和作者。
- 用户要求添加诗词时，如果目标库不唯一，必须先追问。
- 用户要求添加诗词时，如果诗词不唯一，例如“无题”这类同名诗，必须先追问作者、首句或其它可唯一识别的信息。
- 用户要求一次添加多首诗词，且所有诗词都能唯一确认时，返回 add_poems；如果其中任何一首不唯一或无法确认，必须先 ask，不能部分入库。
- 用户要求修改、丰富、纠错、补充译文、补充注释或补充赏析时，必须先从“当前可编辑诗词清单”中确定唯一 poem_id；如果候选不唯一，必须追问并列出可区分的信息。
- update_poem 的 updates 只能包含 title、author、dynasty、content、remark、translation、annotation、appreciation 这些字段，且只包含真正需要修改的字段。
- 不允许只凭标题直接更新；同名诗、同作者同题诗或信息不足时必须 ask。
- 如果用户要求纠错，而你不能可靠确认正确内容，必须 ask 或 not_found，不能编造。
- “补充译文”“丰富赏析”“完善注释”可以基于已有原文与可靠文学常识生成；涉及原文、作者、朝代等事实性改动时必须更谨慎。
- 只有 App 提供“联网搜索结果”时，才可声称已经联网核验；如果没有搜索结果且无法可靠确认，必须返回 search、ask 或 not_found，不能编造。
- 只有在目标库和诗词都唯一、且你能给出可靠全文时，才能返回 add_poem。
- 内容格式规范：
  - content 必须是完整原文，按诗句或词句的传统节奏单位换行，一句一行；不要只按句号、问号、叹号机械换行。
  - 长篇歌行、古体诗仍按诗句单位换行；如权威通行版本有明显分段，可用空行保留分段。
  - translation 尽量与 content 行数和顺序对应，一句译文一行；无法逐句对应时，按自然段保持可读。
  - annotation 使用“[行号] 注释内容”的格式，一条注释一行；这里的行号不是注释序号，而是 content 中从 1 开始计算的原文行号，空行不计入行号。
  - annotation 的所有行都必须以 [行号] 开头，且行号不得超过 content 的非空原文行数。例如 content 有 4 行时，只能使用 [1]、[2]、[3]、[4]。
  - 同一原文行有多个注释时，可以写多条相同 [行号]，例如 “[3] 翔：这里指奔走、跳跃。”
  - appreciation 使用自然段，不强制编号；重点写主题、情感、结构、艺术手法和学习提示。
  - remark 只在需要区分同名诗时填写，例如首句、常用别名。
- translation、annotation 和 appreciation 尽量填写。
- collection_id 必须是上方可用诗词库中的 id。当前在某个诗词库内部时，默认使用当前库 id。
''';
  }

  String _buildPoemLines({
    required List<PoemCollection> collections,
    required Map<int, List<Poem>> poemsByCollection,
    required PoemCollection? currentCollection,
  }) {
    final collectionById = <int, PoemCollection>{
      for (final collection in collections)
        if (collection.id != null) collection.id!: collection,
    };

    final collectionIds = currentCollection?.id == null
        ? collectionById.keys.toList(growable: false)
        : <int>[currentCollection!.id!];

    if (collectionIds.isEmpty) {
      return '（暂无可编辑诗词）';
    }

    final lines = <String>[];
    for (final collectionId in collectionIds) {
      final collection = collectionById[collectionId] ?? currentCollection;
      final poems = poemsByCollection[collectionId] ?? const <Poem>[];
      final collectionName = collection?.name ?? '未知诗词库';
      lines.add('库 id=$collectionId，名称：$collectionName');

      if (poems.isEmpty) {
        lines.add('- 暂无诗词');
        continue;
      }

      for (final poem in poems) {
        final id = poem.id;
        if (id == null) {
          continue;
        }
        final dynasty = poem.dynasty.trim().isEmpty ? '未知朝代' : poem.dynasty;
        final author = poem.author.trim().isEmpty ? '未知作者' : poem.author;
        final remark = poem.remark.trim().isEmpty
            ? ''
            : '，备注：${_compact(poem.remark, maxLength: 28)}';
        final content = _compact(poem.content, maxLength: 72);
        final translation = poem.translation.trim().isEmpty
            ? ''
            : '，译文片段：${_compact(poem.translation, maxLength: 48)}';
        final appreciation = poem.appreciation.trim().isEmpty
            ? ''
            : '，赏析片段：${_compact(poem.appreciation, maxLength: 48)}';
        lines.add(
          '- poem_id=$id，《${poem.title}》，$dynasty，$author$remark，内容片段：$content$translation$appreciation',
        );
      }
    }

    return lines.join('\n');
  }
}

class PoemAgentMessage {
  const PoemAgentMessage({required this.role, required this.content});

  final String role;
  final String content;
}

class PoemAgentResult {
  const PoemAgentResult({
    required this.type,
    required this.message,
    this.collectionId,
    this.poem,
    this.poems = const <PoemAgentDraft>[],
    this.poemId,
    this.updates,
    this.searchQuery,
    this.searchSources = const <String>[],
  });

  final String type;
  final String message;
  final int? collectionId;
  final PoemAgentDraft? poem;
  final List<PoemAgentDraft> poems;
  final int? poemId;
  final PoemAgentUpdates? updates;
  final String? searchQuery;
  final List<String> searchSources;

  bool get shouldAddPoem => type == 'add_poem' && poem != null;
  bool get shouldAddPoems => type == 'add_poems' && poems.isNotEmpty;
  bool get shouldUpdatePoem {
    return type == 'update_poem' && poemId != null && updates != null;
  }
  bool get shouldSearch {
    return type == 'search' && (searchQuery?.trim().isNotEmpty ?? false);
  }

  factory PoemAgentResult.fromJsonText(
    String text, {
    required int? currentCollectionId,
    String? searchQuery,
    List<String> searchSources = const <String>[],
  }) {
    final decoded = jsonDecode(_extractJsonObject(text));
    final map = _readObjectMap(decoded);
    if (map == null) {
      throw const FormatException('模型返回的 JSON 顶层不是对象。');
    }

    final type = (map['type'] as String?)?.trim() ?? 'answer';
    final message = (map['message'] as String?)?.trim() ?? '';
    final rawCollectionId = map['collection_id'];
    final collectionId = currentCollectionId ?? _readInt(rawCollectionId);
    final rawPoem = _readObjectMap(map['poem']);
    final rawPoems = map['poems'];
    final rawUpdates = _readObjectMap(map['updates']);
    final resultSearchQuery =
        ((map['query'] as String?) ?? searchQuery)?.trim();

    return PoemAgentResult(
      type: type,
      message: message.isEmpty ? '已收到。' : message,
      collectionId: collectionId,
      poem: rawPoem == null ? null : PoemAgentDraft.fromMap(rawPoem),
      poems: _readPoemDraftList(rawPoems),
      poemId: _readInt(map['poem_id']),
      updates: rawUpdates == null ? null : PoemAgentUpdates.fromMap(rawUpdates),
      searchQuery:
          resultSearchQuery == null || resultSearchQuery.isEmpty
              ? null
              : resultSearchQuery,
      searchSources: searchSources,
    );
  }
}

class PoemAgentDraft {
  const PoemAgentDraft({
    required this.title,
    required this.author,
    required this.dynasty,
    required this.content,
    this.remark = '',
    this.translation = '',
    this.annotation = '',
    this.appreciation = '',
  });

  final String title;
  final String author;
  final String dynasty;
  final String content;
  final String remark;
  final String translation;
  final String annotation;
  final String appreciation;

  bool get isComplete {
    return title.trim().isNotEmpty &&
        author.trim().isNotEmpty &&
        content.trim().isNotEmpty;
  }

  factory PoemAgentDraft.fromMap(Map<String, Object?> map) {
    return PoemAgentDraft(
      title: (map['title'] as String?)?.trim() ?? '',
      author: (map['author'] as String?)?.trim() ?? '',
      dynasty: (map['dynasty'] as String?)?.trim() ?? '',
      content: (map['content'] as String?)?.trim() ?? '',
      remark: (map['remark'] as String?)?.trim() ?? '',
      translation: (map['translation'] as String?)?.trim() ?? '',
      annotation: (map['annotation'] as String?)?.trim() ?? '',
      appreciation: (map['appreciation'] as String?)?.trim() ?? '',
    );
  }
}

class PoemAgentUpdates {
  const PoemAgentUpdates({required this.values});

  static const _allowedFields = <String>{
    'title',
    'author',
    'dynasty',
    'content',
    'remark',
    'translation',
    'annotation',
    'appreciation',
  };

  static const _fieldLabels = <String, String>{
    'title': '标题',
    'author': '作者',
    'dynasty': '朝代',
    'content': '内容',
    'remark': '备注',
    'translation': '译文',
    'annotation': '注释',
    'appreciation': '赏析',
  };

  final Map<String, String> values;

  bool get hasChanges => values.isNotEmpty;

  List<String> get changedFieldLabels {
    return [
      for (final field in values.keys) _fieldLabels[field] ?? field,
    ];
  }

  Poem applyTo(Poem poem) {
    return poem.copyWith(
      title: values.containsKey('title') ? values['title'] : null,
      author: values.containsKey('author') ? values['author'] : null,
      dynasty: values.containsKey('dynasty') ? values['dynasty'] : null,
      content: values.containsKey('content') ? values['content'] : null,
      remark: values.containsKey('remark') ? values['remark'] : null,
      translation:
          values.containsKey('translation') ? values['translation'] : null,
      annotation:
          values.containsKey('annotation') ? values['annotation'] : null,
      appreciation:
          values.containsKey('appreciation') ? values['appreciation'] : null,
    );
  }

  factory PoemAgentUpdates.fromMap(Map<String, Object?> map) {
    final values = <String, String>{};
    for (final entry in map.entries) {
      final key = entry.key.trim();
      if (!_allowedFields.contains(key) || entry.value == null) {
        continue;
      }
      values[key] = entry.value.toString().trim();
    }

    return PoemAgentUpdates(values: Map.unmodifiable(values));
  }
}

String _extractJsonObject(String text) {
  var trimmed = text.trim();
  if (trimmed.startsWith('```')) {
    final firstLineBreak = trimmed.indexOf('\n');
    if (firstLineBreak >= 0) {
      trimmed = trimmed.substring(firstLineBreak + 1).trim();
    }
    if (trimmed.endsWith('```')) {
      trimmed = trimmed.substring(0, trimmed.length - 3).trim();
    }
  }

  final start = trimmed.indexOf('{');
  final end = trimmed.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw FormatException('模型没有返回 JSON 对象：$text');
  }
  return trimmed.substring(start, end + 1);
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

List<PoemAgentDraft> _readPoemDraftList(Object? value) {
  if (value is! List) {
    return const <PoemAgentDraft>[];
  }

  final drafts = <PoemAgentDraft>[];
  for (final item in value) {
    final map = _readObjectMap(item);
    if (map == null) {
      continue;
    }
    drafts.add(PoemAgentDraft.fromMap(map));
  }
  return List.unmodifiable(drafts);
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
