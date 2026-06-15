import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/api_config.dart';
import '../models/poem.dart';
import '../models/poem_collection.dart';
import '../services/openai_api_service.dart';
import '../services/poem_agent_service.dart';
import '../services/poem_text_format_service.dart';
import '../services/prosody_service.dart';
import '../services/web_search_service.dart';

class PoemAgentChatScreen extends StatefulWidget {
  const PoemAgentChatScreen({
    super.key,
    this.currentCollection,
    this.focusPoem,
  });

  final PoemCollection? currentCollection;
  final Poem? focusPoem;

  @override
  State<PoemAgentChatScreen> createState() => _PoemAgentChatScreenState();
}

class _PoemAgentChatScreenState extends State<PoemAgentChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatBubbleData> _messages = <_ChatBubbleData>[];
  final List<PoemAgentMessage> _agentHistory = <PoemAgentMessage>[];
  final _agentService = const PoemAgentService();

  ApiConfig? _apiConfig;
  List<PoemCollection> _collections = const <PoemCollection>[];
  Map<int, List<Poem>> _poemsByCollection = const <int, List<Poem>>{};
  Future<void> _pendingMessageSave = Future<void>.value();
  Poem? _focusPoem;
  bool _loading = true;
  bool _sending = false;
  bool _changed = false;

  String get _screenTitle {
    final focusPoem = _focusPoem;
    if (focusPoem != null) {
      return '《${focusPoem.title}》助手';
    }
    return widget.currentCollection == null
        ? '诗词库助手'
        : '${widget.currentCollection!.name}助手';
  }

  @override
  void initState() {
    super.initState();
    _focusPoem = widget.focusPoem;
    _loadContext();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    try {
      final database = AppDatabase.instance;
      final config = await database.getActiveApiConfig();
      final collections = await database.getCollections();
      final poemsByCollection = await _loadPoemsByCollection(
        database,
        collections,
      );
      final savedMessages = await database.getPoemAgentMessages(_chatScopeKey);

      if (!mounted) {
        return;
      }

      setState(() {
        _apiConfig = config;
        _collections = collections;
        _poemsByCollection = poemsByCollection;
        _restoreMessages(savedMessages);
        _loading = false;
      });

      if (savedMessages.isEmpty) {
        _addAssistantMessage(_buildInitialMessage(config, collections));
      } else {
        _scrollToBottom();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
      });
      _addAssistantMessage('初始化失败：$error');
    }
  }

  String get _chatScopeKey {
    final collectionId = widget.currentCollection?.id;
    if (collectionId == null) {
      return 'collections';
    }
    final focusPoemId = _focusPoem?.id;
    if (focusPoemId != null) {
      return 'poem:$focusPoemId';
    }
    return 'collection:$collectionId';
  }

  String _buildInitialMessage(
    ApiConfig? config,
    List<PoemCollection> collections,
  ) {
    if (config == null) {
      return '请先在“API管理”中添加并选中一个可用的 API 配置。';
    }
    if (collections.isEmpty) {
      return '当前还没有诗词库。请先创建诗词库，再让我帮你添加或编辑诗词。';
    }
    if (widget.currentCollection == null) {
      return '你可以告诉我要把一首或多首诗添加到哪个诗词库，也可以让我修改已有诗词。信息不唯一时，我会继续追问。';
    }
    final focusPoem = _focusPoem;
    if (focusPoem != null) {
      return '当前学习的是《${focusPoem.title}》。你可以直接问这首诗的字词、句意、结构、赏析；也可以让我补充或更正它的译文、注释、学习笔记和赏析，我会在信息确定时直接写回诗词库。';
    }
    return '当前目标诗词库是“${widget.currentCollection!.name}”。你可以直接说要添加一首或多首诗，也可以让我补充译文、学习笔记、赏析、注释或更正某首诗。';
  }

  void _restoreMessages(List<Map<String, Object?>> savedMessages) {
    _messages.clear();
    _agentHistory.clear();

    for (final row in savedMessages) {
      final role = row['role'] as String? ?? '';
      final content = row['content'] as String? ?? '';
      if (content.trim().isEmpty) {
        continue;
      }

      final normalizedRole = role == 'user' ? 'user' : 'assistant';
      final cleanedContent = normalizedRole == 'assistant'
          ? _cleanAssistantDisplayText(content)
          : content;
      final displayContent = cleanedContent.isEmpty
          ? content.trim()
          : cleanedContent;
      _messages.add(
        normalizedRole == 'user'
            ? _ChatBubbleData.user(displayContent)
            : _ChatBubbleData.assistant(displayContent),
      );
      _agentHistory.add(
        PoemAgentMessage(role: normalizedRole, content: displayContent),
      );
    }
  }

  String _cleanAssistantDisplayText(String content) {
    var text = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
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

  Future<Map<int, List<Poem>>> _loadPoemsByCollection(
    AppDatabase database,
    List<PoemCollection> collections,
  ) async {
    final poemsByCollection = <int, List<Poem>>{};
    for (final collection in collections) {
      final id = collection.id;
      if (id == null) {
        continue;
      }
      poemsByCollection[id] = await database.getPoems(id);
    }
    return poemsByCollection;
  }

  Future<void> _reloadPoemContext() async {
    final database = AppDatabase.instance;
    final collections = await database.getCollections();
    final poemsByCollection = await _loadPoemsByCollection(
      database,
      collections,
    );

    if (!mounted) {
      return;
    }
    final refreshedFocusPoem = _findPoemByIdInMap(
      poemsByCollection,
      _focusPoem?.id,
      preferredCollectionId: widget.currentCollection?.id,
    );
    setState(() {
      _collections = collections;
      _poemsByCollection = poemsByCollection;
      if (refreshedFocusPoem != null) {
        _focusPoem = refreshedFocusPoem;
      }
    });
  }

  void _addAssistantMessage(String content) {
    if (!mounted) {
      return;
    }
    final cleanedContent = _cleanAssistantDisplayText(content);
    final displayContent = cleanedContent.isEmpty
        ? content.trim()
        : cleanedContent;
    setState(() {
      _messages.add(_ChatBubbleData.assistant(displayContent));
      _agentHistory.add(
        PoemAgentMessage(role: 'assistant', content: displayContent),
      );
    });
    _saveMessage(role: 'assistant', content: displayContent);
    _scrollToBottom();
  }

  void _addUserMessage(String content) {
    if (!mounted) {
      return;
    }
    setState(() {
      _messages.add(_ChatBubbleData.user(content));
      _agentHistory.add(PoemAgentMessage(role: 'user', content: content));
    });
    _saveMessage(role: 'user', content: content);
    _scrollToBottom();
  }

  void _saveMessage({required String role, required String content}) {
    final scopeKey = _chatScopeKey;
    _pendingMessageSave = _pendingMessageSave
        .then(
          (_) => AppDatabase.instance.addPoemAgentMessage(
            scopeKey: scopeKey,
            role: role,
            content: content,
          ),
        )
        .catchError((_) {});
  }

  Future<void> _sendMessage() async {
    final config = _apiConfig;
    final text = _inputController.text.trim();
    if (_sending || text.isEmpty) {
      return;
    }
    if (config == null) {
      _showSnackBar('请先配置可用 API');
      return;
    }
    if (_collections.isEmpty) {
      _showSnackBar('请先创建诗词库');
      return;
    }

    _inputController.clear();
    _addUserMessage(text);

    setState(() {
      _sending = true;
    });

    try {
      final result = await _agentService.send(
        config: config,
        history: _agentHistory,
        collections: _collections,
        poemsByCollection: _poemsByCollection,
        currentCollection: widget.currentCollection,
        focusPoem: _focusPoem,
      );
      await _handleAgentResult(result);
    } on ApiRequestException catch (error) {
      _addAssistantMessage('请求失败：${error.toString()}');
    } on SearchRequestException catch (error) {
      _addAssistantMessage('联网搜索失败：${error.toString()}');
    } on FormatException catch (error) {
      _addAssistantMessage('模型返回格式无法解析：${error.message}');
    } catch (error) {
      _addAssistantMessage('执行失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _handleAgentResult(PoemAgentResult result) async {
    if (result.shouldUpdatePoem) {
      await _updatePoemFromAgent(result);
      return;
    }

    if (result.type == 'update_poem') {
      _addAssistantMessage('我还不能确定要修改哪一首诗。请补充诗词库、作者、标题、首句或备注，让目标唯一。');
      return;
    }

    if (result.shouldAddPoem) {
      await _addPoemFromAgent(result);
      return;
    }

    if (result.shouldAddPoems) {
      await _addPoemsFromAgent(result);
      return;
    }

    if (result.type == 'add_poems') {
      _addAssistantMessage('我还没有拿到所有诗词的完整信息。请补充作者、标题、首句或目标诗词库。');
      return;
    }

    _addAssistantMessage(_messageWithSources(result.message, result.searchSources));
  }

  Future<void> _addPoemFromAgent(PoemAgentResult result) async {
    final collectionId = result.collectionId;
    var draft = result.poem!;
    draft = _normalizeDraftContent(draft);
    if (collectionId == null ||
        !_collections.any((item) => item.id == collectionId)) {
      _addAssistantMessage('我还不能确定要添加到哪个诗词库。请说明目标诗词库名称。');
      return;
    }
    if (!draft.isComplete) {
      _addAssistantMessage('我还没有拿到足够完整的诗词信息。请补充作者、标题或首句。');
      return;
    }
    final punctuationError = _validateContentPunctuation(
      draft.content,
      title: draft.title,
    );
    if (punctuationError != null) {
      _addAssistantMessage(
        '我未能搜索到《${draft.title}》带完整标点和可靠分行的全文，所以没有写入。\n\n$punctuationError',
      );
      return;
    }
    final annotationCheck = _normalizeAnnotation(
      content: draft.content,
      annotation: draft.annotation,
    );
    if (annotationCheck.blockingError != null) {
      _addAssistantMessage('模型返回的《${draft.title}》注释无法处理，所以我没有写入。\n\n${annotationCheck.blockingError}');
      return;
    }

    await AppDatabase.instance.createPoem(
      collectionId: collectionId,
      title: draft.title,
      author: draft.author,
      dynasty: draft.dynasty,
      preface: draft.preface,
      content: draft.content,
      remark: draft.remark,
      translation: draft.translation,
      annotation: annotationCheck.annotation,
      learningNote: draft.learningNote,
      appreciation: draft.appreciation,
    );

    _changed = true;
    final collectionName = _collections
        .firstWhere((item) => item.id == collectionId)
        .name;
    await _reloadPoemContext();

    final message = result.message.trim().isEmpty
        ? '已将《${draft.title}》添加到“$collectionName”。'
        : '${result.message}\n\n已将《${draft.title}》添加到“$collectionName”。';
    final warning = _annotationWarningForTitle(draft.title, annotationCheck);
    final displayMessage = warning == null
        ? message
        : '$message\n\n$warning\n可以稍后让我“重新整理《${draft.title}》的注释”。';
    _addAssistantMessage(
      _messageWithSources(displayMessage, result.searchSources),
    );
  }

  Future<void> _addPoemsFromAgent(PoemAgentResult result) async {
    final collectionId = result.collectionId;
    final drafts = result.poems
        .map(_normalizeDraftContent)
        .toList(growable: false);
    if (collectionId == null ||
        !_collections.any((item) => item.id == collectionId)) {
      _addAssistantMessage('我还不能确定要添加到哪个诗词库。请说明目标诗词库名称。');
      return;
    }
    if (drafts.isEmpty) {
      _addAssistantMessage('我还没有拿到要添加的诗词清单。请重新说明要添加哪些诗。');
      return;
    }

    final incompleteDrafts = drafts
        .where((draft) => !draft.isComplete)
        .map((draft) => draft.title.isEmpty ? '未命名诗词' : '《${draft.title}》')
        .toList(growable: false);
    if (incompleteDrafts.isNotEmpty) {
      _addAssistantMessage(
        '以下诗词信息还不完整，所以我没有执行批量入库：${incompleteDrafts.join('、')}。请补充作者、标题或首句。',
      );
      return;
    }
    final punctuationErrors = <String>[];
    for (final draft in drafts) {
      final punctuationError = _validateContentPunctuation(
        draft.content,
        title: draft.title,
      );
      if (punctuationError != null) {
        punctuationErrors.add('《${draft.title}》：$punctuationError');
      }
    }
    if (punctuationErrors.isNotEmpty) {
      _addAssistantMessage(
        '以下诗词未能搜索到带完整标点和可靠分行的全文，所以我没有执行批量入库：\n${punctuationErrors.join('\n')}',
      );
      return;
    }
    final annotationChecks = [
      for (final draft in drafts)
        _normalizeAnnotation(
          content: draft.content,
          annotation: draft.annotation,
        ),
    ];

    for (var index = 0; index < drafts.length; index += 1) {
      final draft = drafts[index];
      final annotationCheck = annotationChecks[index];
      final annotationError = annotationCheck.blockingError;
      if (annotationError != null) {
        _addAssistantMessage('模型返回的《${draft.title}》注释无法处理，所以我没有执行批量入库。\n\n$annotationError');
        return;
      }
    }

    for (var index = 0; index < drafts.length; index += 1) {
      final draft = drafts[index];
      final annotationCheck = annotationChecks[index];
      await AppDatabase.instance.createPoem(
        collectionId: collectionId,
        title: draft.title,
        author: draft.author,
        dynasty: draft.dynasty,
        preface: draft.preface,
        content: draft.content,
        remark: draft.remark,
        translation: draft.translation,
        annotation: annotationCheck.annotation,
        learningNote: draft.learningNote,
        appreciation: draft.appreciation,
      );
    }

    _changed = true;
    final collectionName = _collections
        .firstWhere((item) => item.id == collectionId)
        .name;
    await _reloadPoemContext();

    final titles = drafts.map((draft) => '《${draft.title}》').join('、');
    final message = result.message.trim().isEmpty
        ? '已将 $titles 添加到“$collectionName”。'
        : '${result.message}\n\n已将 $titles 添加到“$collectionName”。';
    final warnings = <String>[];
    for (var index = 0; index < drafts.length; index += 1) {
      final warning = _annotationWarningForTitle(
        drafts[index].title,
        annotationChecks[index],
      );
      if (warning != null) {
        warnings.add(warning);
      }
    }
    final displayMessage = warnings.isEmpty
        ? message
        : '$message\n\n注释处理：\n${warnings.join('\n')}';
    _addAssistantMessage(
      _messageWithSources(displayMessage, result.searchSources),
    );
  }

  Future<void> _updatePoemFromAgent(PoemAgentResult result) async {
    final poemId = result.poemId;
    final updates = result.updates;
    if (poemId == null || updates == null) {
      _addAssistantMessage('我还不能确定要修改哪一首诗。请补充更多信息。');
      return;
    }
    if (!updates.hasChanges) {
      _addAssistantMessage('我已经找到了诗词，但没有收到明确要修改的字段。请说明要修改内容、注释、学习笔记、赏析还是其它信息。');
      return;
    }

    final existing = _findPoemById(poemId);
    if (existing == null) {
      _addAssistantMessage('我没有在当前本地诗词清单中找到这个诗词元素。请重新指定诗词库、标题、作者或首句。');
      return;
    }

    var updatedPoem = updates.applyTo(existing);
    if (updates.values.containsKey('content')) {
      updatedPoem = updatedPoem.copyWith(
        content: normalizePoemContentLayout(
          updatedPoem.content,
          title: updatedPoem.title,
        ),
      );
    }
    if (_shouldRefreshProsody(updates)) {
      final inferredProsody = inferProsodyMetadata(
        title: updatedPoem.title,
        dynasty: updatedPoem.dynasty,
        content: updatedPoem.content,
        remark: updatedPoem.remark,
      );
      final useInferredEnabled =
          existing.prosodySystem == Poem.prosodySystemUnknown;
      updatedPoem = updatedPoem.copyWith(
        prosodySupported: inferredProsody.supported,
        prosodyEnabled: inferredProsody.supported &&
            (useInferredEnabled ? inferredProsody.enabled : existing.prosodyEnabled),
        prosodySystem: inferredProsody.system,
        prosodyForm: inferredProsody.form,
        prosodyRhymeBook: existing.prosodyRhymeBook.trim().isEmpty
            ? inferredProsody.rhymeBook
            : existing.prosodyRhymeBook,
        prosodyNote: inferredProsody.note,
        clearProsodyVerification: true,
      );
    }
    if (updates.values.containsKey('prosody_overrides_json')) {
      updatedPoem = updatedPoem.copyWith(
        prosodyOverridesJson: updates.values['prosody_overrides_json'],
        prosodyVerifiedAt: DateTime.now(),
        prosodyVerifiedBy: 'agent',
      );
    }
    if (updatedPoem.title.trim().isEmpty ||
        updatedPoem.author.trim().isEmpty ||
        updatedPoem.content.trim().isEmpty) {
      _addAssistantMessage('这次修改会导致标题、作者或内容变为空，所以我没有写入。请重新说明要修改的内容。');
      return;
    }
    if (updates.values.containsKey('content')) {
      final punctuationError = _validateContentPunctuation(
        updatedPoem.content,
        title: updatedPoem.title,
      );
      if (punctuationError != null) {
        _addAssistantMessage('我未能确认带完整标点和可靠分行的正文，所以没有写入。\n\n$punctuationError');
        return;
      }
    }
    if (updates.values.containsKey('annotation') ||
        updates.values.containsKey('content')) {
      final annotationError = _validateAnnotationFormat(
        content: updatedPoem.content,
        annotation: updatedPoem.annotation,
      );
      if (annotationError != null) {
        _addAssistantMessage('模型返回的注释格式不符合规范，所以我没有写入。\n\n$annotationError');
        return;
      }
    }

    await AppDatabase.instance.updatePoem(updatedPoem);

    _changed = true;
    await _reloadPoemContext();

    final fields = updates.changedFieldLabels.join('、');
    final suffix = fields.isEmpty ? '' : '的$fields';
    final message = result.message.trim().isEmpty
        ? '已更新《${updatedPoem.title}》$suffix。'
        : '${result.message}\n\n已更新《${updatedPoem.title}》$suffix。';
    _addAssistantMessage(_messageWithSources(message, result.searchSources));
  }

  PoemAgentDraft _normalizeDraftContent(PoemAgentDraft draft) {
    return draft.copyWith(
      content: normalizePoemContentLayout(
        draft.content,
        title: draft.title,
      ),
    );
  }

  String? _validateContentPunctuation(String content, {String title = ''}) {
    return validatePoemContentLayout(content, title: title)?.message;
  }

  bool _shouldRefreshProsody(PoemAgentUpdates updates) {
    return updates.values.containsKey('title') ||
        updates.values.containsKey('dynasty') ||
        updates.values.containsKey('content') ||
        updates.values.containsKey('remark');
  }

  String _messageWithSources(String message, List<String> sources) {
    if (sources.isEmpty) {
      return message;
    }

    final sourceText = sources.take(5).join('\n');
    return '$message\n\n参考来源：\n$sourceText';
  }

  String? _validateAnnotationFormat({
    required String content,
    required String annotation,
  }) {
    final annotationCheck = _normalizeAnnotation(
      content: content,
      annotation: annotation,
    );
    if (annotationCheck.blockingError != null) {
      return annotationCheck.blockingError;
    }
    if (annotationCheck.skippedLines.isEmpty) {
      return null;
    }
    return annotationCheck.skippedLines.first;
  }

  _AnnotationCheck _normalizeAnnotation({
    required String content,
    required String annotation,
  }) {
    final trimmedAnnotation = annotation.trim();
    if (trimmedAnnotation.isEmpty) {
      return const _AnnotationCheck(annotation: '');
    }
    final contentLineCount = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .length;
    if (contentLineCount == 0) {
      return const _AnnotationCheck(
        annotation: '',
        blockingError: '原文内容为空，无法校验注释行号。',
      );
    }

    final annotationLines = trimmedAnnotation
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    final linePattern = RegExp(r'^\[(\d+)\]\s*\S');
    final validLines = <String>[];
    final skippedLines = <String>[];

    for (var index = 0; index < annotationLines.length; index += 1) {
      final line = annotationLines[index].trim();
      final match = linePattern.firstMatch(line);
      if (match == null) {
        skippedLines.add('注释第 ${index + 1} 行没有以 [行号] 开头：$line');
        continue;
      }

      final lineNumber = int.tryParse(match.group(1)!);
      if (lineNumber == null ||
          lineNumber < 0 ||
          lineNumber > contentLineCount) {
        skippedLines.add(
          '注释第 ${index + 1} 行使用了 [$lineNumber]，但原文只有 $contentLineCount 个非空行；[0] 仅用于标题注释。',
        );
        continue;
      }
      validLines.add(line);
    }

    return _AnnotationCheck(
      annotation: validLines.join('\n'),
      skippedLines: List.unmodifiable(skippedLines),
    );
  }

  String? _annotationWarningForTitle(
    String title,
    _AnnotationCheck annotationCheck,
  ) {
    if (annotationCheck.skippedLines.isEmpty) {
      return null;
    }

    final details = annotationCheck.skippedLines.take(3).join('；');
    final remainingCount = annotationCheck.skippedLines.length - 3;
    final remainingText = remainingCount > 0 ? '；另有 $remainingCount 条。' : '。';
    return '《$title》有 ${annotationCheck.skippedLines.length} 条注释未能和正文行号对齐，已跳过：$details$remainingText';
  }

  Poem? _findPoemById(int poemId) {
    final currentCollectionId = widget.currentCollection?.id;
    if (currentCollectionId != null) {
      final currentPoems = _poemsByCollection[currentCollectionId];
      if (currentPoems != null) {
        for (final poem in currentPoems) {
          if (poem.id == poemId) {
            return poem;
          }
        }
      }
    }

    for (final poems in _poemsByCollection.values) {
      for (final poem in poems) {
        if (poem.id == poemId) {
          return poem;
        }
      }
    }
    return null;
  }

  Poem? _findPoemByIdInMap(
    Map<int, List<Poem>> poemsByCollection,
    int? poemId, {
    int? preferredCollectionId,
  }) {
    if (poemId == null) {
      return null;
    }

    final preferredPoems = preferredCollectionId == null
        ? null
        : poemsByCollection[preferredCollectionId];
    if (preferredPoems != null) {
      for (final poem in preferredPoems) {
        if (poem.id == poemId) {
          return poem;
        }
      }
    }

    for (final poems in poemsByCollection.values) {
      for (final poem in poems) {
        if (poem.id == poemId) {
          return poem;
        }
      }
    }
    return null;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _resetConversation() async {
    if (_sending) {
      _showSnackBar('请等待当前回复完成后再重置对话');
      return;
    }

    final resetMode = await showDialog<_ConversationResetMode>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('清除并重置对话'),
          content: const Text(
            '这只会清除助手对话历史，不会影响诗词库内容。若担心其它页面残留旧上下文，可以清除全部助手对话。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                _ConversationResetMode.all,
              ),
              child: const Text('清除全部'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _ConversationResetMode.current,
              ),
              child: const Text('清除当前'),
            ),
          ],
        );
      },
    );

    if (resetMode == null) {
      return;
    }

    try {
      final scopeKey = _chatScopeKey;
      await _pendingMessageSave;
      if (resetMode == _ConversationResetMode.all) {
        await AppDatabase.instance.clearAllPoemAgentMessages();
      } else {
        await AppDatabase.instance.clearPoemAgentMessages(scopeKey);
      }
      if (!mounted) {
        return;
      }

      setState(() {
        _messages.clear();
        _agentHistory.clear();
      });
      _addAssistantMessage(_buildInitialMessage(_apiConfig, _collections));
      _showSnackBar(
        resetMode == _ConversationResetMode.all
            ? '已清除全部助手对话'
            : '已重置当前对话',
      );
    } catch (error) {
      _showSnackBar('重置失败：$error');
    }
  }

  Future<bool> _onWillPop() async {
    await _close();
    return false;
  }

  Future<void> _close() async {
    await _pendingMessageSave;
    if (!mounted) {
      return;
    }
    Navigator.pop(context, _changed);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '返回',
            onPressed: _close,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            _screenTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: '清除并重置对话',
              onPressed: _loading || _sending ? null : _resetConversation,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ChatBubble(message: message),
                          );
                        },
                      ),
              ),
              if (_sending) const LinearProgressIndicator(minHeight: 2),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: '例如：添加《使至塞上》和《赠汪伦》，或补充《春望》的译文',
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: '发送',
                      onPressed: _sending ? null : _sendMessage,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatBubbleData {
  const _ChatBubbleData({required this.content, required this.isUser});

  factory _ChatBubbleData.user(String content) {
    return _ChatBubbleData(content: content, isUser: true);
  }

  factory _ChatBubbleData.assistant(String content) {
    return _ChatBubbleData(content: content, isUser: false);
  }

  final String content;
  final bool isUser;
}

class _AnnotationCheck {
  const _AnnotationCheck({
    required this.annotation,
    this.blockingError,
    this.skippedLines = const <String>[],
  });

  final String annotation;
  final String? blockingError;
  final List<String> skippedLines;
}

enum _ConversationResetMode { current, all }

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _ChatBubbleData message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alignment =
        message.isUser ? Alignment.centerRight : Alignment.centerLeft;
    final background = message.isUser
        ? theme.colorScheme.primary
        : const Color(0xFFFFF4C7);
    final foreground =
        message.isUser ? theme.colorScheme.onPrimary : const Color(0xFF4F3B12);

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 310),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: message.isUser
                ? null
                : Border.all(color: const Color(0xFFEEDC9A)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: SelectableText(
              message.content,
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
