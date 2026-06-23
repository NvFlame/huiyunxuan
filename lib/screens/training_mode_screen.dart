import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_database.dart';
import '../models/poem.dart';
import '../models/poem_collection.dart';
import '../widgets/prosody_panel.dart';
import '../widgets/tone_marked_text.dart';
import 'poem_agent_chat_screen.dart';

enum TrainingDifficulty { xiucai, juren, gongsheng, jinshi }

extension TrainingDifficultyInfo on TrainingDifficulty {
  String get label {
    switch (this) {
      case TrainingDifficulty.xiucai:
        return '秀才';
      case TrainingDifficulty.juren:
        return '举人';
      case TrainingDifficulty.gongsheng:
        return '贡生';
      case TrainingDifficulty.jinshi:
        return '进士';
    }
  }

  String get description {
    switch (this) {
      case TrainingDifficulty.xiucai:
        return '随机抽走少量词语，适合熟悉诗句。';
      case TrainingDifficulty.juren:
        return '随机隐藏约一半诗句，补全整句。';
      case TrainingDifficulty.gongsheng:
        return '整句隐藏与词语填空混合训练。';
      case TrainingDifficulty.jinshi:
        return '全文默写，只保留标点与横线。';
    }
  }

  int get level {
    switch (this) {
      case TrainingDifficulty.xiucai:
        return 1;
      case TrainingDifficulty.juren:
        return 2;
      case TrainingDifficulty.gongsheng:
        return 3;
      case TrainingDifficulty.jinshi:
        return 4;
    }
  }
}

enum CorrectionMode { instant, finalReview }

extension CorrectionModeInfo on CorrectionMode {
  String get label {
    switch (this) {
      case CorrectionMode.instant:
        return '即时批改';
      case CorrectionMode.finalReview:
        return '最终批改';
    }
  }

  String get description {
    switch (this) {
      case CorrectionMode.instant:
        return '每个空输入完毕后立即校对。';
      case CorrectionMode.finalReview:
        return '全部填写后点击“核对答案”。';
    }
  }
}

enum _TrainingPhase { confirm, answering, revealed }

enum _BlankStatus { pending, correct, incorrect }

class TrainingModeScreen extends StatefulWidget {
  const TrainingModeScreen({
    super.key,
    this.initialCollectionId,
    this.initialPoemId,
    this.initialDifficulty = TrainingDifficulty.xiucai,
    this.initialCorrectionMode = CorrectionMode.instant,
    this.autoStart = false,
  });

  final int? initialCollectionId;
  final int? initialPoemId;
  final TrainingDifficulty initialDifficulty;
  final CorrectionMode initialCorrectionMode;
  final bool autoStart;

  @override
  State<TrainingModeScreen> createState() => _TrainingModeScreenState();
}

class _TrainingModeScreenState extends State<TrainingModeScreen> {
  final _random = Random();
  final _scrollController = ScrollController();
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, FocusNode> _focusNodes = {};

  List<PoemCollection> _collections = const <PoemCollection>[];
  List<Poem> _poems = const <Poem>[];
  Map<int, int> _achievements = const <int, int>{};
  PoemCollection? _selectedCollection;
  int _currentIndex = 0;
  TrainingDifficulty _difficulty = TrainingDifficulty.xiucai;
  CorrectionMode _correctionMode = CorrectionMode.instant;
  _TrainingPhase _phase = _TrainingPhase.confirm;
  _TrainingExercise? _exercise;
  bool _loading = true;
  String? _error;
  bool _passed = false;
  bool _abandoned = false;
  bool _trainingSessionStarted = false;
  bool _showToneMarks = false;
  int _attemptToken = 0;

  Poem? get _currentPoem {
    if (_poems.isEmpty || _currentIndex < 0 || _currentIndex >= _poems.length) {
      return null;
    }
    return _poems[_currentIndex];
  }

  int get _currentAchievementLevel {
    final poemId = _currentPoem?.id;
    if (poemId == null) {
      return 0;
    }
    return _achievements[poemId] ?? 0;
  }

  bool get _canGoPrevious => _currentIndex > 0;
  bool get _canGoNext => _currentIndex < _poems.length - 1;
  bool get _shouldReturnToConfirmOnBack =>
      !_loading && _phase != _TrainingPhase.confirm;

  @override
  void initState() {
    super.initState();
    _difficulty = widget.initialDifficulty;
    _correctionMode = widget.initialCorrectionMode;
    _loadInitialState();
  }

  @override
  void dispose() {
    _disposeAnswerInputs();
    _scrollController.dispose();
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
          _achievements = const <int, int>{};
          _loading = false;
          _error = null;
        });
        return;
      }

      final lastCollectionId = await database.getLastTrainingCollectionId();
      final selectedCollection =
          _findCollectionById(collections, widget.initialCollectionId) ??
              _findCollectionById(collections, lastCollectionId) ??
              collections.first;
      final loadResult = await _loadCollectionData(
        selectedCollection,
        preferredPoemId: widget.initialPoemId,
      );
      final achievements = await _loadAchievements(loadResult.poems);

      if (!mounted) {
        return;
      }
      setState(() {
        _collections = collections;
        _selectedCollection = selectedCollection;
        _poems = loadResult.poems;
        _currentIndex = loadResult.index;
        _achievements = achievements;
        _loading = false;
        _error = null;
      });
      if (widget.autoStart && loadResult.poems.isNotEmpty) {
        _startTraining();
      } else {
        await _saveCurrentProgress();
      }
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

  Future<_LoadedTrainingCollection> _loadCollectionData(
    PoemCollection collection, {
    int? preferredPoemId,
  }) async {
    final id = collection.id;
    if (id == null) {
      return const _LoadedTrainingCollection(poems: <Poem>[], index: 0);
    }

    final database = AppDatabase.instance;
    final poems = await database.getPoems(id);
    if (poems.isEmpty) {
      return const _LoadedTrainingCollection(poems: <Poem>[], index: 0);
    }

    final savedPoemId =
        preferredPoemId ?? (await database.getTrainingProgressPoemId(id));
    final savedIndex = poems.indexWhere((poem) => poem.id == savedPoemId);
    return _LoadedTrainingCollection(
      poems: poems,
      index: savedIndex >= 0 ? savedIndex : 0,
    );
  }

  Future<Map<int, int>> _loadAchievements(List<Poem> poems) async {
    return AppDatabase.instance.getTrainingAchievements(
      poems.map((poem) => poem.id).whereType<int>(),
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

    if (!await _confirmDiscardIfAnswering('切换诗词库会重新开始本次训练。')) {
      return;
    }

    final shouldAutoStart = _trainingSessionStarted;
    setState(() {
      _loading = true;
      _error = null;
      _resetTrainingState(returnToConfirm: !shouldAutoStart);
    });

    try {
      final loadResult = await _loadCollectionData(collection);
      final achievements = await _loadAchievements(loadResult.poems);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedCollection = collection;
        _poems = loadResult.poems;
        _currentIndex = loadResult.index;
        _achievements = achievements;
        _loading = false;
      });
      if (shouldAutoStart && mounted) {
        _startTraining();
      } else {
        await _saveCurrentProgress();
      }
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

  Future<void> _goToIndex(int index) async {
    if (index < 0 || index >= _poems.length || index == _currentIndex) {
      return;
    }

    final shouldAutoStart = _trainingSessionStarted;
    setState(() {
      _currentIndex = index;
      _resetTrainingState(returnToConfirm: !shouldAutoStart);
    });
    if (shouldAutoStart && mounted) {
      _startTraining();
    } else {
      await _saveCurrentProgress();
    }
  }

  Future<void> _saveCurrentProgress() async {
    final collectionId = _selectedCollection?.id;
    final poemId = _currentPoem?.id;
    if (collectionId == null || poemId == null) {
      return;
    }

    await AppDatabase.instance.saveTrainingProgress(
      collectionId: collectionId,
      poemId: poemId,
    );
  }

  Future<bool> _handleBackNavigation() async {
    if (!_shouldReturnToConfirmOnBack) {
      return true;
    }
    setState(() {
      _trainingSessionStarted = false;
      _resetTrainingState(returnToConfirm: true);
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    await _saveCurrentProgress();
    return false;
  }

  Future<void> _handleLeadingBackPressed() async {
    final shouldPop = await _handleBackNavigation();
    if (shouldPop && mounted) {
      await Navigator.maybePop(context);
    }
  }

  void _resetTrainingState({required bool returnToConfirm}) {
    _attemptToken += 1;
    if (returnToConfirm) {
      _phase = _TrainingPhase.confirm;
    }
    _exercise = null;
    _passed = false;
    _abandoned = false;
    _disposeAnswerInputs();
  }

  void _disposeAnswerInputs() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    _controllers.clear();
    _focusNodes.clear();
  }

  Future<bool> _confirmDiscardIfAnswering(String message) async {
    if (_phase != _TrainingPhase.answering) {
      return true;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('重新开始训练'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<void> _setDifficulty(TrainingDifficulty difficulty) async {
    if (difficulty == _difficulty) {
      return;
    }
    if (!await _confirmDiscardIfAnswering('切换难度会重新开始本诗训练。')) {
      return;
    }
    setState(() {
      _difficulty = difficulty;
    });
    if (_phase != _TrainingPhase.confirm) {
      _startTraining();
    }
  }

  Future<void> _setCorrectionMode(CorrectionMode mode) async {
    if (mode == _correctionMode) {
      return;
    }
    if (!await _confirmDiscardIfAnswering('切换批改方式会重新开始本诗训练。')) {
      return;
    }
    setState(() {
      _correctionMode = mode;
    });
    if (_phase != _TrainingPhase.confirm) {
      _startTraining();
    }
  }

  void _startTraining() {
    final poem = _currentPoem;
    if (poem == null) {
      return;
    }

    final exercise = _TrainingExercise.create(
      poem: poem,
      difficulty: _difficulty,
      random: _random,
    );
    if (exercise.blanks.isEmpty) {
      _showSnackBar('这首诗没有可训练的正文，请先补充正文。');
      return;
    }
    _disposeAnswerInputs();
    for (final blank in exercise.blanks.values) {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      focusNode.addListener(() {
        if (!focusNode.hasFocus) {
          _commitBlank(blank.id);
        }
      });
      _controllers[blank.id] = controller;
      _focusNodes[blank.id] = focusNode;
    }

    setState(() {
      _trainingSessionStarted = true;
      _attemptToken += 1;
      _exercise = exercise;
      _phase = _TrainingPhase.answering;
      _passed = false;
      _abandoned = false;
    });
    unawaited(_saveCurrentProgress());
  }

  void _commitBlank(int blankId, {bool focusNextOnCorrect = false}) {
    final exercise = _exercise;
    final blank = exercise?.blanks[blankId];
    final controller = _controllers[blankId];
    if (_phase != _TrainingPhase.answering ||
        exercise == null ||
        blank == null ||
        controller == null ||
        blank.status == _BlankStatus.correct) {
      return;
    }

    if (_correctionMode == CorrectionMode.finalReview) {
      if (blank.status == _BlankStatus.incorrect &&
          controller.text.trim().isNotEmpty) {
        setState(() {
          blank.status = _BlankStatus.pending;
        });
      }
      return;
    }

    final input = controller.text.trim();
    if (input.isEmpty) {
      return;
    }

    if (_isAnswerCorrect(input, blank.answer)) {
      setState(() {
        blank.status = _BlankStatus.correct;
        blank.wrongText = '';
        controller.clear();
      });
      if (exercise.allCorrect) {
        unawaited(_completePassed());
      } else if (focusNextOnCorrect) {
        _focusNextPendingBlank(blankId);
      }
      return;
    }

    _markBlankIncorrect(blank, controller, input);
  }

  void _markBlankIncorrect(
    _TrainingBlank blank,
    TextEditingController controller,
    String input,
  ) {
    final token = _attemptToken + 1;
    setState(() {
      _attemptToken = token;
      blank.status = _BlankStatus.incorrect;
      blank.wrongText = input;
      controller.value = TextEditingValue(
        text: input,
        selection: TextSelection.collapsed(offset: input.length),
      );
    });
    Future<void>.delayed(const Duration(milliseconds: 1300), () {
      if (!mounted ||
          _attemptToken != token ||
          _phase != _TrainingPhase.answering ||
          blank.status != _BlankStatus.incorrect) {
        return;
      }
      setState(() {
        controller.clear();
        blank.status = _BlankStatus.pending;
        blank.wrongText = '';
      });
    });
  }

  void _handleBlankEdited(int blankId) {
    final exercise = _exercise;
    final blank = _exercise?.blanks[blankId];
    final controller = _controllers[blankId];
    if (exercise == null || blank == null || controller == null) {
      return;
    }

    if (blank.characterLimit == 1) {
      _handleJinshiBlankEdited(
        exercise: exercise,
        blankId: blankId,
        blank: blank,
        controller: controller,
      );
      return;
    }

    if (blank.status != _BlankStatus.incorrect) {
      return;
    }
    setState(() {
      blank.status = _BlankStatus.pending;
      blank.wrongText = '';
    });
  }

  void _handleJinshiBlankEdited({
    required _TrainingExercise exercise,
    required int blankId,
    required _TrainingBlank blank,
    required TextEditingController controller,
  }) {
    final value = controller.value;
    if (value.composing.isValid && !value.composing.isCollapsed) {
      return;
    }

    final inputCharacters = _jinshiInputCharacters(controller.text);
    if (inputCharacters.isEmpty) {
      if (controller.text.trim().isNotEmpty) {
        controller.clear();
      }
      if (blank.status == _BlankStatus.incorrect) {
        setState(() {
          blank.status = _BlankStatus.pending;
          blank.wrongText = '';
        });
      }
      return;
    }

    final blankRun = _jinshiBlankRunFrom(exercise, blankId);
    if (blankRun.isEmpty) {
      return;
    }

    if (_correctionMode == CorrectionMode.finalReview) {
      final count = min(inputCharacters.length, blankRun.length);
      var lastFilledBlankId = blankId;
      setState(() {
        for (var index = 0; index < count; index += 1) {
          final targetBlankId = blankRun[index];
          final targetBlank = exercise.blanks[targetBlankId];
          final targetController = _controllers[targetBlankId];
          if (targetBlank == null || targetController == null) {
            continue;
          }
          final input = inputCharacters[index];
          targetController.value = TextEditingValue(
            text: input,
            selection: TextSelection.collapsed(offset: input.length),
          );
          if (targetBlank.status == _BlankStatus.incorrect) {
            targetBlank.status = _BlankStatus.pending;
            targetBlank.wrongText = '';
          }
          lastFilledBlankId = targetBlankId;
        }
      });
      _focusNextPendingBlank(lastFilledBlankId);
      return;
    }

    var lastCorrectBlankId = blankId;
    _TrainingBlank? wrongBlank;
    TextEditingController? wrongController;
    String? wrongInput;

    setState(() {
      final count = min(inputCharacters.length, blankRun.length);
      for (var index = 0; index < count; index += 1) {
        final targetBlankId = blankRun[index];
        final targetBlank = exercise.blanks[targetBlankId];
        final targetController = _controllers[targetBlankId];
        if (targetBlank == null || targetController == null) {
          continue;
        }
        if (targetBlank.status == _BlankStatus.correct) {
          lastCorrectBlankId = targetBlankId;
          continue;
        }

        final input = inputCharacters[index];
        if (_isAnswerCorrect(input, targetBlank.answer)) {
          targetBlank.status = _BlankStatus.correct;
          targetBlank.wrongText = '';
          targetController.clear();
          lastCorrectBlankId = targetBlankId;
          continue;
        }

        wrongBlank = targetBlank;
        wrongController = targetController;
        wrongInput = input;
        break;
      }
    });

    final failedBlank = wrongBlank;
    final failedController = wrongController;
    final failedInput = wrongInput;
    if (failedBlank != null &&
        failedController != null &&
        failedInput != null) {
      _markBlankIncorrect(failedBlank, failedController, failedInput);
      _focusNodes[failedBlank.id]?.requestFocus();
      return;
    }

    if (exercise.allCorrect) {
      unawaited(_completePassed());
    } else {
      _focusNextPendingBlank(lastCorrectBlankId);
    }
  }

  void _focusNextPendingBlank(int currentBlankId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final exercise = _exercise;
      if (!mounted ||
          exercise == null ||
          _phase != _TrainingPhase.answering) {
        return;
      }
      final ids = exercise.blanks.keys.toList()..sort();
      for (final id in ids) {
        if (id <= currentBlankId) {
          continue;
        }
        final blank = exercise.blanks[id];
        if (blank == null || blank.status == _BlankStatus.correct) {
          continue;
        }
        final text = _controllers[id]?.text.trim() ?? '';
        if (text.isNotEmpty) {
          continue;
        }
        _focusNodes[id]?.requestFocus();
        return;
      }
      FocusScope.of(context).unfocus();
    });
  }

  Future<void> _checkFinalAnswers() async {
    final exercise = _exercise;
    if (exercise == null || _phase != _TrainingPhase.answering) {
      return;
    }

    var allCorrect = true;
    setState(() {
      for (final blank in exercise.blanks.values) {
        if (blank.status == _BlankStatus.correct) {
          continue;
        }
        final input = _controllers[blank.id]?.text.trim() ?? '';
        if (input.isNotEmpty && _isAnswerCorrect(input, blank.answer)) {
          blank.status = _BlankStatus.correct;
          blank.wrongText = '';
          _controllers[blank.id]?.clear();
        } else {
          blank.status = _BlankStatus.incorrect;
          blank.wrongText = input;
          allCorrect = false;
        }
      }
    });

    if (allCorrect) {
      await _completePassed();
    } else {
      _showSnackBar('还有答案不正确，请修改后再核对。');
    }
  }

  Future<void> _completePassed() async {
    final poemId = _currentPoem?.id;
    if (poemId == null || _phase != _TrainingPhase.answering) {
      return;
    }

    final finalLevel = await AppDatabase.instance.saveTrainingAchievement(
      poemId: poemId,
      level: _difficulty.level,
    );
    if (!mounted) {
      return;
    }

    _disposeAnswerInputs();
    setState(() {
      _achievements = {
        ..._achievements,
        poemId: finalLevel,
      };
      _phase = _TrainingPhase.revealed;
      _passed = true;
      _abandoned = false;
    });
    _showSnackBar('通过${_difficulty.label}训练');
  }

  void _showAnswer() {
    _disposeAnswerInputs();
    setState(() {
      _attemptToken += 1;
      _phase = _TrainingPhase.revealed;
      _passed = false;
      _abandoned = true;
    });
  }

  Future<void> _showPoemSearch() async {
    if (_poems.isEmpty) {
      return;
    }

    final selected = await showModalBottomSheet<Poem>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TrainingPoemSearchSheet(poems: _poems),
    );
    if (selected == null) {
      return;
    }

    final index = _poems.indexWhere((poem) => poem.id == selected.id);
    if (index >= 0) {
      await _goToIndex(index);
    }
  }

  Future<void> _showJumpDialog() async {
    if (_poems.isEmpty) {
      return;
    }

    final targetPage = await showDialog<int>(
      context: context,
      builder: (context) {
        return _TrainingJumpDialog(
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

  Future<void> _openPoemChat() async {
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
        ),
      ),
    );
    if (changed == true && mounted) {
      await _reloadCurrentPoem(poem.id);
    }
  }

  Future<void> _reloadCurrentPoem(int? preferredPoemId) async {
    final collection = _selectedCollection;
    if (collection == null) {
      return;
    }

    final loadResult = await _loadCollectionData(
      collection,
      preferredPoemId: preferredPoemId,
    );
    final achievements = await _loadAchievements(loadResult.poems);
    if (!mounted) {
      return;
    }
    final phaseBeforeReload = _phase;
    setState(() {
      _poems = loadResult.poems;
      _currentIndex = loadResult.index;
      _achievements = achievements;
      if (phaseBeforeReload == _TrainingPhase.answering) {
        _resetTrainingState(returnToConfirm: false);
      }
    });
    if (phaseBeforeReload == _TrainingPhase.answering && mounted) {
      _startTraining();
    } else {
      await _saveCurrentProgress();
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isAnswerCorrect(String input, String answer) {
    return _normalizeAnswer(input) == _normalizeAnswer(answer);
  }

  @override
  Widget build(BuildContext context) {
    final poem = _currentPoem;
    final collection = _selectedCollection;

    return WillPopScope(
      onWillPop: _handleBackNavigation,
      child: Scaffold(
        appBar: AppBar(
          leading: Navigator.canPop(context)
              ? BackButton(
                  onPressed: () => unawaited(_handleLeadingBackPressed()),
                )
              : null,
          title: _TrainingTitle(
            collection: collection,
            currentIndex: _poems.isEmpty ? 0 : _currentIndex + 1,
            total: _poems.length,
            onTapProgress: _poems.isEmpty ? null : _showJumpDialog,
          ),
          actions: [
            if (_phase != _TrainingPhase.confirm) ...[
              PopupMenuButton<TrainingDifficulty>(
                tooltip: '切换难度',
                initialValue: _difficulty,
                icon: const Icon(Icons.school_outlined),
                onSelected: (value) => unawaited(_setDifficulty(value)),
                itemBuilder: (context) {
                  return [
                    for (final difficulty in TrainingDifficulty.values)
                      PopupMenuItem<TrainingDifficulty>(
                        value: difficulty,
                        child: Text(difficulty.label),
                      ),
                  ];
                },
              ),
              PopupMenuButton<CorrectionMode>(
                tooltip: '切换批改方式',
                initialValue: _correctionMode,
                icon: const Icon(Icons.fact_check_outlined),
                onSelected: (value) => unawaited(_setCorrectionMode(value)),
                itemBuilder: (context) {
                  return [
                    for (final mode in CorrectionMode.values)
                      PopupMenuItem<CorrectionMode>(
                        value: mode,
                        child: Text(mode.label),
                      ),
                  ];
                },
              ),
            ],
            IconButton(
              tooltip: '搜索诗词',
              onPressed:
                  _poems.isEmpty ? null : () => unawaited(_showPoemSearch()),
              icon: const Icon(Icons.search),
            ),
          ],
        ),
        body: SafeArea(child: _buildBody(poem)),
        floatingActionButton: _phase == _TrainingPhase.revealed && poem != null
            ? FloatingActionButton.extended(
                onPressed: () => unawaited(_openPoemChat()),
                icon: const Icon(Icons.smart_toy_outlined),
                label: const Text('问道'),
              )
            : null,
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildBody(Poem? poem) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _TrainingMessageView(
        icon: Icons.error_outline,
        title: '展才读取失败',
        message: _error!,
      );
    }
    if (_collections.isEmpty) {
      return const _TrainingMessageView(
        icon: Icons.library_add_outlined,
        title: '还没有诗词库',
        message: '请先在“诗词库管理”中创建诗词库并添加诗词。',
      );
    }
    if (_poems.isEmpty) {
      return const _TrainingMessageView(
        icon: Icons.menu_book_outlined,
        title: '当前诗词库为空',
        message: '可以切换到其它诗词库，或先为当前库添加诗词。',
      );
    }
    if (poem == null) {
      return const _TrainingMessageView(
        icon: Icons.error_outline,
        title: '没有可训练的诗词',
        message: '请返回后重新进入展才。',
      );
    }

    switch (_phase) {
      case _TrainingPhase.confirm:
        return _buildConfirmView(poem);
      case _TrainingPhase.answering:
        return _buildAnsweringView(poem);
      case _TrainingPhase.revealed:
        return _buildRevealedView(poem);
    }
  }

  Widget _buildConfirmView(Poem poem) {
    final collectionId = _selectedCollection?.id;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
      children: [
        _TrainingProgressCard(
          poem: poem,
          currentIndex: _currentIndex + 1,
          total: _poems.length,
          achievementLevel: _currentAchievementLevel,
          onPrevious: _canGoPrevious
              ? () => unawaited(_goToIndex(_currentIndex - 1))
              : null,
          onNext: _canGoNext
              ? () => unawaited(_goToIndex(_currentIndex + 1))
              : null,
          onSearch: () => unawaited(_showPoemSearch()),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: collectionId,
          decoration: const InputDecoration(
            labelText: '当前诗词库',
            prefixIcon: Icon(Icons.folder_outlined),
          ),
          items: [
            for (final collection in _collections)
              if (collection.id != null)
                DropdownMenuItem<int>(
                  value: collection.id,
                  child: Text(
                    collection.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          ],
          onChanged: (value) {
            if (value != null) {
              unawaited(_switchCollection(value));
            }
          },
        ),
        const SizedBox(height: 16),
        _TrainingOptionSection(
          title: '难度模式',
          child: SegmentedButton<TrainingDifficulty>(
            segments: [
              for (final difficulty in TrainingDifficulty.values)
                ButtonSegment<TrainingDifficulty>(
                  value: difficulty,
                  label: Text(difficulty.label),
                ),
            ],
            selected: {_difficulty},
            onSelectionChanged: (selected) {
              unawaited(_setDifficulty(selected.first));
            },
          ),
          description: _difficulty.description,
        ),
        const SizedBox(height: 16),
        _TrainingOptionSection(
          title: '批改模式',
          child: SegmentedButton<CorrectionMode>(
            segments: [
              for (final mode in CorrectionMode.values)
                ButtonSegment<CorrectionMode>(
                  value: mode,
                  label: Text(mode.label),
                ),
            ],
            selected: {_correctionMode},
            onSelectionChanged: (selected) {
              unawaited(_setCorrectionMode(selected.first));
            },
          ),
          description: _correctionMode.description,
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: _startTraining,
          icon: const Icon(Icons.play_arrow),
          label: const Text('开始训练'),
        ),
      ],
    );
  }

  Widget _buildAnsweringView(Poem poem) {
    final exercise = _exercise;
    if (exercise == null) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(48, 18, 48, 120),
          children: [
            _TrainingPoemHeader(
              poem: poem,
              difficulty: _difficulty,
              correctionMode: _correctionMode,
              achievementLevel: _currentAchievementLevel,
            ),
            const SizedBox(height: 18),
            _ExerciseView(
              exercise: exercise,
              controllers: _controllers,
              focusNodes: _focusNodes,
              onSubmitBlank: _commitBlank,
              onEditedBlank: _handleBlankEdited,
            ),
          ],
        ),
        Positioned(
          left: 6,
          top: 0,
          bottom: 0,
          child: Center(
            child: IconButton.filledTonal(
              tooltip: '上一首',
              onPressed: _canGoPrevious
                  ? () => unawaited(_goToIndex(_currentIndex - 1))
                  : null,
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
                  ? () => unawaited(_goToIndex(_currentIndex + 1))
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRevealedView(Poem poem) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(52, 14, 52, 130),
          children: [
            _TrainingResultBanner(
              passed: _passed,
              abandoned: _abandoned,
              difficulty: _difficulty,
              achievementLevel: _currentAchievementLevel,
            ),
            const SizedBox(height: 12),
            _TrainingPoemHeader(
              poem: poem,
              difficulty: _difficulty,
              correctionMode: _correctionMode,
              achievementLevel: _currentAchievementLevel,
            ),
            const SizedBox(height: 12),
            _TrainingContentSection(
              title: '正文',
              icon: Icons.subject_outlined,
              initiallyExpanded: true,
              child: _showToneMarks &&
                      poem.prosodySupported &&
                      poem.prosodyEnabled
                  ? ToneMarkedPoemText(
                      poem: poem,
                      textStyle: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(
                            height: 1.25,
                            color: const Color(0xFF2F2510),
                          ),
                    )
                  : SelectableText(
                      poem.content,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            height: 1.75,
                            color: const Color(0xFF2F2510),
                          ),
                    ),
            ),
            ProsodyPanel(
              poem: poem,
              showToneDetails: _showToneMarks,
              onToneDetailsChanged: (value) {
                setState(() {
                  _showToneMarks = value;
                });
              },
            ),
            if (poem.prosodySupported && poem.prosodyEnabled)
              const SizedBox(height: 8),
            _TrainingContentSection(
              title: '注释',
              icon: Icons.notes_outlined,
              initiallyExpanded: true,
              child: _SelectableTrainingBlock(
                text: poem.annotation,
                emptyText: '暂无注释。',
              ),
            ),
            _TrainingContentSection(
              title: '学习笔记',
              icon: Icons.edit_note_outlined,
              initiallyExpanded: poem.learningNote.trim().isNotEmpty,
              child: _SelectableTrainingBlock(
                text: poem.learningNote,
                emptyText: '暂无学习笔记。',
              ),
            ),
            _TrainingContentSection(
              title: '译文',
              icon: Icons.translate,
              initiallyExpanded: false,
              child: _SelectableTrainingBlock(
                text: poem.translation,
                emptyText: '暂无译文。',
              ),
            ),
            _TrainingContentSection(
              title: '赏析',
              icon: Icons.auto_stories_outlined,
              initiallyExpanded: false,
              child: _SelectableTrainingBlock(
                text: poem.appreciation,
                emptyText: '暂无赏析。',
              ),
            ),
          ],
        ),
        Positioned(
          left: 6,
          top: 0,
          bottom: 0,
          child: Center(
            child: IconButton.filledTonal(
              tooltip: '上一首',
              onPressed: _canGoPrevious
                  ? () => unawaited(_goToIndex(_currentIndex - 1))
                  : null,
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
                  ? () => unawaited(_goToIndex(_currentIndex + 1))
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _buildBottomBar() {
    if (_phase == _TrainingPhase.confirm || _loading || _currentPoem == null) {
      return null;
    }

    if (_phase == _TrainingPhase.answering) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: _TrainingBottomActionButton(
                  onPressed: _showAnswer,
                  icon: const Icon(Icons.visibility_outlined),
                  label: '查看答案',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TrainingBottomActionButton(
                  onPressed: _startTraining,
                  icon: const Icon(Icons.refresh),
                  label: '重新开始',
                ),
              ),
              if (_correctionMode == CorrectionMode.finalReview) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _TrainingBottomActionButton(
                    onPressed: () => unawaited(_checkFinalAnswers()),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: '核对答案',
                    filled: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: _TrainingBottomActionButton(
                onPressed: _startTraining,
                icon: const Icon(Icons.refresh),
                label: '再练一次',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TrainingBottomActionButton(
                onPressed:
                    _canGoNext
                        ? () => unawaited(_goToIndex(_currentIndex + 1))
                        : null,
                icon: const Icon(Icons.chevron_right),
                label: '下一首',
                filled: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadedTrainingCollection {
  const _LoadedTrainingCollection({required this.poems, required this.index});

  final List<Poem> poems;
  final int index;
}

class _TrainingBottomActionButton extends StatelessWidget {
  const _TrainingBottomActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.filled = false,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final child = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme.merge(
            data: const IconThemeData(size: 20),
            child: icon,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            maxLines: 1,
            softWrap: false,
          ),
        ],
      ),
    );

    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: style,
        child: child,
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}

class _TrainingTitle extends StatelessWidget {
  const _TrainingTitle({
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
    final name = collection?.name ?? '展才';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (total > 0)
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTapProgress,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Text(
                '$currentIndex / $total',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: const Color(0xFF4F3B12),
                      decoration: TextDecoration.underline,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TrainingProgressCard extends StatelessWidget {
  const _TrainingProgressCard({
    required this.poem,
    required this.currentIndex,
    required this.total,
    required this.achievementLevel,
    required this.onPrevious,
    required this.onNext,
    required this.onSearch,
  });

  final Poem poem;
  final int currentIndex;
  final int total;
  final int achievementLevel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authorLine = [
      if (poem.dynasty.trim().isNotEmpty) poem.dynasty.trim(),
      poem.author.trim(),
    ].where((item) => item.isNotEmpty).join(' · ');

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('当前进度', style: theme.textTheme.labelLarge),
                const Spacer(),
                _AchievementBadge(level: achievementLevel),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$currentIndex / $total',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF4F3B12),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              poem.title.trim().isEmpty ? '未命名诗词' : poem.title.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              authorLine.isEmpty ? '未知作者' : authorLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: '上一首',
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: '下一首',
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onSearch,
                  icon: const Icon(Icons.search),
                  label: const Text('查找诗词'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrainingOptionSection extends StatelessWidget {
  const _TrainingOptionSection({
    required this.title,
    required this.child,
    required this.description,
  });

  final String title;
  final Widget child;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        child,
        const SizedBox(height: 6),
        Text(description, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _TrainingPoemHeader extends StatelessWidget {
  const _TrainingPoemHeader({
    required this.poem,
    required this.difficulty,
    required this.correctionMode,
    required this.achievementLevel,
  });

  final Poem poem;
  final TrainingDifficulty difficulty;
  final CorrectionMode correctionMode;
  final int achievementLevel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authorLine = [
      if (poem.dynasty.trim().isNotEmpty) poem.dynasty.trim(),
      poem.author.trim(),
    ].where((item) => item.isNotEmpty).join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                poem.title.trim().isEmpty ? '未命名诗词' : poem.title.trim(),
                style: _titleStyle(theme.textTheme, poem.title.length)
                    ?.copyWith(color: const Color(0xFF4F3B12), height: 1.24),
              ),
            ),
            const SizedBox(width: 10),
            _AchievementBadge(level: achievementLevel),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          authorLine.isEmpty ? '未知作者' : authorLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _TrainingChip(icon: Icons.school_outlined, text: difficulty.label),
            _TrainingChip(
              icon: Icons.fact_check_outlined,
              text: correctionMode.label,
            ),
          ],
        ),
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

class _TrainingChip extends StatelessWidget {
  const _TrainingChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEDC9A)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF7B5A00)),
            const SizedBox(width: 5),
            Text(text),
          ],
        ),
      ),
    );
  }
}

class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final label = _achievementLabel(level);
    final achieved = level > 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: achieved ? const Color(0xFFE0B02E) : const Color(0xFFFFF4C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: achieved ? const Color(0xFFB18200) : const Color(0xFFEEDC9A),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            color: achieved ? Colors.white : const Color(0xFF7B5A00),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ExerciseView extends StatelessWidget {
  const _ExerciseView({
    required this.exercise,
    required this.controllers,
    required this.focusNodes,
    required this.onSubmitBlank,
    required this.onEditedBlank,
  });

  final _TrainingExercise exercise;
  final Map<int, TextEditingController> controllers;
  final Map<int, FocusNode> focusNodes;
  final ValueChanged<int> onSubmitBlank;
  final ValueChanged<int> onEditedBlank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEDC9A)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in exercise.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 8,
                  children: [
                    for (final run in _groupExerciseTokens(line.tokens))
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          for (final token in run)
                            if (token.blankId == null)
                              Text(
                                token.text,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  height: 1.8,
                                  color: const Color(0xFF2F2510),
                                ),
                              )
                            else
                              _AnswerBlank(
                                blank: exercise.blanks[token.blankId]!,
                                controller: controllers[token.blankId]!,
                                focusNode: focusNodes[token.blankId]!,
                                onSubmitted: onSubmitBlank,
                                onChanged: onEditedBlank,
                              ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AnswerBlank extends StatelessWidget {
  const _AnswerBlank({
    required this.blank,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onChanged,
  });

  final _TrainingBlank blank;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<int> onSubmitted;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (blank.status == _BlankStatus.correct) {
      return Text(
        blank.revealText,
        style: theme.textTheme.titleMedium?.copyWith(
          height: 1.8,
          color: const Color(0xFF2F2510),
          fontWeight: FontWeight.w600,
        ),
      );
    }

    final width = _blankWidth(blank.revealText);
    final isWrong = blank.status == _BlankStatus.incorrect;

    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        textInputAction: TextInputAction.done,
        keyboardType: TextInputType.text,
        style: theme.textTheme.titleMedium?.copyWith(
          color: isWrong ? Colors.red.shade700 : const Color(0xFF2F2510),
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: ' ',
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          filled: false,
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: isWrong ? Colors.red.shade700 : const Color(0xFF7B5A00),
              width: 1.5,
            ),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: isWrong ? Colors.red.shade700 : const Color(0xFFD8A935),
              width: 2,
            ),
          ),
        ),
        onChanged: (_) => onChanged(blank.id),
        onSubmitted: (_) => onSubmitted(blank.id),
        onTapOutside: (_) => focusNode.unfocus(),
      ),
    );
  }

  double _blankWidth(String text) {
    if (blank.characterLimit == 1) {
      return 30;
    }
    final length = _normalizeAnswer(text).length;
    final width = 24 + length * 18.0;
    return width.clamp(58, 260).toDouble();
  }
}

class _TrainingResultBanner extends StatelessWidget {
  const _TrainingResultBanner({
    required this.passed,
    required this.abandoned,
    required this.difficulty,
    required this.achievementLevel,
  });

  final bool passed;
  final bool abandoned;
  final TrainingDifficulty difficulty;
  final int achievementLevel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = passed
        ? '已通过${difficulty.label}训练'
        : abandoned
            ? '已查看答案'
            : '训练已结束';
    final message = passed
        ? '当前最高标记：${_achievementLabel(achievementLevel)}'
        : '本次训练已放弃，不会更新成就标记。';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: passed ? const Color(0xFFFFF4C7) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEDC9A)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              passed ? Icons.workspace_premium_outlined : Icons.visibility,
              color: const Color(0xFF9A7B2F),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(message, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrainingContentSection extends StatelessWidget {
  const _TrainingContentSection({
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
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectableTrainingBlock extends StatelessWidget {
  const _SelectableTrainingBlock({required this.text, required this.emptyText});

  final String text;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = text.trim();
    if (value.isEmpty) {
      return Text(emptyText, style: theme.textTheme.bodyMedium);
    }

    return SelectableText(
      value,
      style: theme.textTheme.bodyMedium?.copyWith(height: 1.65),
    );
  }
}

class _TrainingMessageView extends StatelessWidget {
  const _TrainingMessageView({
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
        padding: const EdgeInsets.all(28),
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

class _TrainingPoemSearchSheet extends StatefulWidget {
  const _TrainingPoemSearchSheet({required this.poems});

  final List<Poem> poems;

  @override
  State<_TrainingPoemSearchSheet> createState() =>
      _TrainingPoemSearchSheetState();
}

class _TrainingPoemSearchSheetState extends State<_TrainingPoemSearchSheet> {
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
    return widget.poems.where((poem) {
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
    }).toList();
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

class _TrainingJumpDialog extends StatefulWidget {
  const _TrainingJumpDialog({
    required this.initialPage,
    required this.total,
  });

  final int initialPage;
  final int total;

  @override
  State<_TrainingJumpDialog> createState() => _TrainingJumpDialogState();
}

class _TrainingJumpDialogState extends State<_TrainingJumpDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPage.toString());
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

class _TrainingExercise {
  _TrainingExercise({required this.lines, required this.blanks});

  final List<_TrainingLine> lines;
  final Map<int, _TrainingBlank> blanks;

  bool get allCorrect {
    return blanks.values.every((blank) => blank.status == _BlankStatus.correct);
  }

  factory _TrainingExercise.create({
    required Poem poem,
    required TrainingDifficulty difficulty,
    required Random random,
  }) {
    final lines = _visibleContentLines(poem.content);
    if (lines.isEmpty) {
      return _TrainingExercise(
        lines: const <_TrainingLine>[],
        blanks: <int, _TrainingBlank>{},
      );
    }

    switch (difficulty) {
      case TrainingDifficulty.xiucai:
        return _buildMaskedExercise(
          lines: lines,
          hiddenLineIndexes: const <int>{},
          wordDensity: 0.16,
          random: random,
        );
      case TrainingDifficulty.juren:
        return _buildMaskedExercise(
          lines: lines,
          hiddenLineIndexes: _chooseHiddenLineIndexes(lines, random),
          wordDensity: 0,
          random: random,
        );
      case TrainingDifficulty.gongsheng:
        return _buildMaskedExercise(
          lines: lines,
          hiddenLineIndexes: _chooseHiddenLineIndexes(lines, random),
          wordDensity: 0.18,
          random: random,
        );
      case TrainingDifficulty.jinshi:
        return _buildJinshiExercise(lines);
    }
  }
}

class _TrainingLine {
  const _TrainingLine({required this.tokens});

  final List<_TrainingToken> tokens;
}

class _TrainingToken {
  const _TrainingToken.text(this.text) : blankId = null;
  const _TrainingToken.blank(this.blankId) : text = '';

  final String text;
  final int? blankId;
}

class _TrainingBlank {
  _TrainingBlank({
    required this.id,
    required this.answer,
    required this.revealText,
    this.characterLimit,
  });

  final int id;
  final String answer;
  final String revealText;
  final int? characterLimit;
  _BlankStatus status = _BlankStatus.pending;
  String wrongText = '';
}

List<List<_TrainingToken>> _groupExerciseTokens(List<_TrainingToken> tokens) {
  final groups = <List<_TrainingToken>>[];

  for (final token in tokens) {
    final blankId = token.blankId;
    if (blankId != null) {
      groups.add([_TrainingToken.blank(blankId)]);
      continue;
    }

    for (final part in _splitTextToken(token.text)) {
      final textToken = _TrainingToken.text(part);
      if (_startsWithForbiddenLineStartPunctuation(part) &&
          groups.isNotEmpty) {
        groups.last.add(textToken);
      } else {
        groups.add([textToken]);
      }
    }
  }

  return groups;
}

List<int> _jinshiBlankRunFrom(_TrainingExercise exercise, int blankId) {
  for (final line in exercise.lines) {
    var started = false;
    final run = <int>[];
    for (final token in line.tokens) {
      final tokenBlankId = token.blankId;
      if (!started) {
        if (tokenBlankId == blankId) {
          started = true;
          run.add(blankId);
        }
        continue;
      }

      if (tokenBlankId != null) {
        run.add(tokenBlankId);
        continue;
      }

      if (token.text.trim().isNotEmpty) {
        return run;
      }
    }
    if (started) {
      return run;
    }
  }

  return <int>[blankId];
}

List<String> _splitTextToken(String text) {
  final parts = <String>[];
  final buffer = StringBuffer();

  void flushText() {
    if (buffer.isEmpty) {
      return;
    }
    parts.add(buffer.toString());
    buffer.clear();
  }

  for (final char in _charactersOf(text)) {
    if (_isForbiddenLineStartPunctuation(char)) {
      flushText();
      parts.add(char);
    } else {
      buffer.write(char);
    }
  }
  flushText();

  return parts;
}

bool _startsWithForbiddenLineStartPunctuation(String text) {
  final chars = _charactersOf(text);
  return chars.isNotEmpty && _isForbiddenLineStartPunctuation(chars.first);
}

class _CharPosition {
  const _CharPosition(this.lineIndex, this.charIndex);

  final int lineIndex;
  final int charIndex;
}

_TrainingExercise _buildMaskedExercise({
  required List<String> lines,
  required Set<int> hiddenLineIndexes,
  required double wordDensity,
  required Random random,
}) {
  var nextBlankId = 1;
  final blanks = <int, _TrainingBlank>{};
  final lineChars = [for (final line in lines) _charactersOf(line)];
  final masks = [
    for (final chars in lineChars) List<bool>.filled(chars.length, false),
  ];

  if (wordDensity > 0) {
    final candidates = <_CharPosition>[];
    for (var lineIndex = 0; lineIndex < lineChars.length; lineIndex += 1) {
      if (hiddenLineIndexes.contains(lineIndex)) {
        continue;
      }
      final chars = lineChars[lineIndex];
      for (var charIndex = 0; charIndex < chars.length; charIndex += 1) {
        if (!_isPunctuation(chars[charIndex])) {
          candidates.add(_CharPosition(lineIndex, charIndex));
        }
      }
    }
    candidates.shuffle(random);
    final targetCount = max(1, (candidates.length * wordDensity).round());
    var hiddenCount = 0;
    for (final candidate in candidates) {
      if (hiddenCount >= targetCount) {
        break;
      }
      final lineMask = masks[candidate.lineIndex];
      final chars = lineChars[candidate.lineIndex];
      if (lineMask[candidate.charIndex]) {
        continue;
      }
      lineMask[candidate.charIndex] = true;
      hiddenCount += 1;

      final nextIndex = candidate.charIndex + 1;
      if (hiddenCount < targetCount &&
          nextIndex < chars.length &&
          !lineMask[nextIndex] &&
          !_isPunctuation(chars[nextIndex]) &&
          random.nextBool()) {
        lineMask[nextIndex] = true;
        hiddenCount += 1;
      }
    }
  }

  final trainingLines = <_TrainingLine>[];
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    final line = lines[lineIndex];
    if (hiddenLineIndexes.contains(lineIndex)) {
      final tokens = <_TrainingToken>[];
      nextBlankId = _appendBlankedLineTokens(
        line: line,
        tokens: tokens,
        blanks: blanks,
        nextBlankId: nextBlankId,
      );
      trainingLines.add(_TrainingLine(tokens: tokens));
      continue;
    }

    final tokens = <_TrainingToken>[];
    final chars = lineChars[lineIndex];
    final mask = masks[lineIndex];
    final visibleBuffer = StringBuffer();
    var index = 0;
    while (index < chars.length) {
      if (!mask[index]) {
        visibleBuffer.write(chars[index]);
        index += 1;
        continue;
      }

      if (visibleBuffer.isNotEmpty) {
        tokens.add(_TrainingToken.text(visibleBuffer.toString()));
        visibleBuffer.clear();
      }
      final answerBuffer = StringBuffer();
      while (index < chars.length && mask[index]) {
        answerBuffer.write(chars[index]);
        index += 1;
      }
      final answer = answerBuffer.toString();
      final blank = _TrainingBlank(
        id: nextBlankId,
        answer: answer,
        revealText: answer,
      );
      blanks[nextBlankId] = blank;
      tokens.add(_TrainingToken.blank(nextBlankId));
      nextBlankId += 1;
    }
    if (visibleBuffer.isNotEmpty) {
      tokens.add(_TrainingToken.text(visibleBuffer.toString()));
    }
    trainingLines.add(_TrainingLine(tokens: tokens));
  }

  if (blanks.isEmpty) {
    final firstLine = lines.first;
    final blank = _TrainingBlank(
      id: nextBlankId,
      answer: firstLine,
      revealText: firstLine,
    );
    blanks[nextBlankId] = blank;
    trainingLines[0] = _TrainingLine(tokens: [
      _TrainingToken.blank(nextBlankId),
    ]);
  }

  return _TrainingExercise(lines: trainingLines, blanks: blanks);
}

_TrainingExercise _buildJinshiExercise(List<String> lines) {
  var nextBlankId = 1;
  final blanks = <int, _TrainingBlank>{};
  final trainingLines = <_TrainingLine>[];

  for (final line in lines) {
    final tokens = <_TrainingToken>[];
    nextBlankId = _appendJinshiLineTokens(
      line: line,
      tokens: tokens,
      blanks: blanks,
      nextBlankId: nextBlankId,
    );
    trainingLines.add(_TrainingLine(tokens: tokens));
  }

  return _TrainingExercise(lines: trainingLines, blanks: blanks);
}

int _appendJinshiLineTokens({
  required String line,
  required List<_TrainingToken> tokens,
  required Map<int, _TrainingBlank> blanks,
  required int nextBlankId,
}) {
  for (final char in _charactersOf(line)) {
    if (_isPunctuation(char) || char.trim().isEmpty) {
      tokens.add(_TrainingToken.text(char));
      continue;
    }

    final blank = _TrainingBlank(
      id: nextBlankId,
      answer: char,
      revealText: char,
      characterLimit: 1,
    );
    blanks[nextBlankId] = blank;
    tokens.add(_TrainingToken.blank(nextBlankId));
    nextBlankId += 1;
  }

  return nextBlankId;
}

int _appendBlankedLineTokens({
  required String line,
  required List<_TrainingToken> tokens,
  required Map<int, _TrainingBlank> blanks,
  required int nextBlankId,
}) {
  final phraseBuffer = StringBuffer();

  void flushPhrase() {
    if (phraseBuffer.isEmpty) {
      return;
    }
    final answer = phraseBuffer.toString();
    final blank = _TrainingBlank(
      id: nextBlankId,
      answer: answer,
      revealText: answer,
    );
    blanks[nextBlankId] = blank;
    tokens.add(_TrainingToken.blank(nextBlankId));
    nextBlankId += 1;
    phraseBuffer.clear();
  }

  for (final char in _charactersOf(line)) {
    if (_isPunctuation(char)) {
      flushPhrase();
      tokens.add(_TrainingToken.text(char));
    } else {
      phraseBuffer.write(char);
    }
  }
  flushPhrase();

  if (tokens.isEmpty) {
    final blank = _TrainingBlank(
      id: nextBlankId,
      answer: line,
      revealText: line,
    );
    blanks[nextBlankId] = blank;
    tokens.add(_TrainingToken.blank(nextBlankId));
    nextBlankId += 1;
  }

  return nextBlankId;
}

Set<int> _chooseHiddenLineIndexes(List<String> lines, Random random) {
  final indexes = [
    for (var index = 0; index < lines.length; index += 1)
      if (_normalizeAnswer(lines[index]).isNotEmpty) index,
  ];
  if (indexes.isEmpty) {
    return const <int>{};
  }
  indexes.shuffle(random);
  final count = max(1, (indexes.length / 2).round());
  return indexes.take(count).toSet();
}

List<String> _visibleContentLines(String content) {
  return content
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

List<String> _charactersOf(String value) {
  return value.runes.map(String.fromCharCode).toList();
}

String _normalizeAnswer(String value) {
  final buffer = StringBuffer();
  for (final char in _charactersOf(value)) {
    if (!_isPunctuation(char) && char.trim().isNotEmpty) {
      buffer.write(char);
    }
  }
  return buffer.toString();
}

List<String> _jinshiInputCharacters(String value) {
  final chars = <String>[];
  for (final char in _charactersOf(value.trim())) {
    if (_isPunctuation(char) || char.trim().isEmpty) {
      break;
    }
    chars.add(char);
  }
  return chars;
}

bool _isPunctuation(String char) {
  const punctuation =
      '，。？！；：、“”‘’（）《》〈〉【】「」『』,.!?;:\'"()[]{}-—…·';
  return punctuation.contains(char);
}

bool _isForbiddenLineStartPunctuation(String char) {
  const punctuation = '，。？！；：、”’）】》〉」』,.!?;:)]}';
  return punctuation.contains(char);
}

String _achievementLabel(int level) {
  if (level >= TrainingDifficulty.jinshi.level) {
    return '进士';
  }
  if (level >= TrainingDifficulty.gongsheng.level) {
    return '贡生';
  }
  if (level >= TrainingDifficulty.juren.level) {
    return '举人';
  }
  if (level >= TrainingDifficulty.xiucai.level) {
    return '秀才';
  }
  return '未通过';
}
