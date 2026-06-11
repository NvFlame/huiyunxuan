import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/poem_collection.dart';
import 'poem_agent_chat_screen.dart';
import 'poem_list_screen.dart';

class CollectionListScreen extends StatefulWidget {
  const CollectionListScreen({super.key});

  @override
  State<CollectionListScreen> createState() => _CollectionListScreenState();
}

class _CollectionListScreenState extends State<CollectionListScreen> {
  late Future<List<PoemCollection>> _collectionsFuture;

  @override
  void initState() {
    super.initState();
    _loadCollections();
  }

  void _loadCollections() {
    _collectionsFuture = AppDatabase.instance.getCollections();
  }

  Future<void> _refreshCollections() async {
    setState(_loadCollections);
    await _collectionsFuture;
  }

  Future<void> _showCollectionDialog({PoemCollection? collection}) async {
    final result = await showDialog<_CollectionDraft>(
      context: context,
      builder: (context) {
        return _CollectionDialog(collection: collection);
      },
    );

    if (result == null) {
      return;
    }

    if (collection == null) {
      await AppDatabase.instance.createCollection(
        name: result.name,
        description: result.description,
      );
    } else {
      await AppDatabase.instance.updateCollection(
        collection.copyWith(name: result.name, description: result.description),
      );
    }

    if (!mounted) {
      return;
    }
    await _refreshCollections();
  }

  Future<void> _deleteCollection(PoemCollection collection) async {
    final id = collection.id;
    if (id == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除数据库'),
          content: Text('确定删除“${collection.name}”吗？其中的诗词也会一起删除。'),
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

    await AppDatabase.instance.deleteCollection(id);
    if (!mounted) {
      return;
    }
    await _refreshCollections();
  }

  Future<void> _openCollection(PoemCollection collection) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => PoemListScreen(collection: collection),
      ),
    );
    if (mounted) {
      await _refreshCollections();
    }
  }

  Future<void> _openAgentChat() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const PoemAgentChatScreen(),
      ),
    );
    if (mounted && changed == true) {
      await _refreshCollections();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('诗词库管理')),
      body: FutureBuilder<List<PoemCollection>>(
        future: _collectionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _MessageView(
              icon: Icons.error_outline,
              title: '数据库读取失败',
              message: snapshot.error.toString(),
            );
          }

          final collections = snapshot.data ?? const <PoemCollection>[];
          if (collections.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refreshCollections,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 160),
                  _MessageView(
                    icon: Icons.library_add_outlined,
                    title: '还没有训练库',
                    message: '点击右下角按钮添加第一个诗词数据库。',
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshCollections,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemCount: collections.length,
              itemBuilder: (context, index) {
                final collection = collections[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(
                      collection.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: collection.description.isEmpty
                        ? const Text('诗词训练库')
                        : Text(
                            collection.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing: PopupMenuButton<_CollectionAction>(
                      onSelected: (action) {
                        switch (action) {
                          case _CollectionAction.edit:
                            _showCollectionDialog(collection: collection);
                          case _CollectionAction.delete:
                            _deleteCollection(collection);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: _CollectionAction.edit,
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('编辑'),
                          ),
                        ),
                        PopupMenuItem(
                          value: _CollectionAction.delete,
                          child: ListTile(
                            leading: Icon(Icons.delete_outline),
                            title: Text('删除'),
                          ),
                        ),
                      ],
                    ),
                    onTap: () => _openCollection(collection),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FloatingActionButton(
              heroTag: 'collection_agent_chat',
              onPressed: _openAgentChat,
              tooltip: '诗词库助手',
              child: const Icon(Icons.smart_toy_outlined),
            ),
            FloatingActionButton(
              heroTag: 'collection_add',
              onPressed: () => _showCollectionDialog(),
              tooltip: '添加数据库',
              child: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}

enum _CollectionAction { edit, delete }

class _CollectionDraft {
  const _CollectionDraft({required this.name, required this.description});

  final String name;
  final String description;
}

class _CollectionDialog extends StatefulWidget {
  const _CollectionDialog({this.collection});

  final PoemCollection? collection;

  @override
  State<_CollectionDialog> createState() => _CollectionDialogState();
}

class _CollectionDialogState extends State<_CollectionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.collection?.name);
    _descriptionController = TextEditingController(
      text: widget.collection?.description,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.pop(
      context,
      _CollectionDraft(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.collection != null;
    return AlertDialog(
      title: Text(isEditing ? '编辑数据库' : '添加数据库'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '数据库名称',
                hintText: '例如：李商隐诗选',
              ),
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入数据库名称';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '说明',
                hintText: '可选',
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
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
