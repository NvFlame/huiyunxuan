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
  late Future<List<Poem>> _poemsFuture;

  int get _collectionId => widget.collection.id!;

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
          title: const Text('删除诗词'),
          content: Text('确定删除《${poem.title}》吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
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
      appBar: AppBar(title: Text(widget.collection.name)),
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
                labelText: '搜索标题、作者、内容或备注',
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
                        onTap: () => _openEditor(poem: poem),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: '添加原创诗词',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _PoemCard extends StatelessWidget {
  const _PoemCard({
    required this.poem,
    required this.onTap,
    required this.onDelete,
  });

  final Poem poem;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contentPreview = poem.content
        .replaceAll('\r\n', '\n')
        .replaceAll('\n', ' / ');

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              IconButton(
                tooltip: '删除诗词',
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
