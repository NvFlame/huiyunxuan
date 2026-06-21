import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/app_database.dart';
import '../models/poem.dart';
import '../models/poem_collection.dart';
import '../services/prosody_ai_service.dart';
import '../services/regulated_verse_checker.dart';
import '../widgets/prosody_calibration_dialog.dart';
import '../widgets/prosody_panel.dart';
import '../widgets/tone_marked_text.dart';
import 'poem_agent_chat_screen.dart';

class LearningModeScreen extends StatefulWidget {
  const LearningModeScreen({super.key});

  @override
  State<LearningModeScreen> createState() => _LearningModeScreenState();
}

class _LearningModeScreenState extends State<LearningModeScreen> {
  static const double _annotationScrollTopPadding = 72;

  final _learningScrollController = ScrollController();
  final _learningListKey = GlobalKey();
  final _annotationSectionKey = GlobalKey();
  final Map<int, GlobalKey> _annotationLineKeys = <int, GlobalKey>{};
  List<PoemCollection> _collections = const <PoemCollection>[];
  List<Poem> _poems = const <Poem>[];
  PoemCollection? _selectedCollection;
  Set<int> _currentPoemCollectionIds = const <int>{};
  int _currentIndex = 0;
  bool _annotationExpanded = true;
  double? _returnScrollOffset;
  int? _highlightedAnnotationLine;
  int _annotationJumpToken = 0;
  int? _previewLineNumber;
  List<String> _previewAnnotationNotes = const <String>[];
  int _previewToken = 0;
  bool _showToneMarks = false;
  bool _prosodyCalibrating = false;
  final _poemContentKey = GlobalKey<_PoemContentViewState>();
  bool _contentSelectionActive = false;
  bool _contentSelectionWasActiveOnPointerDown = false;
  bool _loading = true;
  String? _error;

  Poem? get _currentPoem {
    if (_poems.isEmpty || _currentIndex < 0 || _currentIndex >= _poems.length) {
      return null;
    }
    return _poems[_currentIndex];
  }

  bool get _canGoPrevious => _currentIndex > 0;
  bool get _canGoNext => _currentIndex < _poems.length - 1;
  Set<int> get _favoriteTargetCollectionIds {
    final currentCollectionId = _selectedCollection?.id;
    return {
      for (final collection in _collections)
        if (collection.id != null &&
            (collection.id != currentCollectionId || collection.isFavorites))
          collection.id!,
    };
  }

  Set<int> get _selectedFavoriteTargetIds {
    return _currentPoemCollectionIds.intersection(_favoriteTargetCollectionIds);
  }

  bool get _isCurrentPoemFavorited => _selectedFavoriteTargetIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  @override
  void dispose() {
    _learningScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialState() async {
    try {
      final database = AppDatabase.instance;
      final collections = await database.getCollections();
      if (collections.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _collections = const <PoemCollection>[];
          _selectedCollection = null;
          _poems = const <Poem>[];
          _loading = false;
          _error = null;
        });
        return;
      }

      final lastCollectionId = await database.getLastLearningCollectionId();
      final selectedCollection =
          _findCollectionById(collections, lastCollectionId) ??
              collections.first;
      final loadResult = await _loadCollectionData(selectedCollection);
      final poemCollectionIds = await _loadPoemCollectionIds(
        loadResult.currentPoemId,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _collections = collections;
        _selectedCollection = selectedCollection;
        _poems = loadResult.poems;
        _currentIndex = loadResult.index;
        _currentPoemCollectionIds = poemCollectionIds;
        _loading = false;
        _error = null;
      });
      await _saveCurrentProgress();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<_LoadedCollection> _loadCollectionData(
    PoemCollection collection, {
    int? preferredPoemId,
  }) async {
    final id = collection.id;
    if (id == null) {
      return const _LoadedCollection(poems: <Poem>[], index: 0);
    }

    final database = AppDatabase.instance;
    final poems = await database.getPoems(id);
    if (poems.isEmpty) {
      return const _LoadedCollection(poems: <Poem>[], index: 0);
    }

    final savedPoemId =
        preferredPoemId ?? (await database.getLearningProgressPoemId(id));
    final savedIndex = poems.indexWhere((poem) => poem.id == savedPoemId);
    return _LoadedCollection(
      poems: poems,
      index: savedIndex >= 0 ? savedIndex : 0,
    );
  }

  PoemCollection? _findCollectionById(
    List<PoemCollection> collections,
    int? id,
  ) {
    if (id == null) {
      return null;
    }
    for (final collection in collections) {
      if (collection.id == id) {
        return collection;
      }
    }
    return null;
  }

  Future<void> _switchCollection(int collectionId) async {
    final collection = _findCollectionById(_collections, collectionId);
    if (collection == null || collection.id == _selectedCollection?.id) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final loadResult = await _loadCollectionData(collection);
      final poemCollectionIds = await _loadPoemCollectionIds(
        loadResult.currentPoemId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedCollection = collection;
        _poems = loadResult.poems;
        _currentIndex = loadResult.index;
        _currentPoemCollectionIds = poemCollectionIds;
        _loading = false;
        _resetLineAnnotationState();
      });
      await _saveCurrentProgress();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _reloadCurrentCollection({int? preferredPoemId}) async {
    final collection = _selectedCollection;
    if (collection == null) {
      return;
    }

    final loadResult = await _loadCollectionData(
      collection,
      preferredPoemId: preferredPoemId,
    );
    final poemCollectionIds = await _loadPoemCollectionIds(
      loadResult.currentPoemId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _poems = loadResult.poems;
      _currentIndex = loadResult.index;
      _currentPoemCollectionIds = poemCollectionIds;
      _resetLineAnnotationState();
    });
    await _saveCurrentProgress();
  }

  Future<Set<int>> _loadPoemCollectionIds(int? poemId) async {
    if (poemId == null) {
      return const <int>{};
    }
    return AppDatabase.instance.getPoemCollectionIds(poemId);
  }

  Future<void> _refreshCollectionsAndFavoriteState() async {
    final poemId = _currentPoem?.id;
    final database = AppDatabase.instance;
    final collections = await database.getCollections();
    final poemCollectionIds = await _loadPoemCollectionIds(poemId);
    if (!mounted) {
      return;
    }
    setState(() {
      _collections = collections;
      _currentPoemCollectionIds = poemCollectionIds;
    });
  }

  Future<void> _goToIndex(int index) async {
    if (index < 0 || index >= _poems.length || index == _currentIndex) {
      return;
    }
    final poemCollectionIds = await _loadPoemCollectionIds(_poems[index].id);
    if (!mounted) {
      return;
    }
    setState(() {
      _currentIndex = index;
      _currentPoemCollectionIds = poemCollectionIds;
      _resetLineAnnotationState();
    });
    _scrollLearningToTopAfterFrame();
    await _saveCurrentProgress();
  }

  void _scrollLearningToTopAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_learningScrollController.hasClients) {
        return;
      }
      _learningScrollController.jumpTo(
        _learningScrollController.position.minScrollExtent,
      );
    });
  }

  void _resetLineAnnotationState() {
    _annotationLineKeys.clear();
    _annotationExpanded = true;
    _returnScrollOffset = null;
    _highlightedAnnotationLine = null;
    _annotationJumpToken += 1;
    _previewLineNumber = null;
    _previewAnnotationNotes = const <String>[];
    _previewToken += 1;
  }

  Future<void> _saveCurrentProgress() async {
    final collectionId = _selectedCollection?.id;
    final poemId = _currentPoem?.id;
    if (collectionId == null || poemId == null) {
      return;
    }

    await AppDatabase.instance.saveLearningProgress(
      collectionId: collectionId,
      poemId: poemId,
    );
  }

  Future<void> _showPoemSearch() async {
    if (_poems.isEmpty) {
      return;
    }

    final selected = await showModalBottomSheet<Poem>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PoemSearchSheet(poems: _poems),
    );
    if (selected == null) {
      return;
    }

    final index = _poems.indexWhere((poem) => poem.id == selected.id);
    if (index >= 0) {
      await _goToIndex(index);
    }
  }

  Future<void> _openPoemChat({String? initialInput}) async {
    final collection = _selectedCollection;
    final poem = _currentPoem;
    if (collection == null || poem == null) {
      return;
    }

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PoemAgentChatScreen(
          currentCollection: collection,
          focusPoem: poem,
          initialInput: initialInput,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _reloadCurrentCollection(preferredPoemId: poem.id);
    }
  }

  Future<void> _saveLearningNote(Poem poem, String note) async {
    final nextNote = note.trim();
    if (nextNote == poem.learningNote.trim()) {
      return;
    }

    final updatedPoem = poem.copyWith(learningNote: nextNote);
    await AppDatabase.instance.updatePoem(
      updatedPoem,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      final index = _poems.indexWhere((item) => item.id == poem.id);
      if (index < 0) {
        return;
      }
      final poems = List<Poem>.of(_poems);
      poems[index] = updatedPoem;
      _poems = List.unmodifiable(poems);
    });
  }

  Future<void> _openProsodyCalibrationDialog(Poem poem) async {
    final nextOverridesJson = await showDialog<String>(
      context: context,
      builder: (context) => ProsodyCalibrationDialog(poem: poem),
    );
    if (nextOverridesJson == null || !mounted) {
      return;
    }
    await AppDatabase.instance.updatePoem(
      poem.copyWith(
        prosodyOverridesJson: nextOverridesJson,
        prosodyVerifiedAt: DateTime.now(),
        prosodyVerifiedBy: 'user',
      ),
    );
    await _reloadCurrentCollection(preferredPoemId: poem.id);
    _showSnackBar('已保存人工校准');
  }

  Future<void> _runProsodyAiCalibration(Poem poem) async {
    if (_prosodyCalibrating) {
      return;
    }
    final config = await AppDatabase.instance.getActiveApiConfig();
    if (config == null) {
      _showSnackBar('请先在设置中选择可用配置');
      return;
    }

    setState(() {
      _prosodyCalibrating = true;
    });
    try {
      final overridesJson = await const ProsodyAiService().calibrate(
        config: config,
        poem: poem,
      );
      await AppDatabase.instance.updatePoem(
        poem.copyWith(
          prosodyOverridesJson: overridesJson,
          prosodyVerifiedAt: DateTime.now(),
          prosodyVerifiedBy: 'agent',
        ),
      );
      await _reloadCurrentCollection(preferredPoemId: poem.id);
      _showSnackBar('智能校准已写回诗词库');
    } catch (error) {
      _showSnackBar('智能校准失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _prosodyCalibrating = false;
        });
      }
    }
  }

  Future<void> _showJumpDialog() async {
    if (_poems.isEmpty) {
      return;
    }

    final targetPage = await showDialog<int>(
      context: context,
      builder: (context) {
        return _JumpToPoemDialog(
          initialPage: _currentIndex + 1,
          total: _poems.length,
        );
      },
    );
    if (targetPage == null) {
      return;
    }
    await _goToIndex(targetPage - 1);
  }

  Future<void> _toggleFavorite() async {
    final poem = _currentPoem;
    final poemId = poem?.id;
    if (poem == null || poemId == null) {
      return;
    }

    if (!_isCurrentPoemFavorited) {
      final favoriteCollection =
          await AppDatabase.instance.getOrCreateFavoritesCollection();
      final favoriteCollectionId = favoriteCollection.id;
      if (favoriteCollectionId == null) {
        return;
      }
      await AppDatabase.instance.addPoemsToCollection(
        collectionId: favoriteCollectionId,
        poemIds: [poemId],
      );
      await _refreshCollectionsAndFavoriteState();
      if (mounted) {
        _showSnackBar('已收藏到“${favoriteCollection.name}”');
      }
      return;
    }

    final selectableCollections = _favoriteSelectableCollections();
    final selectedIds = await showDialog<Set<int>>(
      context: context,
      builder: (context) {
        return _FavoriteCollectionsDialog(
          collections: selectableCollections,
          initialSelectedIds: _selectedFavoriteTargetIds,
        );
      },
    );
    if (selectedIds == null) {
      return;
    }

    final selectableIds = selectableCollections
        .map((collection) => collection.id)
        .whereType<int>()
        .toSet();
    final currentSelectedIds = _currentPoemCollectionIds.intersection(
      selectableIds,
    );
    final idsToAdd = selectedIds.difference(currentSelectedIds);
    final idsToRemove = currentSelectedIds.difference(selectedIds);

    for (final collectionId in idsToAdd) {
      await AppDatabase.instance.addPoemsToCollection(
        collectionId: collectionId,
        poemIds: [poemId],
      );
    }
    for (final collectionId in idsToRemove) {
      await AppDatabase.instance.removePoemsFromCollection(
        collectionId: collectionId,
        poemIds: [poemId],
      );
    }

    await _refreshCollectionsAndFavoriteState();
    if (idsToRemove.contains(_selectedCollection?.id)) {
      await _reloadCurrentCollection();
    }
    if (mounted) {
      _showSnackBar(selectedIds.isEmpty ? '已取消收藏' : '已更新收藏');
    }
  }

  List<PoemCollection> _favoriteSelectableCollections() {
    final currentCollectionId = _selectedCollection?.id;
    final collections = [
      for (final collection in _collections)
        if (collection.id != null &&
            (collection.id != currentCollectionId || collection.isFavorites))
          collection,
    ];
    collections.sort((a, b) {
      if (a.isFavorites != b.isFavorites) {
        return a.isFavorites ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
    return collections;
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _handleLearningPointerDown(PointerDownEvent event) {
    final contentState = _poemContentKey.currentState;
    final selectionActive =
        _contentSelectionActive || (contentState?.hasActiveSelection ?? false);
    _contentSelectionWasActiveOnPointerDown = selectionActive;
    if (!selectionActive || contentState == null) {
      return;
    }
    if (!contentState.containsGlobalPosition(event.position)) {
      contentState.clearTextSelection();
    }
  }

  void _handleContentSelectionActiveChanged(bool active) {
    if (_contentSelectionActive == active || !mounted) {
      return;
    }
    setState(() {
      _contentSelectionActive = active;
    });
  }

  void _handleToneDetailsChanged(bool value) {
    if (value &&
        (_contentSelectionActive || _contentSelectionWasActiveOnPointerDown)) {
      _contentSelectionWasActiveOnPointerDown = false;
      _poemContentKey.currentState?.clearTextSelection();
      _showSnackBar('请先取消文本选择，再开启格律审查');
      return;
    }

    _contentSelectionWasActiveOnPointerDown = false;
    setState(() {
      _showToneMarks = value;
    });
  }

  void _jumpToAnnotationLine(int lineNumber, _ParsedAnnotation annotation) {
    final notes = annotation.grouped[lineNumber];
    if (notes == null || notes.isEmpty) {
      _showSnackBar('第 $lineNumber 行暂无对应注释');
      return;
    }

    final previousOffset = _learningScrollController.hasClients
        ? _learningScrollController.offset
        : null;
    final jumpToken = _annotationJumpToken + 1;
    setState(() {
      _annotationExpanded = true;
      _returnScrollOffset = previousOffset;
      _highlightedAnnotationLine = lineNumber;
      _annotationJumpToken = jumpToken;
      _previewLineNumber = null;
      _previewAnnotationNotes = const <String>[];
      _previewToken += 1;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (!mounted || _annotationJumpToken != jumpToken) {
          return;
        }
        final targetContext =
            _annotationLineKeys[lineNumber]?.currentContext ??
                _annotationSectionKey.currentContext;
        if (targetContext == null) {
          return;
        }
        _scrollToLearningContext(targetContext);
      });
    });
  }

  void _scrollToLearningContext(
    BuildContext targetContext, {
    double topPadding = _annotationScrollTopPadding,
  }) {
    if (!_learningScrollController.hasClients) {
      return;
    }

    final targetObject = targetContext.findRenderObject();
    if (targetObject == null) {
      return;
    }

    final viewport = RenderAbstractViewport.maybeOf(targetObject);
    if (viewport == null) {
      return;
    }

    final position = _learningScrollController.position;
    final targetOffset = (viewport.getOffsetToReveal(targetObject, 0).offset -
            topPadding)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();

    _learningScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
    );
  }

  void _returnToPreviousContentPosition() {
    final offset = _returnScrollOffset;
    if (offset == null || !_learningScrollController.hasClients) {
      setState(() {
        _returnScrollOffset = null;
        _highlightedAnnotationLine = null;
      });
      return;
    }

    final position = _learningScrollController.position;
    final target = offset
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _learningScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    setState(() {
      _returnScrollOffset = null;
      _highlightedAnnotationLine = null;
    });
  }

  void _showLineAnnotationPreview(
    int lineNumber,
    _ParsedAnnotation annotation,
  ) {
    final notes = annotation.grouped[lineNumber];
    if (notes == null || notes.isEmpty) {
      _showSnackBar('第 $lineNumber 行暂无对应注释');
      return;
    }

    final token = _previewToken + 1;
    setState(() {
      _previewToken = token;
      _previewLineNumber = lineNumber;
      _previewAnnotationNotes = List.unmodifiable(notes);
    });

    Future<void>.delayed(const Duration(seconds: 6), () {
      if (!mounted || _previewToken != token) {
        return;
      }
      setState(() {
        _previewLineNumber = null;
        _previewAnnotationNotes = const <String>[];
      });
    });
  }

  void _hideLineAnnotationPreview() {
    setState(() {
      _previewToken += 1;
      _previewLineNumber = null;
      _previewAnnotationNotes = const <String>[];
    });
  }

  @override
  Widget build(BuildContext context) {
    final collection = _selectedCollection;
    final poem = _currentPoem;

    return Scaffold(
      appBar: AppBar(
        title: _LearningTitle(
          collection: collection,
          currentIndex: _poems.isEmpty ? 0 : _currentIndex + 1,
          total: _poems.length,
          onTapProgress: _poems.isEmpty ? null : _showJumpDialog,
        ),
        actions: [
          IconButton(
            tooltip: _isCurrentPoemFavorited ? '管理收藏' : '收藏',
            onPressed: _currentPoem == null ? null : _toggleFavorite,
            icon: Icon(
              _isCurrentPoemFavorited ? Icons.star : Icons.star_border,
            ),
          ),
          IconButton(
            tooltip: '搜索诗词',
            onPressed: _poems.isEmpty ? null : _showPoemSearch,
            icon: const Icon(Icons.search),
          ),
          PopupMenuButton<int>(
            tooltip: '切换诗词库',
            enabled: _collections.isNotEmpty,
            icon: const Icon(Icons.folder_open_outlined),
            onSelected: _switchCollection,
            itemBuilder: (context) {
              return [
                for (final item in _collections)
                  if (item.id != null)
                    PopupMenuItem<int>(
                      value: item.id,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 26,
                            child: item.id == collection?.id
                                ? const Icon(Icons.check, size: 18)
                                : null,
                          ),
                          Expanded(
                            child: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
              ];
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(poem),
      ),
      floatingActionButton: poem == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openPoemChat(),
              icon: const Icon(Icons.smart_toy_outlined),
              label: const Text('问道'),
            ),
    );
  }

  Widget _buildBody(Poem? poem) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _LearningMessageView(
        icon: Icons.error_outline,
        title: '学文读取失败',
        message: _error!,
      );
    }
    if (_collections.isEmpty) {
      return const _LearningMessageView(
        icon: Icons.library_add_outlined,
        title: '还没有诗词库',
        message: '请先在“诗词库管理”中创建诗词库并添加诗词。',
      );
    }
    if (_poems.isEmpty) {
      return const _LearningMessageView(
        icon: Icons.menu_book_outlined,
        title: '当前诗词库为空',
        message: '可以切换到其它诗词库，或先为当前库添加诗词。',
      );
    }
    if (poem == null) {
      return const _LearningMessageView(
        icon: Icons.error_outline,
        title: '没有可学习的诗词',
        message: '请返回后重新进入学文。',
      );
    }

    final parsedAnnotation = _parseAnnotation(poem.annotation);
    _annotationLineKeys.removeWhere(
      (lineNumber, _) => !parsedAnnotation.grouped.containsKey(lineNumber),
    );
    for (final lineNumber in parsedAnnotation.grouped.keys) {
      _annotationLineKeys.putIfAbsent(lineNumber, () => GlobalKey());
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleLearningPointerDown,
      child: Stack(
        children: [
          SingleChildScrollView(
          key: _learningListKey,
          controller: _learningScrollController,
          padding: const EdgeInsets.fromLTRB(52, 14, 52, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PoemLearningHeader(
                poem: poem,
                onAskAi: (text) => _openPoemChat(initialInput: text),
              ),
              const SizedBox(height: 12),
              _PoemContentView(
                key: _poemContentKey,
                poem: poem,
                showToneMarks: _showToneMarks &&
                    poem.prosodySupported &&
                    poem.prosodyEnabled,
                previewLineNumber: _previewLineNumber,
                previewNotes: _previewAnnotationNotes,
                onLineNumberTap: (lineNumber) {
                  _jumpToAnnotationLine(lineNumber, parsedAnnotation);
                },
                onLineTap: (lineNumber) {
                  _showLineAnnotationPreview(lineNumber, parsedAnnotation);
                },
                onAskAi: (text) => _openPoemChat(initialInput: text),
                onDismissPreview: _hideLineAnnotationPreview,
                onSelectionActiveChanged:
                    _handleContentSelectionActiveChanged,
              ),
              const SizedBox(height: 12),
              ProsodyPanel(
                poem: poem,
                showToneDetails: _showToneMarks,
                calibrationBusy: _prosodyCalibrating,
                onToneDetailsChanged: _handleToneDetailsChanged,
                onManualCalibration: () => _openProsodyCalibrationDialog(poem),
                onAiCalibration: () => _runProsodyAiCalibration(poem),
              ),
              if (poem.prosodySupported && poem.prosodyEnabled)
                const SizedBox(height: 12),
              _ControlledLearningSection(
                sectionKey: _annotationSectionKey,
                title: '注释',
                icon: Icons.notes_outlined,
                expanded: _annotationExpanded,
                onExpansionChanged: (expanded) {
                  setState(() {
                    _annotationExpanded = expanded;
                  });
                },
                child: _AnnotationView(
                  annotation: parsedAnnotation,
                  lineKeys: _annotationLineKeys,
                  highlightedLine: _highlightedAnnotationLine,
                  onAskAi: (text) => _openPoemChat(initialInput: text),
                ),
              ),
              _LearningNoteSection(
                note: poem.learningNote,
                onChanged: (note) => _saveLearningNote(poem, note),
                onAskAi: (text) => _openPoemChat(initialInput: text),
              ),
              _LearningSection(
                title: '译文',
                icon: Icons.translate,
                initiallyExpanded: false,
                child: _SelectableBlock(
                  text: poem.translation,
                  emptyText: '暂无译文。可以在编辑页补充，也可以让智能体补全。',
                  onAskAi: (text) => _openPoemChat(initialInput: text),
                ),
              ),
              _LearningSection(
                title: '赏析',
                icon: Icons.auto_stories_outlined,
                initiallyExpanded: false,
                child: _SelectableBlock(
                  text: poem.appreciation,
                  emptyText: '暂无赏析。可以让智能体先生成一个学习版赏析。',
                  onAskAi: (text) => _openPoemChat(initialInput: text),
                ),
              ),
            ],
          ),
        ),
          if (_returnScrollOffset != null)
            Positioned(
            left: 52,
            right: 52,
            bottom: 18,
            child: Center(
              child: FilledButton.tonalIcon(
                onPressed: _returnToPreviousContentPosition,
                icon: const Icon(Icons.keyboard_return),
                label: const Text('回到原位置'),
              ),
            ),
          ),
          Positioned(
          left: 6,
          top: 0,
          bottom: 0,
          child: Center(
            child: IconButton.filledTonal(
              tooltip: '上一首',
              onPressed:
                  _canGoPrevious ? () => _goToIndex(_currentIndex - 1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
          ),
        ),
          Positioned(
          right: 6,
          top: 0,
          bottom: 0,
          child: Center(
            child: IconButton.filledTonal(
              tooltip: '下一首',
              onPressed: _canGoNext
                  ? () => _goToIndex(_currentIndex + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ),
          ),
        ],
      ),
    );
  }
}

class _LoadedCollection {
  const _LoadedCollection({required this.poems, required this.index});

  final List<Poem> poems;
  final int index;

  int? get currentPoemId {
    if (poems.isEmpty || index < 0 || index >= poems.length) {
      return null;
    }
    return poems[index].id;
  }
}

class _LearningTitle extends StatelessWidget {
  const _LearningTitle({
    required this.collection,
    required this.currentIndex,
    required this.total,
    required this.onTapProgress,
  });

  final PoemCollection? collection;
  final int currentIndex;
  final int total;
  final VoidCallback? onTapProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final collectionName = collection?.name ?? '学文';
    final progress = total == 0 ? '暂无诗词' : '$currentIndex / $total';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          collectionName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTapProgress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            child: Text(
              progress,
              style: theme.textTheme.labelSmall?.copyWith(
                decoration:
                    onTapProgress == null ? null : TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _JumpToPoemDialog extends StatefulWidget {
  const _JumpToPoemDialog({required this.initialPage, required this.total});

  final int initialPage;
  final int total;

  @override
  State<_JumpToPoemDialog> createState() => _JumpToPoemDialogState();
}

class _JumpToPoemDialogState extends State<_JumpToPoemDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialPage}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < 1 || value > widget.total) {
      setState(() {
        _errorText = '请输入 1 到 ${widget.total} 之间的数字';
      });
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('跳转到第几首'),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: '序号',
          hintText: '1-${widget.total}',
          errorText: _errorText,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('跳转'),
        ),
      ],
    );
  }
}

class _FavoriteCollectionsDialog extends StatefulWidget {
  const _FavoriteCollectionsDialog({
    required this.collections,
    required this.initialSelectedIds,
  });

  final List<PoemCollection> collections;
  final Set<int> initialSelectedIds;

  @override
  State<_FavoriteCollectionsDialog> createState() =>
      _FavoriteCollectionsDialogState();
}

class _FavoriteCollectionsDialogState
    extends State<_FavoriteCollectionsDialog> {
  late final Set<int> _selectedIds;

  bool get _canCancelFavorite => _selectedIds.isEmpty;
  bool get _canSave => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.initialSelectedIds.toSet();
  }

  void _toggle(int collectionId, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedIds.add(collectionId);
      } else {
        _selectedIds.remove(collectionId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('管理收藏'),
      content: SizedBox(
        width: double.maxFinite,
        child: widget.collections.isEmpty
            ? const Text('暂无可收藏的其它诗词库。')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: widget.collections.length,
                itemBuilder: (context, index) {
                  final collection = widget.collections[index];
                  final id = collection.id;
                  if (id == null) {
                    return const SizedBox.shrink();
                  }
                  return CheckboxListTile(
                    value: _selectedIds.contains(id),
                    onChanged: (selected) => _toggle(id, selected),
                    title: Text(
                      collection.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: collection.isFavorites
                        ? const Text('默认收藏库')
                        : collection.description.trim().isEmpty
                            ? null
                            : Text(
                                collection.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        TextButton(
          onPressed: _canCancelFavorite
              ? () => Navigator.pop(context, <int>{})
              : null,
          child: const Text('取消收藏'),
        ),
        FilledButton(
          onPressed: _canSave
              ? () => Navigator.pop(context, _selectedIds.toSet())
              : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _PoemLearningHeader extends StatelessWidget {
  const _PoemLearningHeader({required this.poem, required this.onAskAi});

  final Poem poem;
  final ValueChanged<String> onAskAi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = poem.title.trim();
    final titleStyle = _titleStyle(theme.textTheme, title.length);
    final authorLine = [
      if (poem.dynasty.trim().isNotEmpty) poem.dynasty.trim(),
      poem.author.trim(),
    ].where((item) => item.isNotEmpty).join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.isEmpty ? '未命名诗词' : title,
          style: titleStyle?.copyWith(
            color: const Color(0xFF4F3B12),
            height: 1.24,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          authorLine.isEmpty ? '未知作者' : authorLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        if (poem.remark.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          _InfoChip(text: '备注：${poem.remark.trim()}'),
        ],
        if (poem.preface.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4C7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFEEDC9A)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('序 / 小序', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  SelectableText(
                    poem.preface.trim(),
                    contextMenuBuilder: _askAiSelectionMenuBuilder(onAskAi),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  TextStyle? _titleStyle(TextTheme textTheme, int titleLength) {
    if (titleLength > 60) {
      return textTheme.bodyLarge;
    }
    if (titleLength > 34) {
      return textTheme.titleMedium;
    }
    if (titleLength > 18) {
      return textTheme.titleLarge;
    }
    return textTheme.headlineSmall;
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4C7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }
}

EditableTextContextMenuBuilder _askAiSelectionMenuBuilder(
  ValueChanged<String> onAskAi,
) {
  return (context, editableTextState) {
    final value = editableTextState.textEditingValue;
    final selection = value.selection;
    final selectedText = selection.isValid && !selection.isCollapsed
        ? selection.textInside(value.text).trim()
        : '';
    final items = <ContextMenuButtonItem>[
      for (final item in editableTextState.contextMenuButtonItems)
        if (!_isReadAloudMenuItem(item)) item,
      if (selectedText.isNotEmpty)
        ContextMenuButtonItem(
          label: '问AI',
          onPressed: () {
            editableTextState.hideToolbar();
            onAskAi(selectedText);
          },
        ),
    ];

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  };
}

SelectableRegionContextMenuBuilder _askAiRegionMenuBuilder(
  String Function() selectedTextGetter,
  ValueChanged<String> onAskAi,
) {
  return (context, selectableRegionState) {
    final selectedText = selectedTextGetter().trim();
    final items = <ContextMenuButtonItem>[
      for (final item in selectableRegionState.contextMenuButtonItems)
        if (!_isReadAloudMenuItem(item)) item,
      if (selectedText.isNotEmpty)
        ContextMenuButtonItem(
          label: '问AI',
          onPressed: () {
            selectableRegionState.hideToolbar();
            onAskAi(selectedText);
          },
        ),
    ];

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: selectableRegionState.contextMenuAnchors,
      buttonItems: items,
    );
  };
}

bool _isReadAloudMenuItem(ContextMenuButtonItem item) {
  final label = item.label?.trim().toLowerCase();
  return label == 'read aloud' || label == '大声朗读';
}

class _PoemContentView extends StatefulWidget {
  const _PoemContentView({
    super.key,
    required this.poem,
    required this.showToneMarks,
    required this.previewLineNumber,
    required this.previewNotes,
    required this.onLineNumberTap,
    required this.onLineTap,
    required this.onAskAi,
    required this.onDismissPreview,
    required this.onSelectionActiveChanged,
  });

  final Poem poem;
  final bool showToneMarks;
  final int? previewLineNumber;
  final List<String> previewNotes;
  final ValueChanged<int> onLineNumberTap;
  final ValueChanged<int> onLineTap;
  final ValueChanged<String> onAskAi;
  final VoidCallback onDismissPreview;
  final ValueChanged<bool> onSelectionActiveChanged;

  @override
  State<_PoemContentView> createState() => _PoemContentViewState();
}

class _PoemContentViewState extends State<_PoemContentView> {
  final _selectionAreaKey = GlobalKey<SelectionAreaState>();
  String _selectedText = '';

  bool get hasActiveSelection => _selectedText.isNotEmpty;

  bool containsGlobalPosition(Offset position) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }
    final localPosition = renderObject.globalToLocal(position);
    return (Offset.zero & renderObject.size).contains(localPosition);
  }

  void clearTextSelection() {
    _selectionAreaKey.currentState?.selectableRegion.clearSelection();
    _setSelectedText('');
  }

  void _setSelectedText(String text) {
    final nextText = text.trim();
    final wasActive = _selectedText.isNotEmpty;
    final isActive = nextText.isNotEmpty;
    _selectedText = nextText;
    if (wasActive != isActive) {
      widget.onSelectionActiveChanged(isActive);
    }
  }

  void _handleSelectionChanged(SelectedContent? content) {
    _setSelectedText(content?.plainText ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = widget.poem.content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final regulatedCheck =
        widget.showToneMarks ? checkRegulatedVerse(widget.poem) : null;
    final lineChecksByNumber = {
      for (final line in regulatedCheck?.lines ?? <RegulatedVerseLineCheck>[])
        line.lineNumber: line,
    };
    final relationsByFirstLine = <int, List<RegulatedVerseRelationCheck>>{};
    for (final relation
        in regulatedCheck?.relations ?? <RegulatedVerseRelationCheck>[]) {
      relationsByFirstLine
          .putIfAbsent(relation.firstLine, () => <RegulatedVerseRelationCheck>[])
          .add(relation);
    }
    var lineNumber = 0;

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEDC9A)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final rawLine in lines)
              if (rawLine.trim().isEmpty)
                const _StanzaDivider()
              else
                Builder(
                  builder: (context) {
                    lineNumber += 1;
                    final currentLineNumber = lineNumber;
                    final showPreview =
                        widget.previewLineNumber == currentLineNumber &&
                            widget.previewNotes.isNotEmpty;
                    final lineMarks =
                        lineChecksByNumber[currentLineNumber]?.marks ??
                            const <RegulatedVerseMark>[];
                    final relationLabels =
                        relationsByFirstLine[currentLineNumber] ??
                            const <RegulatedVerseRelationCheck>[];
                    final lineRow = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectionContainer.disabled(
                          child: SizedBox(
                            width: 28,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => widget.onLineNumberTap(
                                currentLineNumber,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child: Text(
                                  '$currentLineNumber',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: const Color(0xFF9A7B2F),
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: widget.showToneMarks
                              ? ToneMarkedLineText(
                                  line: rawLine.trim(),
                                  rhymeBook: widget.poem.prosodyRhymeBook,
                                  lineNumber: currentLineNumber,
                                  overridesJson:
                                      widget.poem.prosodyOverridesJson,
                                  marks: lineMarks,
                                  textStyle:
                                      theme.textTheme.titleMedium?.copyWith(
                                    height: 1.25,
                                    color: const Color(0xFF2F2510),
                                  ),
                                )
                              : _SelectableLineText(
                                  rawLine.trim(),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    height: 1.7,
                                    color: const Color(0xFF2F2510),
                                  ),
                                ),
                        ),
                      ],
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showPreview) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 28,
                                right: 2,
                                bottom: 6,
                              ),
                              child: _LineAnnotationPreview(
                                lineNumber: currentLineNumber,
                                notes: widget.previewNotes,
                                onClose: widget.onDismissPreview,
                              ),
                            ),
                          ],
                          Material(
                            color: Colors.transparent,
                            child: widget.showToneMarks
                                ? InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () =>
                                        widget.onLineTap(currentLineNumber),
                                    onLongPress: _showToneSelectionHint,
                                    child: ToneMarkedLineIssueOverlay(
                                      line: rawLine.trim(),
                                      showLineNumbers: true,
                                      marks: lineMarks,
                                      relations: relationLabels,
                                      lineTopPadding: 2,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 2,
                                        ),
                                        child: lineRow,
                                      ),
                                    ),
                                  )
                                : Padding(
                                    padding: EdgeInsets.zero,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(6),
                                      onTap: () =>
                                          widget.onLineTap(currentLineNumber),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 2,
                                        ),
                                        child: lineRow,
                                      ),
                                    ),
                                  ),
                          ),
                         ],
                       ),
                     );
                  },
                ),
          ],
        ),
      ),
    );

    if (widget.showToneMarks) {
      return content;
    }

    return SelectionArea(
      key: _selectionAreaKey,
      contextMenuBuilder: _askAiRegionMenuBuilder(
        () => _selectedText,
        widget.onAskAi,
      ),
      onSelectionChanged: _handleSelectionChanged,
      child: content,
    );
  }

  void _showToneSelectionHint() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('欲选择文本需关闭格律审查。')),
      );
  }
}

class _SelectableLineText extends StatelessWidget {
  const _SelectableLineText(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: style);
  }
}

class _StanzaDivider extends StatelessWidget {
  const _StanzaDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 10, 4, 10),
      child: Divider(
        height: 1,
        thickness: 0.8,
        color: Color(0xFFEEDC9A),
      ),
    );
  }
}

class _LineAnnotationPreview extends StatelessWidget {
  const _LineAnnotationPreview({
    required this.lineNumber,
    required this.notes,
    required this.onClose,
  });

  final int lineNumber;
  final List<String> notes;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEDC9A)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '第 $lineNumber 行注释',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF7B5A00),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '关闭',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            Text(
              notes.join('\n'),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _LearningSection extends StatelessWidget {
  const _LearningSection({
    required this.title,
    required this.icon,
    required this.child,
    required this.initiallyExpanded,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
          leading: Icon(icon),
          title: Text(title),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [child],
        ),
      ),
    );
  }
}

class _ControlledLearningSection extends StatelessWidget {
  const _ControlledLearningSection({
    required this.sectionKey,
    required this.title,
    required this.icon,
    required this.expanded,
    required this.onExpansionChanged,
    required this.child,
  });

  final Key sectionKey;
  final String title;
  final IconData icon;
  final bool expanded;
  final ValueChanged<bool> onExpansionChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: sectionKey,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          ListTile(
            leading: Icon(icon),
            title: Text(title),
            trailing: Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            ),
            onTap: () => onExpansionChanged(!expanded),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _LearningNoteSection extends StatefulWidget {
  const _LearningNoteSection({
    required this.note,
    required this.onChanged,
    required this.onAskAi,
  });

  final String note;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onAskAi;

  @override
  State<_LearningNoteSection> createState() => _LearningNoteSectionState();
}

class _LearningNoteSectionState extends State<_LearningNoteSection> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _saveTimer;
  late String _lastSavedNote;

  @override
  void initState() {
    super.initState();
    _lastSavedNote = widget.note.trim();
    _controller = TextEditingController(text: _lastSavedNote);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _LearningNoteSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextNote = widget.note.trim();
    if (!_focusNode.hasFocus && nextNote != _lastSavedNote) {
      _lastSavedNote = nextNote;
      _controller.text = nextNote;
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveNow();
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _saveNow();
    }
  }

  void _scheduleSave(String _) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 900), _saveNow);
  }

  void _saveNow() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final nextNote = _controller.text.trim();
    if (nextNote == _lastSavedNote) {
      return;
    }
    _lastSavedNote = nextNote;
    widget.onChanged(nextNote);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
          leading: const Icon(Icons.edit_note_outlined),
          title: const Text('学习笔记'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              minLines: 3,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              contextMenuBuilder: _askAiSelectionMenuBuilder(widget.onAskAi),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.65),
              decoration: InputDecoration(
                hintText: '暂无笔记',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF9B9484),
                ),
                contentPadding: const EdgeInsets.all(12),
                filled: true,
                fillColor: Colors.white,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFEEDC9A)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE0B02E)),
                ),
              ),
              onChanged: _scheduleSave,
              onEditingComplete: _saveNow,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectableBlock extends StatelessWidget {
  const _SelectableBlock({
    required this.text,
    required this.emptyText,
    required this.onAskAi,
  });

  final String text;
  final String emptyText;
  final ValueChanged<String> onAskAi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = text.trim();
    if (value.isEmpty) {
      return Text(emptyText, style: theme.textTheme.bodyMedium);
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: SelectableText(
        value,
        contextMenuBuilder: _askAiSelectionMenuBuilder(onAskAi),
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.65),
      ),
    );
  }
}

class _ParsedAnnotation {
  const _ParsedAnnotation({
    required this.grouped,
    required this.unmatched,
  });

  final Map<int, List<String>> grouped;
  final List<String> unmatched;

  bool get isEmpty => grouped.isEmpty && unmatched.isEmpty;
}

_ParsedAnnotation _parseAnnotation(String annotation) {
  final value = annotation.trim();
  if (value.isEmpty) {
    return const _ParsedAnnotation(
      grouped: <int, List<String>>{},
      unmatched: <String>[],
    );
  }

  final grouped = <int, List<String>>{};
  final unmatched = <String>[];
  final pattern = RegExp(r'^\[(\d+)\]\s*(.+)$');
  final lines = value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty);

  for (final line in lines) {
    final match = pattern.firstMatch(line);
    if (match == null) {
      unmatched.add(line);
      continue;
    }
    final lineNumber = int.tryParse(match.group(1)!);
    final note = match.group(2)!.trim();
    if (lineNumber == null || note.isEmpty) {
      unmatched.add(line);
      continue;
    }
    grouped.putIfAbsent(lineNumber, () => <String>[]).add(note);
  }

  return _ParsedAnnotation(
    grouped: Map.unmodifiable(grouped),
    unmatched: List.unmodifiable(unmatched),
  );
}

class _AnnotationView extends StatelessWidget {
  const _AnnotationView({
    required this.annotation,
    required this.lineKeys,
    required this.highlightedLine,
    required this.onAskAi,
  });

  final _ParsedAnnotation annotation;
  final Map<int, GlobalKey> lineKeys;
  final int? highlightedLine;
  final ValueChanged<String> onAskAi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (annotation.isEmpty) {
      return Text(
        '暂无注释。可以让智能体按 [0] 标题注释、[行号] 正文注释的规范补充。',
        style: theme.textTheme.bodyMedium,
      );
    }

    final keys = annotation.grouped.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final key in keys)
          Container(
            key: lineKeys[key],
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: highlightedLine == key
                ? const EdgeInsets.fromLTRB(8, 8, 8, 8)
                : EdgeInsets.zero,
            decoration: highlightedLine == key
                ? BoxDecoration(
                    color: const Color(0xFFFFF4C7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE0B02E)),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  key == 0 ? '标题' : '第 $key 行',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF9A7B2F),
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  annotation.grouped[key]!.join('\n'),
                  contextMenuBuilder: _askAiSelectionMenuBuilder(onAskAi),
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                ),
              ],
            ),
          ),
        if (annotation.unmatched.isNotEmpty) ...[
          Text('未分组注释', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(
            annotation.unmatched.join('\n'),
            contextMenuBuilder: _askAiSelectionMenuBuilder(onAskAi),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
        ],
      ],
    );
  }
}

class _PoemSearchSheet extends StatefulWidget {
  const _PoemSearchSheet({required this.poems});

  final List<Poem> poems;

  @override
  State<_PoemSearchSheet> createState() => _PoemSearchSheetState();
}

class _PoemSearchSheetState extends State<_PoemSearchSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Poem> get _filteredPoems {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) {
      return widget.poems;
    }
    return widget.poems.where((poem) => _matches(poem, keyword)).toList();
  }

  bool _matches(Poem poem, String keyword) {
    return poem.title.contains(keyword) ||
        poem.author.contains(keyword) ||
        poem.dynasty.contains(keyword) ||
        poem.preface.contains(keyword) ||
        poem.content.contains(keyword) ||
        poem.remark.contains(keyword) ||
        poem.translation.contains(keyword) ||
        poem.annotation.contains(keyword) ||
        poem.learningNote.contains(keyword) ||
        poem.appreciation.contains(keyword);
  }

  @override
  Widget build(BuildContext context) {
    final filteredPoems = _filteredPoems;

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            12 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: '搜索当前诗词库',
                  hintText: '标题、作者、正文、序、译文、注释、笔记或赏析',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: filteredPoems.isEmpty
                    ? const Center(child: Text('没有找到匹配诗词'))
                    : ListView.builder(
                        itemCount: filteredPoems.length,
                        itemBuilder: (context, index) {
                          final poem = filteredPoems[index];
                          return ListTile(
                            title: Text(
                              poem.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                if (poem.dynasty.trim().isNotEmpty)
                                  poem.dynasty.trim(),
                                poem.author.trim(),
                                if (poem.remark.trim().isNotEmpty)
                                  poem.remark.trim(),
                              ].where((item) => item.isNotEmpty).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.pop(context, poem),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LearningMessageView extends StatelessWidget {
  const _LearningMessageView({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
