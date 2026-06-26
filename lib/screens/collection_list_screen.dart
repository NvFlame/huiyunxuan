import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/poem_collection.dart';
import '../services/poem_collection_export_service.dart';
import '../services/poem_fingerprint_service.dart';
import '../services/poem_import_service.dart';
import '../theme/app_typography.dart';
import '../widgets/duplicate_poem_dialog.dart';
import '../widgets/huiyun_visuals.dart';
import 'poem_agent_chat_screen.dart';
import 'poem_list_screen.dart';

class CollectionListScreen extends StatefulWidget {
  const CollectionListScreen({super.key});

  @override
  State<CollectionListScreen> createState() => _CollectionListScreenState();
}

class _CollectionListScreenState extends State<CollectionListScreen> {
  static const _exportService = PoemCollectionExportService();

  late Future<List<PoemCollection>> _collectionsFuture;
  int? _exportingCollectionId;

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
    final result = await showDialog<_CollectionDialogResult>(
      context: context,
      builder: (context) {
        return _CollectionDialog(collection: collection);
      },
    );

    if (result == null) {
      return;
    }

    if (result.action == _CollectionDialogAction.importCollection) {
      await _showImportCollectionDialog();
      return;
    }

    final draft = result.draft;
    if (draft == null) {
      return;
    }

    if (collection == null) {
      await AppDatabase.instance.createCollection(
        name: draft.name,
        description: draft.description,
      );
    } else {
      await AppDatabase.instance.updateCollection(
        collection.copyWith(name: draft.name, description: draft.description),
      );
    }

    if (!mounted) {
      return;
    }
    await _refreshCollections();
  }

  Future<void> _showImportCollectionDialog() async {
    final result = await showDialog<_CollectionImportResult>(
      context: context,
      builder: (context) => const _CollectionImportDialog(),
    );
    if (result == null) {
      return;
    }

    final shouldContinue = await _confirmCollectionImportDuplicates(result);
    if (!shouldContinue) {
      return;
    }

    final collectionId = await AppDatabase.instance.createCollection(
      name: result.collection.name,
      description: result.collection.description,
    );
    for (final poem in result.collection.poems) {
      await AppDatabase.instance.createPoem(
        collectionId: collectionId,
        title: poem.title,
        author: poem.author,
        dynasty: poem.dynasty,
        preface: poem.preface,
        content: poem.content,
        remark: poem.remark,
        translation: poem.translation,
        annotation: poem.annotation,
        learningNote: poem.learningNote,
        appreciation: poem.appreciation,
        prosodySupported: poem.prosodySupported,
        prosodyEnabled: poem.prosodyEnabled,
        prosodySystem: poem.prosodySystem,
        prosodyForm: poem.prosodyForm,
        prosodyRhymeBook: poem.prosodyRhymeBook,
        prosodyNote: poem.prosodyNote,
        prosodyOverridesJson: poem.prosodyOverridesJson,
        prosodyVerifiedAt: poem.prosodyVerifiedAt,
        prosodyVerifiedBy: poem.prosodyVerifiedBy,
      );
    }

    if (!mounted) {
      return;
    }
    await _refreshCollections();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '已导入“${result.collection.name}”，共 ${result.collection.poems.length} 首诗词',
            ),
          ),
        );
    }
  }

  Future<bool> _confirmCollectionImportDuplicates(
    _CollectionImportResult result,
  ) async {
    final candidatesById = <int, DuplicatePoemCandidate>{};
    for (final poem in result.collection.poems) {
      final candidates = await AppDatabase.instance.findPotentialDuplicatePoems(
        author: poem.author,
        content: poem.content,
        limit: 3,
      );
      for (final candidate in candidates) {
        final id = candidate.poem.id;
        if (id != null) {
          candidatesById[id] = candidate;
        }
      }
    }
    if (!mounted) {
      return false;
    }
    return confirmPotentialDuplicatePoems(
      context: context,
      candidates: candidatesById.values.toList(growable: false),
      title: '导入前发现疑似重复',
    );
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

  Future<void> _exportCollection(PoemCollection collection) async {
    final id = collection.id;
    if (id == null || _exportingCollectionId != null) {
      return;
    }

    setState(() {
      _exportingCollectionId = id;
    });
    try {
      final result = await _exportService.exportCollection(collection);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result == null
                  ? '已取消导出'
                  : '已导出“${collection.name}”，共 ${result.poemCount} 首诗词',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('导出失败：$error')));
    } finally {
      if (mounted) {
        setState(() {
          _exportingCollectionId = null;
        });
      }
    }
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
      appBar: AppBar(
        title: Text(
          '诗词库管理',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFamily: kFeiHuaSongTiFontFamily,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF4D3714),
              ),
        ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
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
                final isExporting = _exportingCollectionId == collection.id;
                return HuiyunPageEntrance(
                  index: index,
                  child: HuiyunPaperCard(
                    onTap: () => _openCollection(collection),
                    padding: EdgeInsets.zero,
                    child: ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(
                      collection.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: kFeiHuaSongTiFontFamily,
                        fontWeight: FontWeight.w700,
                      ),
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
                          case _CollectionAction.export:
                            _exportCollection(collection);
                          case _CollectionAction.edit:
                            _showCollectionDialog(collection: collection);
                          case _CollectionAction.delete:
                            _deleteCollection(collection);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: _CollectionAction.export,
                          enabled: !isExporting,
                          child: ListTile(
                            leading: isExporting
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.download_outlined),
                            title: Text(isExporting ? '导出中' : '导出'),
                          ),
                        ),
                        const PopupMenuItem(
                          value: _CollectionAction.edit,
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('编辑'),
                          ),
                        ),
                        const PopupMenuItem(
                          value: _CollectionAction.delete,
                          child: ListTile(
                            leading: Icon(Icons.delete_outline),
                            title: Text('删除'),
                          ),
                        ),
                      ],
                    ),
                    ),
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

enum _CollectionAction { export, edit, delete }

enum _CollectionDialogAction { save, importCollection }

class _CollectionDialogResult {
  const _CollectionDialogResult.save(this.draft)
      : action = _CollectionDialogAction.save;
  const _CollectionDialogResult.importCollection()
      : action = _CollectionDialogAction.importCollection,
        draft = null;

  final _CollectionDialogAction action;
  final _CollectionDraft? draft;
}

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
      _CollectionDialogResult.save(
        _CollectionDraft(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
        ),
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
        if (!isEditing)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(
                context,
                const _CollectionDialogResult.importCollection(),
              );
            },
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('导入'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

class _CollectionImportResult {
  const _CollectionImportResult({required this.collection});

  final ImportedCollectionDraft collection;
}

class _CollectionImportDialog extends StatefulWidget {
  const _CollectionImportDialog();

  @override
  State<_CollectionImportDialog> createState() => _CollectionImportDialogState();
}

class _CollectionImportDialogState extends State<_CollectionImportDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _textController = TextEditingController();
  String? _errorText;
  bool _pickingFile = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final collection = parsePoemCollectionImport(
        _textController.text,
        fallbackName: _nameController.text,
        fallbackDescription: _descriptionController.text,
      );
      if (collection.name.trim().isEmpty) {
        setState(() {
          _errorText = '请输入数据库名称，或在 JSON 中提供 name 字段';
        });
        return;
      }
      Navigator.pop(
        context,
        _CollectionImportResult(collection: collection),
      );
    } on FormatException catch (error) {
      setState(() {
        _errorText = error.message;
      });
    } catch (error) {
      setState(() {
        _errorText = error.toString();
      });
    }
  }

  Future<void> _pickFile() async {
    setState(() {
      _pickingFile = true;
      _errorText = null;
    });
    try {
      final text = await pickPoemImportFileText();
      if (!mounted) {
        return;
      }
      if (text != null) {
        setState(() {
          _textController.text = text;
        });
      }
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _pickingFile = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入诗词库'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '数据库名称',
                  hintText: 'JSON 中已有 name 时可不填',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: '说明',
                  hintText: '可选',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _pickingFile ? null : _pickFile,
                  icon: _pickingFile
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_outlined),
                  label: Text(_pickingFile ? '读取中' : '选择 JSON / JSONL 文件'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                decoration: InputDecoration(
                  labelText: 'JSON / JSONL',
                  hintText: '{"name":"唐诗三百首","poems":[...]}',
                  alignLabelWithHint: true,
                  errorText: _errorText,
                ),
                minLines: 8,
                maxLines: 14,
                keyboardType: TextInputType.multiline,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('导入'),
        ),
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
    return HuiyunEmptyState(
      icon: icon,
      title: title,
      message: message,
    );
  }
}
