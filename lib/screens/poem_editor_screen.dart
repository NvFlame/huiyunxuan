import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/poem.dart';
import '../services/poem_import_service.dart';
import '../services/prosody_service.dart';
import '../theme/app_typography.dart';
import '../widgets/duplicate_poem_dialog.dart';
import '../widgets/prosody_calibration_dialog.dart';

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
  late ProsodyMetadata _prosodyMetadata;
  String _prosodyOverridesJson = '';
  DateTime? _prosodyVerifiedAt;
  String _prosodyVerifiedBy = '';
  bool _prosodyDisplayTouched = false;
  bool _prosodyDetailsTouched = false;
  bool _suppressProsodySourceListener = false;
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
    _prosodyMetadata = poem == null
        ? _inferProsodyFromForm()
        : metadataFromPoem(poem);
    _prosodyOverridesJson = poem?.prosodyOverridesJson ?? '';
    _prosodyVerifiedAt = poem?.prosodyVerifiedAt;
    _prosodyVerifiedBy = poem?.prosodyVerifiedBy ?? '';
    for (final controller in [
      _titleController,
      _dynastyController,
      _contentController,
      _remarkController,
    ]) {
      controller.addListener(_handleProsodySourceChanged);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _titleController,
      _dynastyController,
      _contentController,
      _remarkController,
    ]) {
      controller.removeListener(_handleProsodySourceChanged);
    }
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
    final prosody = _prosodyForSave();
    final clearProsodyVerification =
        existing != null && _shouldClearProsodyVerification(existing);
    final prosodyOverridesJson =
        clearProsodyVerification ? '' : _prosodyOverridesJson;
    final prosodyVerifiedAt =
        clearProsodyVerification ? null : _prosodyVerifiedAt;
    final prosodyVerifiedBy =
        clearProsodyVerification ? '' : _prosodyVerifiedBy;
    final shouldContinue = await _confirmNoDuplicate(
      author: _authorController.text,
      content: _contentController.text,
      excludePoemId: existing?.id,
    );
    if (!shouldContinue) {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
      return;
    }

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
        prosodySupported: prosody.supported,
        prosodyEnabled: prosody.enabled,
        prosodySystem: prosody.system,
        prosodyForm: prosody.form,
        prosodyRhymeBook: prosody.rhymeBook,
        prosodyNote: prosody.note,
        prosodyOverridesJson: prosodyOverridesJson,
        prosodyVerifiedAt: prosodyVerifiedAt,
        prosodyVerifiedBy: prosodyVerifiedBy,
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
          prosodySupported: prosody.supported,
          prosodyEnabled: prosody.enabled,
          prosodySystem: prosody.system,
          prosodyForm: prosody.form,
          prosodyRhymeBook: prosody.rhymeBook,
          prosodyNote: prosody.note,
          prosodyOverridesJson: prosodyOverridesJson,
          prosodyVerifiedAt: prosodyVerifiedAt,
          prosodyVerifiedBy: prosodyVerifiedBy,
          clearProsodyVerification: clearProsodyVerification,
        ),
      );
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<bool> _confirmNoDuplicate({
    required String author,
    required String content,
    int? excludePoemId,
  }) async {
    final candidates = await AppDatabase.instance.findPotentialDuplicatePoems(
      author: author,
      content: content,
      excludePoemId: excludePoemId,
    );
    if (!mounted) {
      return false;
    }
    return confirmPotentialDuplicatePoems(
      context: context,
      candidates: candidates,
      title: '发现疑似重复作品',
    );
  }

  Future<void> _importPoemDraft() async {
    final draft = await showDialog<ImportedPoemDraft>(
      context: context,
      builder: (context) => const _SinglePoemImportDialog(),
    );
    if (draft == null || !mounted) {
      return;
    }

    setState(() {
      _suppressProsodySourceListener = true;
      _titleController.text = draft.title;
      _authorController.text = draft.author;
      _dynastyController.text = draft.dynasty;
      _prefaceController.text = draft.preface;
      _contentController.text = draft.content;
      _remarkController.text = draft.remark;
      _translationController.text = draft.translation;
      _annotationController.text = draft.annotation;
      _learningNoteController.text = draft.learningNote;
      _appreciationController.text = draft.appreciation;
      _prosodyMetadata = _prosodyFromImportedDraft(draft);
      _prosodyOverridesJson = draft.prosodyOverridesJson;
      _prosodyVerifiedAt = draft.prosodyVerifiedAt;
      _prosodyVerifiedBy = draft.prosodyVerifiedBy;
      _prosodyDisplayTouched = false;
      _prosodyDetailsTouched = false;
      _suppressProsodySourceListener = false;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已导入到当前表单')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? '编辑诗词' : '添加原创诗词',
          style: const TextStyle(
            fontFamily: kFeiHuaSongTiFontFamily,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '导入诗词',
            onPressed: _saving ? null : _importPoemDraft,
            icon: const Icon(Icons.upload_file_outlined),
          ),
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
                  labelText: '序',
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
                  hintText: '一句一行，上下阙或自然段用空行分隔',
                  alignLabelWithHint: true,
                ),
                minLines: 8,
                maxLines: 16,
                keyboardType: TextInputType.multiline,
                validator: _required('请输入诗词内容'),
              ),
              const SizedBox(height: 12),
              _ProsodyEditorSection(
                metadata: _prosodyMetadata,
                onRefresh: _refreshProsodyInference,
                onManualCalibration: _openProsodyCalibrationDialog,
                onFormChanged: (form) {
                  setState(() {
                    _prosodyDetailsTouched = true;
                    final currentRhymeBook = _prosodyMetadata.rhymeBook.trim();
                    final shouldUseDefaultRhymeBook =
                        currentRhymeBook.isEmpty ||
                            currentRhymeBook == Poem.rhymeBookCiLin;
                    _prosodyMetadata = _prosodyMetadata.copyWith(
                      enabled: true,
                      system: Poem.prosodySystemRegulatedVerse,
                      form: form,
                      rhymeBook: shouldUseDefaultRhymeBook
                          ? _defaultRegulatedRhymeBook()
                          : currentRhymeBook,
                      note: '已手动设为$form，可在此页继续调整韵书。',
                    );
                  });
                },
                onEnabledChanged: (enabled) {
                  setState(() {
                    _prosodyDisplayTouched = true;
                    _prosodyMetadata = _prosodyMetadata.copyWith(
                      enabled: enabled && _prosodyMetadata.canEnable,
                    );
                  });
                },
                onRhymeBookChanged: (rhymeBook) {
                  setState(() {
                    _prosodyDetailsTouched = true;
                    _prosodyMetadata = _prosodyMetadata.copyWith(
                      rhymeBook: rhymeBook,
                    );
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _annotationController,
                decoration: const InputDecoration(
                  labelText: '注释',
                  hintText: '标题注释用 [0]，正文注释用 [行号]，一条注释一行',
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

  ProsodyMetadata _inferProsodyFromForm() {
    return inferProsodyMetadata(
      title: _titleController.text,
      dynasty: _dynastyController.text,
      content: _contentController.text,
      remark: _remarkController.text,
    );
  }

  ProsodyMetadata _prosodyFromImportedDraft(ImportedPoemDraft draft) {
    final inferred = _inferProsodyFromForm();
    if (!draft.hasProsodyMetadata) {
      return inferred;
    }

    final importedSystem = draft.prosodySystem.trim().isEmpty
        ? inferred.system
        : draft.prosodySystem.trim();
    final hasExplicitProsodyMetadata = draft.prosodySystem.trim().isNotEmpty ||
        draft.prosodyForm.trim().isNotEmpty ||
        draft.prosodyRhymeBook.trim().isNotEmpty ||
        draft.prosodyOverridesJson.trim().isNotEmpty ||
        draft.prosodyVerifiedAt != null ||
        draft.prosodyVerifiedBy.trim().isNotEmpty;
    final supported = draft.prosodySupported ??
        (hasExplicitProsodyMetadata &&
                importedSystem != Poem.prosodySystemUnknown &&
                importedSystem != Poem.prosodySystemUnsupported
            ? true
            : inferred.supported);
    return inferred.copyWith(
      supported: supported,
      enabled: supported &&
          (draft.prosodyEnabled ??
              (hasExplicitProsodyMetadata ? true : inferred.enabled)),
      system: importedSystem,
      form: draft.prosodyForm.trim().isEmpty
          ? inferred.form
          : draft.prosodyForm.trim(),
      rhymeBook: draft.prosodyRhymeBook.trim().isEmpty
          ? inferred.rhymeBook
          : draft.prosodyRhymeBook.trim(),
      note: draft.prosodyNote.trim().isEmpty
          ? inferred.note
          : draft.prosodyNote.trim(),
    );
  }

  void _refreshProsodyInference() {
    setState(() {
      _prosodyMetadata = _inferProsodyFromForm();
      _prosodyDisplayTouched = false;
      _prosodyDetailsTouched = false;
    });
  }

  void _handleProsodySourceChanged() {
    if (!mounted || _suppressProsodySourceListener) {
      return;
    }
    final inferred = _inferProsodyFromForm();
    final enabled = inferred.supported
        ? (_prosodyDisplayTouched ? _prosodyMetadata.enabled : inferred.enabled)
        : false;
    final keepDetails = _prosodyDetailsTouched &&
        inferred.supported &&
        _prosodyMetadata.system == inferred.system;
    setState(() {
      _prosodyMetadata = inferred.copyWith(
        enabled: enabled,
        form: keepDetails && _prosodyMetadata.form.trim().isNotEmpty
            ? _prosodyMetadata.form
            : inferred.form,
        rhymeBook: keepDetails && _prosodyMetadata.rhymeBook.trim().isNotEmpty
            ? _prosodyMetadata.rhymeBook
            : inferred.rhymeBook,
      );
    });
  }

  ProsodyMetadata _prosodyForSave() {
    final inferred = _inferProsodyFromForm();
    final useInferredDefault =
        !_isEditing && _prosodyMetadata.system == Poem.prosodySystemUnknown;
    final base = useInferredDefault ? inferred : _prosodyMetadata;
    final enabledPreference =
        useInferredDefault ? inferred.enabled : base.enabled;
    final supported = base.supported;
    final enabled = supported && enabledPreference;
    final rhymeBook = base.rhymeBook.trim().isEmpty
        ? inferred.rhymeBook
        : base.rhymeBook.trim();
    final form = base.form.trim().isEmpty ? inferred.form : base.form.trim();
    final baseNote = base.note.trim();
    final note = baseNote.isEmpty ||
            (inferred.system == Poem.prosodySystemCi &&
                !isStaleUnsupportedCiProsodyNote(inferred.note) &&
                isStaleUnsupportedCiProsodyNote(baseNote))
        ? inferred.note
        : baseNote;
    return base.copyWith(
      supported: supported,
      enabled: enabled,
      form: form,
      rhymeBook: rhymeBook,
      note: note,
    );
  }

  Future<void> _openProsodyCalibrationDialog() async {
    final prosody = _prosodyForSave();
    if (!prosody.supported || !prosody.enabled || !prosody.canEnable) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('当前诗词尚未开启格律显示，不能校准平仄。')),
        );
      return;
    }
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('请先填写正文内容。')),
        );
      return;
    }

    final now = DateTime.now();
    final draftPoem = Poem(
      id: widget.poem?.id,
      identity: widget.poem?.identity ?? 'draft',
      collectionId: widget.collectionId,
      title: _titleController.text.trim().isEmpty
          ? '未命名'
          : _titleController.text.trim(),
      author: _authorController.text.trim(),
      dynasty: _dynastyController.text.trim(),
      preface: _prefaceController.text.trim(),
      content: _contentController.text.trim(),
      remark: _remarkController.text.trim(),
      translation: _translationController.text.trim(),
      annotation: _annotationController.text.trim(),
      learningNote: _learningNoteController.text.trim(),
      appreciation: _appreciationController.text.trim(),
      prosodySupported: prosody.supported,
      prosodyEnabled: prosody.enabled,
      prosodySystem: prosody.system,
      prosodyForm: prosody.form,
      prosodyRhymeBook: prosody.rhymeBook,
      prosodyNote: prosody.note,
      prosodyOverridesJson: _prosodyOverridesJson,
      prosodyVerifiedAt: _prosodyVerifiedAt,
      prosodyVerifiedBy: _prosodyVerifiedBy,
      createdAt: widget.poem?.createdAt ?? now,
      updatedAt: now,
    );

    final nextOverridesJson = await showDialog<String>(
      context: context,
      builder: (context) => ProsodyCalibrationDialog(poem: draftPoem),
    );
    if (nextOverridesJson == null || !mounted) {
      return;
    }

    setState(() {
      _prosodyMetadata = prosody;
      _prosodyOverridesJson = nextOverridesJson;
      _prosodyVerifiedAt = DateTime.now();
      _prosodyVerifiedBy = 'user';
      _prosodyDisplayTouched = true;
      _prosodyDetailsTouched = true;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已写入当前表单，保存后生效。')));
  }

  bool _shouldClearProsodyVerification(Poem existing) {
    return existing.title.trim() != _titleController.text.trim() ||
        existing.dynasty.trim() != _dynastyController.text.trim() ||
        existing.content.trim() != _contentController.text.trim() ||
        existing.remark.trim() != _remarkController.text.trim();
  }

  String _defaultRegulatedRhymeBook() {
    final dynasty = _dynastyController.text.trim();
    final isModern = dynasty.contains('当代') ||
        dynasty.contains('现代') ||
        dynasty.contains('近现代') ||
        dynasty.contains('现当代');
    return isModern ? Poem.rhymeBookXinYun : Poem.rhymeBookPingShui;
  }
}

class _ProsodyEditorSection extends StatelessWidget {
  const _ProsodyEditorSection({
    required this.metadata,
    required this.onRefresh,
    required this.onManualCalibration,
    required this.onFormChanged,
    required this.onEnabledChanged,
    required this.onRhymeBookChanged,
  });

  final ProsodyMetadata metadata;
  final VoidCallback onRefresh;
  final VoidCallback onManualCalibration;
  final ValueChanged<String> onFormChanged;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<String> onRhymeBookChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = metadata.enabled && metadata.canEnable;
    const regulatedFormValues = <String>['五绝', '七绝', '五律', '七律'];
    final currentForm = metadata.form.trim();
    final formOptions = <String>[
      if (regulatedFormValues.contains(currentForm)) currentForm,
      ...regulatedFormValues,
    ].toSet().toList(growable: false);
    final rhymeBooks = <String>[
      if (metadata.rhymeBook.trim().isNotEmpty) metadata.rhymeBook,
      Poem.rhymeBookPingShui,
      Poem.rhymeBookCiLin,
      Poem.rhymeBookXinYun,
    ].toSet().toList(growable: false);
    final showRegulatedFormField =
        metadata.system != Poem.prosodySystemCi &&
            metadata.system != Poem.prosodySystemQu;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8DD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE6C66A)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('格律检查', style: theme.textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新识别'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              [
                '系统：${prosodySystemLabel(metadata.system)}',
                if (metadata.form.trim().isNotEmpty) '体式：${metadata.form}',
              ].join('　'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              metadata.supported ? '当前结构支持显示格律。' : '当前结构暂不支持显示格律。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6A5219),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: enabled,
              onChanged: metadata.canEnable ? onEnabledChanged : null,
              title: const Text('显示格律面板'),
              subtitle: Text(
                metadata.canEnable ? '关闭后学习和训练答案页不显示格律。' : '请补充朝代、正文结构或词牌信息后重新识别。',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: enabled ? onManualCalibration : null,
                icon: const Icon(Icons.tune_outlined),
                label: const Text('人工校准'),
              ),
            ),
            const SizedBox(height: 14),
            if (showRegulatedFormField) ...[
              DropdownButtonFormField<String>(
                value: regulatedFormValues.contains(currentForm)
                    ? currentForm
                    : null,
                decoration: const InputDecoration(labelText: '近体诗体式'),
                items: [
                  for (final form in formOptions)
                    DropdownMenuItem(value: form, child: Text(form)),
                ],
                onChanged: metadata.supported
                    ? (value) {
                        if (value != null) {
                          onFormChanged(value);
                        }
                      }
                    : null,
              ),
              const SizedBox(height: 8),
            ] else if (currentForm.isNotEmpty) ...[
              InputDecorator(
                decoration: const InputDecoration(labelText: '词牌 / 曲牌'),
                child: Text(currentForm),
              ),
              const SizedBox(height: 8),
            ],
            DropdownButtonFormField<String>(
              value: rhymeBooks.contains(metadata.rhymeBook)
                  ? metadata.rhymeBook
                  : null,
              decoration: const InputDecoration(labelText: '韵书'),
              items: [
                for (final book in rhymeBooks)
                  DropdownMenuItem(value: book, child: Text(book)),
              ],
              onChanged: metadata.canEnable && enabled
                  ? (value) {
                      if (value != null) {
                        onRhymeBookChanged(value);
                      }
                    }
                  : null,
            ),
            if (metadata.note.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                metadata.note,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SinglePoemImportDialog extends StatefulWidget {
  const _SinglePoemImportDialog();

  @override
  State<_SinglePoemImportDialog> createState() => _SinglePoemImportDialogState();
}

class _SinglePoemImportDialogState extends State<_SinglePoemImportDialog> {
  final _textController = TextEditingController();
  String? _errorText;
  bool _pickingFile = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final poem = parseSinglePoemImport(_textController.text);
      Navigator.pop(context, poem);
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
      title: const Text('导入诗词'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                  hintText: '{"title":"静夜思","author":"李白","content":"..."}',
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
