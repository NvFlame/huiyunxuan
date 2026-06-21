import 'dart:convert';

import '../models/api_config.dart';
import '../models/poem.dart';
import '../models/poem_collection.dart';
import 'openai_api_service.dart';
import 'prosody_service.dart';
import 'regulated_verse_checker.dart';
import 'rhyme_service.dart';
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
    Poem? focusPoem,
  }) async {
    final requestHistory = _historyForCurrentRequest(history);
    final latestUserRequest = _latestUserRequest(history);
    final initialMessages = <Map<String, String>>[
      {
        'role': 'system',
        'content': _buildSystemPrompt(
          collections: collections,
          poemsByCollection: poemsByCollection,
          currentCollection: currentCollection,
          focusPoem: focusPoem,
          searchAvailable: config.isSearchEnabled,
        ),
      },
      _latestRequestMessage(latestUserRequest),
      for (final message in requestHistory)
        {
          'role': message.role,
          'content': message.content,
        },
    ];
    final content = await _createStrictAgentCompletion(
      config: config,
      messages: initialMessages,
      latestUserRequest: latestUserRequest,
      hasSearchResults: false,
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
        message: '当前 API 配置还没有启用联网搜索。请先在设置中为当前配置填写 Tavily 或博查 API Key，或补充可核验的资料。',
      );
    }

    final searchQueries = initialResult.effectiveSearchQueries.take(5).toList();
    final searchResults = <WebSearchResult>[];
    final sourceLines = <String>[];
    for (final query in searchQueries) {
      final result = await searchService.search(
        config: config,
        query: query,
      );
      searchResults.add(result);
      sourceLines.addAll(result.sourceLines);
    }

    if (searchResults.every((result) => result.isEmpty)) {
      return PoemAgentResult(
        type: 'not_found',
        message: '联网搜索没有返回可用结果，因此没有执行入库或修改。',
        searchQuery: searchQueries.join('；'),
        searchQueries: searchQueries,
        searchSources: sourceLines,
      );
    }

    final finalMessages = <Map<String, String>>[
      {
        'role': 'system',
        'content': _buildSystemPrompt(
          collections: collections,
          poemsByCollection: poemsByCollection,
          currentCollection: currentCollection,
          focusPoem: focusPoem,
          searchAvailable: true,
          searchResults: searchResults,
        ),
      },
      _latestRequestMessage(latestUserRequest),
      for (final message in requestHistory)
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
        'content': 'App 已根据以下 query 完成联网搜索：${searchQueries.join('；')}。'
            '请逐一处理用户本轮要求的每一首诗，不能因为某一个 query 的结果里没有另一首诗就判断另一首不存在。'
            '如果是批量添加，能确认全部诗词时优先返回 add_poems。不要再次返回 search 或 search_batch。'
            '最终结果只能围绕“本轮用户最新请求”，不得把历史对话中的其它诗题、其它添加任务或旧搜索结果当作当前目标。',
      },
    ];
    final finalContent = await _createStrictAgentCompletion(
      config: config,
      messages: finalMessages,
      latestUserRequest: latestUserRequest,
      hasSearchResults: true,
    );

    final finalResult = PoemAgentResult.fromJsonText(
      finalContent,
      currentCollectionId: currentCollection?.id,
      searchQuery: searchQueries.join('；'),
      searchQueries: searchQueries,
      searchSources: sourceLines,
    );
    if (finalResult.shouldSearch) {
      return PoemAgentResult(
        type: 'ask',
        message: '我已经完成联网搜索，但仍无法唯一确认可执行结果。请补充作者、首句、目标诗词库或其它限定信息。',
        searchQuery: searchQueries.join('；'),
        searchQueries: searchQueries,
        searchSources: sourceLines,
      );
    }
    return finalResult;
  }

  Future<String> _createStrictAgentCompletion({
    required ApiConfig config,
    required List<Map<String, String>> messages,
    required String latestUserRequest,
    required bool hasSearchResults,
  }) async {
    var currentMessages = List<Map<String, String>>.from(messages);
    var lastContent = '';
    for (var attempt = 0; attempt < 3; attempt += 1) {
      lastContent = await apiService.createChatCompletion(
        config: config,
        messages: currentMessages,
      );
      if (!_shouldRetryIntermediateReply(lastContent, latestUserRequest)) {
        return lastContent;
      }
      currentMessages = <Map<String, String>>[
        ...messages,
        {
          'role': 'assistant',
          'content': lastContent,
        },
        {
          'role': 'system',
          'content': _intermediateReplyRepairPrompt(
            hasSearchResults: hasSearchResults,
          ),
        },
      ];
    }

    return jsonEncode({
      'type': 'ask',
      'message': '模型只返回了“正在检索/正在处理”之类的中间态说明，没有给出可执行结果。请重新发送，或补充作者、首句、目标诗词库等限定信息后再试。',
    });
  }

  bool _shouldRetryIntermediateReply(String content, String latestUserRequest) {
    if (!_looksLikeActionRequest(latestUserRequest)) {
      return false;
    }

    final jsonObject = _tryExtractJsonObject(content);
    if (jsonObject == null) {
      return _looksLikeIntermediateReply(content);
    }

    try {
      final decoded = jsonDecode(jsonObject);
      final map = _readObjectMap(decoded);
      if (map == null) {
        return false;
      }
      final type = (map['type'] as String?)?.trim();
      if (type != null && type != 'answer') {
        return false;
      }
      return _looksLikeIntermediateReply(_plainTextFromModel(map['message']));
    } catch (_) {
      return false;
    }
  }

  String _intermediateReplyRepairPrompt({required bool hasSearchResults}) {
    final allowedAction = hasSearchResults
        ? 'add_poem、add_poems、update_poem、ask、not_found 或 answer'
        : 'search、search_batch、add_poem、add_poems、update_poem、ask、not_found 或 answer';
    return '你刚才返回了中间态说明，但 App 没有后台异步任务，不会在你说“正在检索/正在处理”后自动继续。'
        '请立刻重新输出一个且仅一个 JSON 对象，type 必须是 $allowedAction。'
        '如果需要联网搜索，返回 search 或 search_batch；如果已经有搜索结果，必须根据结果返回最终动作。'
        '禁止输出“正在检索”“我将搜索”“请稍等”“稍后处理”等非最终回复。';
  }

  String _buildSystemPrompt({
    required List<PoemCollection> collections,
    required Map<int, List<Poem>> poemsByCollection,
    required PoemCollection? currentCollection,
    required Poem? focusPoem,
    required bool searchAvailable,
    List<WebSearchResult> searchResults = const <WebSearchResult>[],
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
    final focusPoemBlock = _buildFocusPoemBlock(focusPoem);

    final context = currentCollection == null
        ? '当前位于“诗词库管理”页面。用户若要添加诗词，必须明确目标诗词库；用户若要修改诗词，必须明确到一个本地 poem_id。'
        : '当前位于诗词库“${currentCollection.name}”（id=${currentCollection.id}）内部。添加诗词默认归入当前库；修改诗词只允许使用当前库清单中列出的 poem_id。';
    final focusContext = focusPoem == null
        ? ''
        : '当前学文或展才聚焦诗词：poem_id=${focusPoem.id}，《${focusPoem.title}》，${focusPoem.dynasty}，${focusPoem.author}。用户说“这首诗”“当前诗”“这句”时，默认指这首诗；涉及修改时应优先使用这个 poem_id。若用户要求补充或更正译文、注释、学习笔记、赏析，且可确定内容，应直接返回 update_poem 写回诗词库；若用户说的内容与它明显不符，必须追问确认。';
    final hasSearchResults = searchResults.isNotEmpty;
    final searchState = !hasSearchResults
        ? searchAvailable
            ? '联网搜索已启用。若用户要求添加新诗、核验原文事实、校正作者朝代、或要求依据外部资料补充内容，先确认目标库和诗词身份是否唯一；若仍不唯一则 ask，若已经唯一且本轮尚无搜索结果，则必须先返回 search 或 search_batch 动作，让 App 先联网检索。若用户只是要求基于当前聚焦诗词的已有内容调整措辞、整理注释格式、改写译文、补充学习笔记或润色赏析，且不需要外部事实核验，可以直接返回 update_poem。'
            : '联网搜索未启用。不要声称已经联网搜索；如果需要外部核验，应 ask 用户配置联网搜索或补充资料。'
        : 'App 已完成联网搜索。你必须优先依据下方搜索结果返回最终动作，不得再次返回 search 或 search_batch。若是批量搜索，必须逐一检查每个搜索分组，不能用某一组结果否定另一首诗。若搜索结果不足、冲突或无法核验，应返回 ask 或 not_found。';
    final searchBlock = !hasSearchResults
        ? ''
        : '''

联网搜索结果：
${_buildSearchResultsBlock(searchResults)}
''';

    return '''
你是“绘云轩”的诗词库助手，负责和用户反复确认诗词、目标诗词库与本地诗词元素，并在信息唯一时返回可执行动作。

$context

$focusContext

$searchState

可用诗词库：
$collectionLines

当前可编辑诗词清单（更新诗词时只能使用这里列出的 poem_id）：
$poemLines

当前聚焦诗词完整内容（学文或展才中用于回答与修改）：
$focusPoemBlock
$searchBlock

格式示例：
content:
岂无山歌与村笛？
呕哑嘲哳难为听。

translation:
难道没有山歌和村笛可以听吗？
只是那声音嘈杂刺耳，实在难以入耳。

annotation:
[0] 标题或词牌需要解释时使用标题注释。
[1] 岂无：难道没有。
[1] 山歌与村笛：山野歌声和乡村笛声。
[2] 呕哑嘲哳：形容声音杂乱刺耳。

反例：如果 content 只有 4 个非空原文行，annotation 里绝不能出现 [5]、[6]、[7] 这类行号；也不能写成普通编号或省略行号。[0] 只能用于标题注释，不能用于正文注释。

重要：不要返回“正在检索”“正在搜索”“我将处理”“请稍等”“稍后回复”等中间态说明。App 没有后台异步任务；每次回复都必须是最终可执行 JSON。需要联网时返回 search 或 search_batch；已有搜索结果时返回 add_poem、add_poems、update_poem、ask、not_found 或 answer。
你必须严格只返回一个 JSON 对象，不要使用 Markdown，不要输出 JSON 之外的任何文字。

JSON 格式只能是以下八类之一：
1. 需要追问：
{"type":"ask","message":"你的追问"}

2. 需要联网搜索：
{"type":"search","message":"我需要先联网核验","query":"作者 标题 全文 译文 注释 赏析"}

3. 需要批量联网搜索：
{"type":"search_batch","message":"我需要分别核验这些诗词","queries":["作者A 标题A 首句A 全文 译文 注释 赏析","作者B 标题B 首句B 全文 译文 注释 赏析"]}

4. 可以添加诗词：
{"type":"add_poem","message":"简短说明","collection_id":1,"poem":{"title":"标题","author":"作者","dynasty":"朝代","preface":"序或小序，没有则留空","content":"诗词全文，一行一句","remark":"","translation":"译文","annotation":"注释","learning_note":"","appreciation":"赏析"}}

5. 可以一次添加多首诗词：
{"type":"add_poems","message":"简短说明","collection_id":1,"poems":[{"title":"标题","author":"作者","dynasty":"朝代","preface":"序或小序，没有则留空","content":"诗词全文，一行一句","remark":"","translation":"译文","annotation":"注释","learning_note":"","appreciation":"赏析"},{"title":"标题","author":"作者","dynasty":"朝代","preface":"序或小序，没有则留空","content":"诗词全文，一行一句","remark":"","translation":"译文","annotation":"注释","learning_note":"","appreciation":"赏析"}]}

6. 可以更新已有诗词元素：
{"type":"update_poem","message":"简短说明","poem_id":12,"updates":{"translation":"新的译文","annotation":"新的注释","learning_note":"新的学习笔记","appreciation":"新的赏析内容"}}
如果用户明确要求确认多音字平仄或韵脚韵部，可返回：
{"type":"update_poem","message":"简短说明","poem_id":12,"updates":{"prosody_overrides_json":{"items":[{"line":4,"char_index":5,"char":"上","tone":"仄","rhyme":"去声二十三漾","note":"方位词，表示在青苔上面"}]}}}

7. 确认不存在或无法查到：
{"type":"not_found","message":"说明为什么不执行操作"}

8. 普通回答：
{"type":"answer","message":"回答内容"}

规则：
- search/search_batch 只能在联网搜索已启用且本轮没有搜索结果时返回；一旦已有搜索结果，不得再次返回 search 或 search_batch。
- search.query 应包含作者、标题、首句、全文、译文、注释、赏析等能帮助检索的关键词。
- 一次添加多首诗时，必须优先返回 search_batch，每首诗一个 query；不要把多首诗挤进同一个 query。每个 query 都要包含该诗自己的作者、标题、首句或用户提供的识别短语。
- 如果用户提供了首句、长题片段或别名，search.query 必须原样包含这些短语；不要把用户给出的首句省略掉，也不要只用简称搜索。
- 如果上一轮是一次添加多首诗词的未完成任务，而本轮用户只是澄清其中一首、说“选择……”“先添加……”“继续添加……”，必须把本轮视为同一批量任务的继续；除非用户明确说“只添加这一首”“取消其它”，不要把其它待添加诗词视为取消。
- 如果批量搜索结果中某一组没有另一首诗的信息，这只说明该组 query 与另一首无关，不能据此判断另一首不存在；必须查看对应另一首的搜索分组。
- App 会自动优先搜索古文岛、古诗文库、百度百科、百度汉语、维基文库、中华诗词、搜韵等来源；如果搜索结果中有这些来源，必须优先依据它们。新闻、论坛、个人站、泛内容站只能作辅助，不能作为添加长诗全文的唯一依据。
- 每次执行添加、搜索或更新时，目标必须以“本轮用户最新请求”为准；历史对话只用于理解必要的澄清，不得把历史中的其它诗题、旧搜索结果或旧添加任务当成当前目标。
- 所有 message、translation、annotation、learning_note、appreciation 等文本字段都必须使用纯文本，不要使用 Markdown 标记；不要输出 **粗体**、# 标题、> 引用、```代码块``` 或反引号。
- 普通回答如需分点，可使用自然段或“1.”、“2.”这样的纯文本编号，不要用 Markdown 粗体、标题或引用格式。
- 即使只是普通问答、赏析或解释，也必须返回 {"type":"answer","message":"回答内容"}，不要直接输出自然语言正文。
- dynasty/朝代字段必须按本 App 的时期命名填写：辛亥革命、民国、抗战、建国初期主要活动的人物统一写“近代”，例如毛泽东、鲁迅、郁达夫、郭沫若、闻一多、徐志摩等；“当代”只用于改革开放以后或当前仍主要活跃的作者。
- 用户要求添加诗词时，如果目标库不唯一，必须先追问。
- 用户要求添加诗词时，如果诗词不唯一，例如“无题”这类同名诗，必须先追问作者、首句或其它可唯一识别的信息。
- 用户要求一次添加多首诗词，且所有诗词都能唯一确认、并且已经拥有可靠完整全文时，返回 add_poems；如果还没有搜索或资料不足，先返回 search_batch；如果其中任何一首不唯一或无法确认，必须先 ask，不能部分入库。
- 批量添加的最终动作不能只处理其中一首然后结束；除非用户明确说“只添加这一首”，否则必须继续处理同一批任务里的其它诗词。
- 用户要求修改、丰富、纠错、补充译文、补充注释、补充学习笔记或补充赏析时，必须先从“当前可编辑诗词清单”中确定唯一 poem_id；如果候选不唯一，必须追问并列出可区分的信息。
- update_poem 的 updates 只能包含 title、author、dynasty、preface、content、remark、translation、annotation、learning_note、appreciation、prosody_overrides_json、prosody_note 这些字段，且只包含真正需要修改的字段。
- update_poem 的字段值必须是该字段“更新后的完整内容”，不是局部补丁；例如只修改 annotation 中某个词条时，也必须在 annotation 中返回保留其它原有注释后的完整注释文本。
- prosody_overrides_json 只用于用户明确要求确认或更正多音字平仄、韵脚韵部时；格式必须是 JSON 对象或 JSON 字符串，包含 items 数组，每项含 line、char_index、char、tone、rhyme、note。tone 只能为“平”“仄”“多”；不能为了押韵强行改变字义读音。如果同诗韵脚分属多个韵部，应分别填写各自韵部。
- 如果当前聚焦诗词完整内容中已经提供 annotation、translation、learning_note 或 appreciation，不得声称不知道现有注释、译文、学习笔记或赏析；只有该字段确实为空时，才可说明暂无现有内容。
- 不允许只凭标题直接更新；同名诗、同作者同题诗或信息不足时必须 ask。
- 如果用户要求纠错，而你不能可靠确认正确内容，必须 ask 或 not_found，不能编造。
- “补充译文”“丰富赏析”“完善注释”可以基于已有原文与可靠文学常识生成；涉及原文、作者、朝代等事实性改动时必须更谨慎。
- 只有 App 提供“联网搜索结果”时，才可声称已经联网核验；如果没有搜索结果且无法可靠确认，必须返回 search、ask 或 not_found，不能编造。
- 只有在目标库和诗词都唯一、且你能给出可靠全文时，才能返回 add_poem。
- 用户要求添加诗词时，不能把“格式不合规”“注释行号不合规”“正文分行不合规”作为最终失败理由；这些属于你必须在返回 JSON 前自行修正的内部格式问题。
- 添加诗词的最终失败理由只能是：无法搜索或核验到目标诗词的完整可靠全文，或用户提供的信息不足以唯一确定目标。若能找到完整全文，就必须先按规范重排 content、translation、annotation，再返回 add_poem 或 add_poems。
- 返回 add_poem/add_poems 前必须做一次内部校对：content 是否每个诗句一行、标点是否保留、annotation 行号是否没有超过 content 的非空行数。校对不通过时，必须自行修正后再返回，不能要求用户“重新整理格式”。
- 内容格式规范：
  - 写入数据库的字段必须是可直接显示和保存的纯文本，不能包含 Markdown 标记。
  - content 必须是完整原文，按诗句或词句的传统节奏单位换行，一句一行；不要只按句号、问号、叹号机械换行。
  - 四言、五言、七言诗以及明显的四言、五言、七言古体/歌行，必须按每个诗句换行：四字一句、五字一句或七字一句；不能把“上句， 下句。”合并成一行。
  - 七绝、七律通常每行 7 个汉字并保留行末标点；五绝、五律通常每行 5 个汉字并保留行末标点；《诗经》等四言诗通常每行 4 个汉字并保留行末标点。
  - 如果原文写作“千里莺啼绿映红，水村山郭酒旗风。”，content 必须写成两行：“千里莺啼绿映红，”换行“水村山郭酒旗风。”；“岂无山歌与村笛？呕哑嘲哳难为听。”同理应拆为两个七言诗句。
  - 词、曲、骚体、长短句、杂言诗必须优先保留权威整理本的通行换行；如果搜索结果无法提供可靠换行，不要自行猜测，应 ask 用户确认或继续补充资料。
  - 添加词、曲等有上下阙/上下片/分片的作品时，content 中必须在上阙与下阙之间写入一个空行，也就是两次换行（JSON 字符串中表现为 \n\n）；不要只用一个普通换行把上下阙连在一起。
  - 例如词的 content 应为“上阙最后一句。\n\n下阙第一句，”这种结构；空行只用于显示分段，不计入注释行号。诗文有自然段落时也按同样方式用一个空行分隔自然段。
  - content 必须保留权威来源或通行整理本中的现代标点，包括逗号、句号、问号、叹号、分号、冒号、顿号等；换行时不得删除标点。
  - 五言、七言诗句如果原整理本为“天上白玉京，十二楼五城。”，应写成“天上白玉京，”换行“十二楼五城。”，不能写成“天上白玉京”换行“十二楼五城”。
  - 如果搜索结果只有无标点古籍文本，应优先继续寻找带标点的权威整理本；不能可靠补出标点时，不要添加入库，应 ask 用户确认是否接受无标点版本。
  - preface 只填写题前序、词前小序或作者原有题注，例如“丙辰中秋，欢饮达旦……兼怀子由。”；不要把序混入 content，也不要把普通备注写入 preface。
  - 长篇歌行、古体诗仍按诗句单位换行；如权威通行版本有明显分段，可用空行保留分段。
  - translation 尽量与 content 行数和顺序对应，一句译文一行；无法逐句对应时，按自然段保持可读。
  - annotation 使用“[行号] 注释内容”的格式，一条注释一行；这里的行号不是注释序号。正文行号从 content 中第 1 个非空原文行开始计算，空行不计入行号。
  - annotation 可以使用 [0] 表示标题注释，专门解释标题、词牌、题中地名、人名、典故或题下注关键信息；[0] 不对应正文行。
  - annotation 的 [行号] 必须对应“最终 content 分行后”的原文行号；不要按逗号数量、语义句数量、注释条目数量或搜索来源原段落编号来编号。
  - annotation 的所有行都必须以 [行号] 开头，且除 [0] 标题注释外，正文行号不得超过 content 的非空原文行数。例如 content 有 4 行时，只能使用 [0]、[1]、[2]、[3]、[4]。
  - 同一原文行有多个注释时，可以写多条相同 [行号]，例如 “[3] 翔：这里指奔走、跳跃。”
  - 长篇诗文的 annotation 不必逐行覆盖，优先给出能准确对齐原文行号的关键注释；不能确认行号的注释宁可省略，不要编造或使用超出 content 行数的行号。
  - 返回前必须自检：annotation 中最大的正文 [行号] 不能超过 content 的非空原文行数；[0] 只用于标题注释。
  - learning_note 是用户个人学习笔记，可写个人理解、疑问、记忆方法、课堂笔记或待复习点；添加新诗时除非用户明确要求，一般留空。
  - appreciation 使用自然段，不强制编号；重点写主题、情感、结构、艺术手法和学习提示。
  - remark 只在需要区分同名诗时填写，例如首句、常用别名。
- translation、annotation 和 appreciation 尽量填写；learning_note 除非用户要求，一般不要自动编写。
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
        final preface = poem.preface.trim().isEmpty
            ? ''
            : '，序：${_compact(poem.preface, maxLength: 36)}';
        final content = _compact(poem.content, maxLength: 72);
        final translation = poem.translation.trim().isEmpty
            ? ''
            : '，译文片段：${_compact(poem.translation, maxLength: 48)}';
        final appreciation = poem.appreciation.trim().isEmpty
            ? ''
            : '，赏析片段：${_compact(poem.appreciation, maxLength: 48)}';
        final learningNote = poem.learningNote.trim().isEmpty
            ? ''
            : '，笔记片段：${_compact(poem.learningNote, maxLength: 48)}';
        final prosody = _compact(_prosodySummaryForList(poem), maxLength: 120);
        final prosodyText = prosody.isEmpty ? '' : '，格律：$prosody';
        lines.add(
          '- poem_id=$id，《${poem.title}》，$dynasty，$author$remark$preface，内容片段：$content$translation$learningNote$appreciation$prosodyText',
        );
      }
    }

    return lines.join('\n');
  }

  String _buildFocusPoemBlock(Poem? poem) {
    if (poem == null) {
      return '（无当前聚焦诗词）';
    }

    return '''
poem_id: ${poem.id}
title: ${poem.title}
author: ${poem.author}
dynasty: ${poem.dynasty}
remark: ${_emptyAsNone(poem.remark)}
preface:
${_emptyAsNone(poem.preface)}

content:
${_emptyAsNone(poem.content)}

translation:
${_emptyAsNone(poem.translation)}

annotation:
${_emptyAsNone(poem.annotation)}

learning_note:
${_emptyAsNone(poem.learningNote)}

appreciation:
${_emptyAsNone(poem.appreciation)}

prosody:
system: ${poem.prosodySystem}
form: ${poem.prosodyForm}
rhyme_book: ${poem.prosodyRhymeBook}
note: ${_emptyAsNone(poem.prosodyNote)}
overrides_json:
${_emptyAsNone(poem.prosodyOverridesJson)}

prosody_candidates:
${_buildProsodyCandidateBlock(poem)}

prosody_tones:
${_buildProsodyToneBlock(poem)}
''';
  }

  String _buildProsodyCandidateBlock(Poem poem) {
    final candidates = findProsodyCalibrationCandidates(poem);
    if (candidates.isEmpty) {
      return '（暂无需要确认的多音字或多韵韵脚）';
    }
    return candidates.map((candidate) {
      final options = candidate.matches.isEmpty
          ? '无本地韵书候选'
          : candidate.matches.map((entry) => entry.label).join('、');
      return '- line=${candidate.lineNumber}, char_index=${candidate.charIndex}, '
          'char=${candidate.character}, current=${candidate.currentTone}, '
          'is_rhyme_foot=${candidate.isRhymeFoot}, options=$options';
    }).join('\n');
  }

  String _prosodySummaryForList(Poem poem) {
    if (!poem.prosodySupported || !poem.prosodyEnabled) {
      return '';
    }
    final candidates = findProsodyCalibrationCandidates(poem);
    final regulatedCheck = checkRegulatedVerse(poem);
    final candidateText = candidates.isEmpty
        ? '暂无候选'
        : candidates
            .take(8)
            .map((candidate) {
              final options = candidate.matches.isEmpty
                  ? '无候选'
                  : candidate.matches.map((entry) => entry.label).join('/');
              return '第${candidate.lineNumber}行第${candidate.charIndex}字“${candidate.character}”(${candidate.currentTone}, $options)';
            })
            .join('；');
    return [
      prosodySystemLabel(poem.prosodySystem),
      if (poem.prosodyForm.trim().isNotEmpty) poem.prosodyForm.trim(),
      if (poem.prosodyRhymeBook.trim().isNotEmpty)
        poem.prosodyRhymeBook.trim(),
      if (regulatedCheck.applicable) regulatedCheck.summary,
      '候选：$candidateText',
    ].join('，');
  }

  String _buildProsodyToneBlock(Poem poem) {
    if (!poem.prosodySupported || !poem.prosodyEnabled) {
      return '（未启用格律显示）';
    }
    final toneLines = analyzeCharacterTones(poem);
    final regulatedCheck = checkRegulatedVerse(poem);
    final toneText = toneLines.isEmpty
        ? '（暂无逐字平仄）'
        : toneLines.map((line) {
            final marks = line.characters
                .map((character) => '${character.character}${character.mark}')
                .join(' ');
            return '- line=${line.lineNumber}: $marks';
          }).join('\n');
    final lineChecks = regulatedCheck.lines.isEmpty
        ? '（暂无逐句审查）'
        : regulatedCheck.lines.map((line) {
            return '- line=${line.lineNumber}, pattern=${line.pattern}, '
                'tags=${line.tags.join('、')}';
          }).join('\n');
    final relations = regulatedCheck.relations.isEmpty
        ? '（无失粘失对关系）'
        : regulatedCheck.relations.map((relation) {
            return '- lines=${relation.firstLine}-${relation.secondLine}, '
                'tag=${relation.tag}';
          }).join('\n');
    return '''
check: ${regulatedCheck.summary}
display_form: ${regulatedCheck.displayForm}
tones:
$toneText
line_checks:
$lineChecks
relations:
$relations
''';
  }

  String _buildSearchResultsBlock(List<WebSearchResult> results) {
    if (results.length == 1) {
      return results.first.toPromptText();
    }
    return [
      for (var index = 0; index < results.length; index += 1)
        [
          '【搜索 ${index + 1}】',
          results[index].toPromptText(),
        ].join('\n'),
    ].join('\n\n');
  }
}

class PoemAgentMessage {
  const PoemAgentMessage({required this.role, required this.content});

  final String role;
  final String content;
}

List<PoemAgentMessage> _historyForCurrentRequest(
  List<PoemAgentMessage> history,
) {
  if (history.length <= _requestHistoryLimit) {
    return List.unmodifiable(history);
  }
  return List.unmodifiable(
    history.sublist(history.length - _requestHistoryLimit),
  );
}

String _latestUserRequest(List<PoemAgentMessage> history) {
  for (var index = history.length - 1; index >= 0; index -= 1) {
    final message = history[index];
    if (message.role == 'user' && message.content.trim().isNotEmpty) {
      return message.content.trim();
    }
  }
  return '';
}

Map<String, String> _latestRequestMessage(String latestUserRequest) {
  final content = latestUserRequest.trim().isEmpty
      ? '本轮用户最新请求为空；如信息不足，应 ask。'
      : '本轮用户最新请求：$latestUserRequest\n'
          '添加、搜索、更新、入库的目标原则上只能来自本轮最新请求和必要的澄清上下文。'
          '如果紧邻上文存在尚未完成的同一批量添加任务，而本轮只是选择、确认、先添加或继续其中一项，可以延续该批量任务；'
          '除此之外，不得把更早历史里的其它诗题、旧搜索或旧添加任务当作当前目标。';
  return {'role': 'system', 'content': content};
}

const _requestHistoryLimit = 8;

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
    this.searchQueries = const <String>[],
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
  final List<String> searchQueries;
  final List<String> searchSources;

  bool get shouldAddPoem => type == 'add_poem' && poem != null;
  bool get shouldAddPoems => type == 'add_poems' && poems.isNotEmpty;
  bool get shouldUpdatePoem {
    return type == 'update_poem' && poemId != null && updates != null;
  }
  bool get shouldSearch {
    return (type == 'search' || type == 'search_batch') &&
        effectiveSearchQueries.isNotEmpty;
  }

  List<String> get effectiveSearchQueries {
    final queries = <String>[];
    for (final query in searchQueries) {
      final trimmed = query.trim();
      if (trimmed.isNotEmpty && !queries.contains(trimmed)) {
        queries.add(trimmed);
      }
    }
    final singleQuery = searchQuery?.trim() ?? '';
    if (singleQuery.isNotEmpty && !queries.contains(singleQuery)) {
      queries.add(singleQuery);
    }
    return List.unmodifiable(queries);
  }

  factory PoemAgentResult.fromJsonText(
    String text, {
    required int? currentCollectionId,
    String? searchQuery,
    List<String> searchQueries = const <String>[],
    List<String> searchSources = const <String>[],
  }) {
    final jsonObject = _tryExtractJsonObject(text);
    if (jsonObject == null) {
      final fallbackMessage = _plainTextFromModel(text);
      return PoemAgentResult(
        type: 'answer',
        message: fallbackMessage.isEmpty ? '模型返回了空内容。' : fallbackMessage,
        searchQuery: searchQuery,
        searchQueries: searchQueries,
        searchSources: searchSources,
      );
    }

    final decoded = jsonDecode(jsonObject);
    final map = _readObjectMap(decoded);
    if (map == null) {
      throw const FormatException('模型返回的 JSON 顶层不是对象。');
    }

    final type = (map['type'] as String?)?.trim() ?? 'answer';
    final message = _plainTextFromModel(map['message']);
    final rawCollectionId = map['collection_id'];
    final collectionId = currentCollectionId ?? _readInt(rawCollectionId);
    final rawPoem = _readObjectMap(map['poem']);
    final rawPoems = map['poems'];
    final rawUpdates = _readObjectMap(map['updates']);
    final parsedQueries = _readStringList(map['queries']);
    final resultSearchQuery =
        ((map['query'] as String?) ?? searchQuery)?.trim();
    final allQueries = <String>[
      ...searchQueries,
      ...parsedQueries,
      if (resultSearchQuery != null && resultSearchQuery.isNotEmpty)
        resultSearchQuery,
    ];

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
      searchQueries: List.unmodifiable(_uniqueNonEmptyStrings(allQueries)),
      searchSources: searchSources,
    );
  }
}

class PoemAgentDraft {
  const PoemAgentDraft({
    required this.title,
    required this.author,
    required this.dynasty,
    this.preface = '',
    required this.content,
    this.remark = '',
    this.translation = '',
    this.annotation = '',
    this.learningNote = '',
    this.appreciation = '',
  });

  final String title;
  final String author;
  final String dynasty;
  final String preface;
  final String content;
  final String remark;
  final String translation;
  final String annotation;
  final String learningNote;
  final String appreciation;

  bool get isComplete {
    return title.trim().isNotEmpty &&
        author.trim().isNotEmpty &&
        content.trim().isNotEmpty;
  }

  PoemAgentDraft copyWith({
    String? title,
    String? author,
    String? dynasty,
    String? preface,
    String? content,
    String? remark,
    String? translation,
    String? annotation,
    String? learningNote,
    String? appreciation,
  }) {
    return PoemAgentDraft(
      title: title ?? this.title,
      author: author ?? this.author,
      dynasty: dynasty ?? this.dynasty,
      preface: preface ?? this.preface,
      content: content ?? this.content,
      remark: remark ?? this.remark,
      translation: translation ?? this.translation,
      annotation: annotation ?? this.annotation,
      learningNote: learningNote ?? this.learningNote,
      appreciation: appreciation ?? this.appreciation,
    );
  }

  factory PoemAgentDraft.fromMap(Map<String, Object?> map) {
    final author = _plainTextFromModel(map['author']);
    final dynasty = _plainTextFromModel(map['dynasty']);
    return PoemAgentDraft(
      title: _plainTextFromModel(map['title']),
      author: author,
      dynasty: _normalizeAgentDynasty(dynasty: dynasty, author: author),
      preface: _plainTextFromModel(map['preface']),
      content: _plainTextFromModel(map['content']),
      remark: _plainTextFromModel(map['remark']),
      translation: _plainTextFromModel(map['translation']),
      annotation: _plainTextFromModel(map['annotation']),
      learningNote: _plainTextFromModel(
        map['learning_note'] ?? map['learningNote'],
      ),
      appreciation: _plainTextFromModel(map['appreciation']),
    );
  }
}

class PoemAgentUpdates {
  const PoemAgentUpdates({required this.values});

  static const _allowedFields = <String>{
    'title',
    'author',
    'dynasty',
    'preface',
    'content',
    'remark',
    'translation',
    'annotation',
    'learning_note',
    'appreciation',
    'prosody_overrides_json',
    'prosody_note',
  };

  static const _fieldLabels = <String, String>{
    'title': '标题',
    'author': '作者',
    'dynasty': '朝代',
    'preface': '序/小序',
    'content': '内容',
    'remark': '备注',
    'translation': '译文',
    'annotation': '注释',
    'learning_note': '学习笔记',
    'appreciation': '赏析',
    'prosody_overrides_json': '格律校准',
    'prosody_note': '格律说明',
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
      preface: values.containsKey('preface') ? values['preface'] : null,
      content: values.containsKey('content') ? values['content'] : null,
      remark: values.containsKey('remark') ? values['remark'] : null,
      translation:
          values.containsKey('translation') ? values['translation'] : null,
      annotation:
          values.containsKey('annotation') ? values['annotation'] : null,
      learningNote:
          values.containsKey('learning_note') ? values['learning_note'] : null,
      appreciation:
          values.containsKey('appreciation') ? values['appreciation'] : null,
      prosodyOverridesJson: values.containsKey('prosody_overrides_json')
          ? values['prosody_overrides_json']
          : null,
      prosodyNote: values.containsKey('prosody_note')
          ? values['prosody_note']
          : null,
    );
  }

  factory PoemAgentUpdates.fromMap(Map<String, Object?> map) {
    final values = <String, String>{};
    for (final entry in map.entries) {
      final rawKey = entry.key.trim();
      final key = rawKey == 'learningNote' ? 'learning_note' : rawKey;
      if (!_allowedFields.contains(key) || entry.value == null) {
        continue;
      }
      if (key == 'prosody_overrides_json' &&
          (entry.value is Map || entry.value is List)) {
        values[key] = jsonEncode(entry.value);
      } else {
        values[key] = _plainTextFromModel(entry.value);
      }
    }
    if (values.containsKey('dynasty')) {
      values['dynasty'] = _normalizeAgentDynasty(
        dynasty: values['dynasty'] ?? '',
        author: values['author'] ?? '',
      );
    }

    return PoemAgentUpdates(values: Map.unmodifiable(values));
  }
}

String _normalizeAgentDynasty({
  required String dynasty,
  required String author,
}) {
  final text = dynasty.trim();
  if (text.isEmpty) {
    return text;
  }
  const nearModernLabels = {'当代', '现代', '近现代', '现当代'};
  final compactText = text.replaceAll(RegExp(r'\s+'), '');
  if (!nearModernLabels.any(compactText.contains)) {
    return text;
  }

  const nearModernAuthorKeywords = <String>{
    '毛泽东',
    '鲁迅',
    '周树人',
    '周作人',
    '胡适',
    '陈独秀',
    '李大钊',
    '秋瑾',
    '柳亚子',
    '郁达夫',
    '郭沫若',
    '闻一多',
    '徐志摩',
    '戴望舒',
    '艾青',
    '朱德',
    '陈毅',
    '叶剑英',
  };
  final authorText = author.trim();
  if (nearModernAuthorKeywords.any(authorText.contains)) {
    return '近代';
  }
  return text;
}

String _plainTextFromModel(Object? value) {
  var text = (value?.toString() ?? '').trim();
  if (text.isEmpty) {
    return '';
  }

  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  text = text.replaceAll(RegExp(r'```[a-zA-Z0-9_-]*\n?'), '');
  text = text.replaceAll('```', '');
  text = text.replaceAllMapped(
    RegExp(r'\*\*([^*\n]+)\*\*'),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'__([^_\n]+)__'),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'`([^`\n]+)`'),
    (match) => match.group(1) ?? '',
  );

  return text
      .split('\n')
      .map((line) {
        var cleanedLine = line.trimRight();
        cleanedLine = cleanedLine.replaceFirst(
          RegExp(r'^\s{0,3}#{1,6}\s+'),
          '',
        );
        cleanedLine = cleanedLine.replaceFirst(
          RegExp(r'^\s{0,3}>\s?'),
          '',
        );
        return cleanedLine;
      })
      .join('\n')
      .trim();
}

bool _looksLikeActionRequest(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), '');
  if (normalized.isEmpty) {
    return false;
  }

  const actionKeywords = <String>[
    '添加',
    '加入',
    '入库',
    '收录',
    '导入',
    '放进',
    '写入',
    '补充',
    '完善',
    '丰富',
    '更正',
    '纠错',
    '修正',
    '修改',
    '更新',
    '校准',
    '确认平仄',
    '确认韵部',
    '搜索',
    '检索',
    '查找',
  ];
  return actionKeywords.any(normalized.contains);
}

bool _looksLikeIntermediateReply(String text) {
  final normalized = _plainTextFromModel(text).replaceAll(RegExp(r'\s+'), '');
  if (normalized.isEmpty) {
    return false;
  }

  final patterns = <RegExp>[
    RegExp(r'(正在|开始|先)(联网)?(检索|搜索|查询|查找|核验|整理|处理)'),
    RegExp(r'(检索|搜索|查询|查找|核验|整理|处理)中'),
    RegExp(r'(我会|我将|我来|我先|接下来).{0,16}(检索|搜索|查询|查找|核验|整理|处理|添加|写入)'),
    RegExp(r'(请稍等|稍等|马上为你|稍后|稍候)'),
    RegExp(r'(需要|需)先(联网)?(检索|搜索|查询|查找|核验)'),
  ];
  return patterns.any((pattern) => pattern.hasMatch(normalized));
}

String? _tryExtractJsonObject(String text) {
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
    return null;
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

List<String> _readStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return List.unmodifiable(_uniqueNonEmptyStrings([
    for (final item in value) item.toString(),
  ]));
}

List<String> _uniqueNonEmptyStrings(Iterable<String> values) {
  final result = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty && !result.contains(trimmed)) {
      result.add(trimmed);
    }
  }
  return result;
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

String _emptyAsNone(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? '（空）' : trimmed;
}
