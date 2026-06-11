import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/poem.dart';

class PoemEditorScreen extends StatefulWidget {
  const PoemEditorScreen({super.key, required this.collectionId, this.poem});

  final int collectionId;
  final Poem? poem;

  @override
  State<PoemEditorScreen> createState() => _PoemEditorScreenState();
}

class _PoemEditorScreenState extends State<PoemEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _authorController;
  late final TextEditingController _dynastyController;
  late final TextEditingController _prefaceController;
  late final TextEditingController _contentController;
  late final TextEditingController _remarkController;
  late final TextEditingController _translationController;
  late final TextEditingController _annotationController;
  late final TextEditingController _learningNoteController;
  late final TextEditingController _appreciationController;
  bool _saving = false;

  bool get _isEditing => widget.poem != null;

  @override
  void initState() {
    super.initState();
    final poem = widget.poem;
    _titleController = TextEditingController(text: poem?.title);
    _authorController = TextEditingController(text: poem?.author);
    _dynastyController = TextEditingController(text: poem?.dynasty);
    _prefaceController = TextEditingController(text: poem?.preface);
    _contentController = TextEditingController(text: poem?.content);
    _remarkController = TextEditingController(text: poem?.remark);
    _translationController = TextEditingController(text: poem?.translation);
    _annotationController = TextEditingController(text: poem?.annotation);
    _learningNoteController = TextEditingController(text: poem?.learningNote);
    _appreciationController = TextEditingController(text: poem?.appreciation);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _dynastyController.dispose();
    _prefaceController.dispose();
    _contentController.dispose();
    _remarkController.dispose();
    _translationController.dispose();
    _annotationController.dispose();
    _learningNoteController.dispose();
    _appreciationController.dispose();
    super.dispose();
  }

  Future<void> _savePoem() async {
    if (_saving || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _saving = true;
    });

    final database = AppDatabase.instance;
    final existing = widget.poem;

    if (existing == null) {
      await database.createPoem(
        collectionId: widget.collectionId,
        title: _titleController.text,
        author: _authorController.text,
        dynasty: _dynastyController.text,
        preface: _prefaceController.text,
        content: _contentController.text,
        remark: _remarkController.text,
        translation: _translationController.text,
        annotation: _annotationController.text,
        learningNote: _learningNoteController.text,
        appreciation: _appreciationController.text,
      );
    } else {
      await database.updatePoem(
        existing.copyWith(
          title: _titleController.text.trim(),
          author: _authorController.text.trim(),
          dynasty: _dynastyController.text.trim(),
          preface: _prefaceController.text.trim(),
          content: _contentController.text.trim(),
          remark: _remarkController.text.trim(),
          translation: _translationController.text.trim(),
          annotation: _annotationController.text.trim(),
          learningNote: _learningNoteController.text.trim(),
          appreciation: _appreciationController.text.trim(),
        ),
      );
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑诗词' : '添加原创诗词'),
        actions: [
          IconButton(
            tooltip: '保存',
            onPressed: _saving ? null : _savePoem,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '标题',
                  hintText: '例如：无题',
                ),
                textInputAction: TextInputAction.next,
                validator: _required('请输入标题'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _authorController,
                decoration: const InputDecoration(
                  labelText: '作者',
                  hintText: '例如：李商隐',
                ),
                textInputAction: TextInputAction.next,
                validator: _required('请输入作者'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dynastyController,
                decoration: const InputDecoration(
                  labelText: '朝代',
                  hintText: '例如：唐',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _remarkController,
                decoration: const InputDecoration(
                  labelText: '备注 / 别名',
                  hintText: '例如：相见时难、彩凤',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _prefaceController,
                decoration: const InputDecoration(
                  labelText: '序 / 小序',
                  hintText: '例如：丙辰中秋，欢饮达旦，大醉，作此篇，兼怀子由。',
                  alignLabelWithHint: true,
                ),
                minLines: 2,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contentController,
                decoration: const InputDecoration(
                  labelText: '内容',
                  hintText: '按诗句或词句换行，一句一行',
                  alignLabelWithHint: true,
                ),
                minLines: 8,
                maxLines: 16,
                keyboardType: TextInputType.multiline,
                validator: _required('请输入诗词内容'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _annotationController,
                decoration: const InputDecoration(
                  labelText: '注释',
                  hintText: '用 [行号] 开头，一条注释一行',
                  alignLabelWithHint: true,
                ),
                minLines: 4,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _learningNoteController,
                decoration: const InputDecoration(
                  labelText: '学习笔记',
                  hintText: '记录个人理解、疑问、记忆方法或学习心得',
                  alignLabelWithHint: true,
                ),
                minLines: 4,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _translationController,
                decoration: const InputDecoration(
                  labelText: '译文',
                  hintText: '尽量与原文逐句对应，一句译文一行',
                  alignLabelWithHint: true,
                ),
                minLines: 4,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _appreciationController,
                decoration: const InputDecoration(
                  labelText: '赏析',
                  hintText: '记录主题、情感、手法和个人理解',
                  alignLabelWithHint: true,
                ),
                minLines: 4,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving ? null : _savePoem,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? '保存中' : '保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  FormFieldValidator<String> _required(String message) {
    return (value) {
      if (value == null || value.trim().isEmpty) {
        return message;
      }
      return null;
    };
  }
}
