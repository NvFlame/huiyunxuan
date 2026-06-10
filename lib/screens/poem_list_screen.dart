import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/poem.dart';
import '../models/poem_collection.dart';
import 'poem_editor_screen.dart';

class PoemListScreen extends StatefulWidget {
  const PoemListScreen({super.key, required this.collection});

  final PoemCollection collection;

  @override
  State<PoemListScreen> createState() => _PoemListScreenState();
}

class _PoemListScreenState extends State<PoemListScreen> {
  final _searchController = TextEditingController();
  final Set<int> _selectedPoemIds = <int>{};
  late Future<List<Poem>> _poemsFuture;

  int get _collectionId => widget.collection.id!;
  bool get _isSelecting => _selectedPoemIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadPoems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadPoems() {
    _poemsFuture = AppDatabase.instance.getPoems(
      _collectionId,
      query: _searchController.text,
    );
  }

  Future<void> _refreshPoems() async {
    setState(_loadPoems);
    await _poemsFuture;
  }

  void _selectPoem(Poem poem) {
    final id = poem.id;
    if (id == null) {
      return;
    }

    setState(() {
      _selectedPoemIds.add(id);
    });
  }

  void _togglePoemSelection(Poem poem) {
    final id = poem.id;
    if (id == null) {
      return;
    }

    setState(() {
      if (_selectedPoemIds.contains(id)) {
        _selectedPoemIds.remove(id);
      } else {
        _selectedPoemIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(_selectedPoemIds.clear);
  }

  void _copySelectedPoems() {
    final selectedIds = _selectedPoemIds.toList(growable: false);
    if (selectedIds.isEmpty) {
      return;
    }

    _PoemClipboard.copy(
      sourceCollectionId: _collectionId,
      poemIds: selectedIds,
    );
    _clearSelection();
    _showSnackBar('已复制 ${selectedIds.length} 首诗词');
  }

  void _cutSelectedPoems() {
    final selectedIds = _selectedPoemIds.toList(growable: false);
    if (selectedIds.isEmpty) {
      return;
    }

    _PoemClipboard.cut(
      sourceCollectionId: _collectionId,
      poemIds: selectedIds,
    );
    _clearSelection();
    _showSnackBar('已剪切 ${selectedIds.length} 首诗词');
  }

  Future<void> _removeSelectedPoems() async {
    final selectedIds = _selectedPoemIds.toList(growable: false);
    if (selectedIds.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('移除诗词'),
          content: Text('确定从当前诗词库移除选中的 ${selectedIds.length} 首诗词吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('移除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final removedCount = await AppDatabase.instance.removePoemsFromCollection(
      collectionId: _collectionId,
      poemIds: selectedIds,
    );

    if (!mounted) {
      return;
    }
    _selectedPoemIds.clear();
    await _refreshPoems();
    if (mounted) {
      _showSnackBar('已移除 $removedCount 首诗词');
    }
  }

  Future<void> _pastePoems() async {
    final clipboard = _PoemClipboard.data;
    if (clipboard == null || clipboard.poemIds.isEmpty) {
      return;
    }

    final addedPoemIds = await AppDatabase.instance.addPoemsToCollection(
      collectionId: _collectionId,
      poemIds: clipboard.poemIds,
    );
    final skippedCount = clipboard.poemIds.length - addedPoemIds.length;
    var message = addedPoemIds.isEmpty
        ? '剪贴板中的诗词已在当前诗词库中'
        : '已粘贴 ${addedPoemIds.length} 首诗词';

    if (skippedCount > 0 && addedPoemIds.isNotEmpty) {
      message = '已粘贴 ${addedPoemIds.length} 首诗词，跳过 $skippedCount 首已有诗词';
    }

    if (clipboard.mode == _PoemClipboardMode.cut &&
        clipboard.sourceCollectionId != _collectionId &&
        addedPoemIds.isNotEmpty) {
      await AppDatabase.instance.removePoemsFromCollection(
        collectionId: clipboard.sourceCollectionId,
        poemIds: addedPoemIds,
      );
      _PoemClipboard.clear();
      message = skippedCount > 0
          ? '已移动 ${addedPoemIds.length} 首诗词，跳过 $skippedCount 首已有诗词'
          : '已移动 ${addedPoemIds.length} 首诗词';
    }

    if (!mounted) {
      return;
    }
    await _refreshPoems();
    if (mounted) {
      setState(() {});
      _showSnackBar(message);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openEditor({Poem? poem}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            PoemEditorScreen(collectionId: _collectionId, poem: poem),
      ),
    );

    if (saved == true && mounted) {
      await _refreshPoems();
    }
  }

  Future<void> _deletePoem(Poem poem) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('移除诗词'),
          content: Text('确定从当前诗词库移除《${poem.title}》吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('移除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await AppDatabase.instance.deletePoem(poem);
    if (mounted) {
      await _refreshPoems();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空搜索',
                        onPressed: () {
                          _searchController.clear();
                          _refreshPoems();
                        },
                        icon: const Icon(Icons.close),
                      ),
                labelText: '搜索标题、作者、内容、备注、注释或赏析',
              ),
              onChanged: (_) => _refreshPoems(),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Poem>>(
              future: _poemsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return _PoemMessageView(
                    icon: Icons.error_outline,
                    title: '诗词读取失败',
                    message: snapshot.error.toString(),
                  );
                }

                final poems = snapshot.data ?? const <Poem>[];
                if (poems.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refreshPoems,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120),
                        _PoemMessageView(
                          icon: Icons.note_add_outlined,
                          title: _searchController.text.trim().isEmpty
                              ? '还没有诗词'
                              : '没有找到匹配结果',
                          message: _searchController.text.trim().isEmpty
                              ? '点击右下角按钮添加原创诗词。'
                              : '可以换一个关键词继续搜索。',
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refreshPoems,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88, top: 4),
                    itemCount: poems.length,
                    itemBuilder: (context, index) {
                      final poem = poems[index];
                      return _PoemCard(
                        poem: poem,
                        selectionMode: _isSelecting,
                        selected: poem.id != null &&
                            _selectedPoemIds.contains(poem.id),
                        onTap: () {
                          if (_isSelecting) {
                            _togglePoemSelection(poem);
                          } else {
                            _openEditor(poem: poem);
                          }
                        },
                        onLongPress: () => _selectPoem(poem),
                        onDelete: () => _deletePoem(poem),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _isSelecting
          ? null
          : FloatingActionButton(
              onPressed: () => _openEditor(),
              tooltip: '添加原创诗词',
              child: const Icon(Icons.add),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (_isSelecting) {
      return AppBar(
        leading: IconButton(
          tooltip: '取消选择',
          onPressed: _clearSelection,
          icon: const Icon(Icons.close),
        ),
        title: Text('已选择 ${_selectedPoemIds.length} 首'),
        actions: [
          IconButton(
            tooltip: '复制',
            onPressed: _copySelectedPoems,
            icon: const Icon(Icons.content_copy),
          ),
          IconButton(
            tooltip: '剪切',
            onPressed: _cutSelectedPoems,
            icon: const Icon(Icons.content_cut),
          ),
          IconButton(
            tooltip: '移除',
            onPressed: _removeSelectedPoems,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      );
    }

    return AppBar(
      title: Text(widget.collection.name),
      actions: [
        if (_PoemClipboard.hasData)
          IconButton(
            tooltip: '粘贴',
            onPressed: _pastePoems,
            icon: const Icon(Icons.content_paste),
          ),
      ],
    );
  }
}

class _PoemCard extends StatelessWidget {
  const _PoemCard({
    required this.poem,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
  });

  final Poem poem;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contentPreview = poem.content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectionMode) ...[
                Checkbox(value: selected, onChanged: (_) => onTap()),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      poem.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (poem.dynasty.isNotEmpty) poem.dynasty,
                        poem.author,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (poem.remark.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4C7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            '备注：${poem.remark}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      contentPreview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (!selectionMode)
                IconButton(
                  tooltip: '从当前诗词库移除',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PoemClipboardMode { copy, cut }

class _PoemClipboard {
  static _PoemClipboardData? _data;

  static _PoemClipboardData? get data => _data;

  static bool get hasData => _data != null && _data!.poemIds.isNotEmpty;

  static void copy({
    required int sourceCollectionId,
    required Iterable<int> poemIds,
  }) {
    _data = _PoemClipboardData(
      mode: _PoemClipboardMode.copy,
      sourceCollectionId: sourceCollectionId,
      poemIds: poemIds.toSet().toList(growable: false),
    );
  }

  static void cut({
    required int sourceCollectionId,
    required Iterable<int> poemIds,
  }) {
    _data = _PoemClipboardData(
      mode: _PoemClipboardMode.cut,
      sourceCollectionId: sourceCollectionId,
      poemIds: poemIds.toSet().toList(growable: false),
    );
  }

  static void clear() {
    _data = null;
  }
}

class _PoemClipboardData {
  const _PoemClipboardData({
    required this.mode,
    required this.sourceCollectionId,
    required this.poemIds,
  });

  final _PoemClipboardMode mode;
  final int sourceCollectionId;
  final List<int> poemIds;
}

class _PoemMessageView extends StatelessWidget {
  const _PoemMessageView({
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
            const SizedBox(height: 16),
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
