import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/api_config.dart';
import '../services/openai_api_service.dart';

class ApiConfigEditorScreen extends StatefulWidget {
  const ApiConfigEditorScreen({super.key, this.config});

  final ApiConfig? config;

  @override
  State<ApiConfigEditorScreen> createState() => _ApiConfigEditorScreenState();
}

class _ApiConfigEditorScreenState extends State<ApiConfigEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _chatModelController;
  late final TextEditingController _embeddingModelController;
  bool _saving = false;
  bool _showApiKey = false;
  bool _loadingModels = false;
  bool _testingApi = false;
  late bool _isActive;

  bool get _isEditing => widget.config != null;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    _nameController = TextEditingController(text: config?.name);
    _apiKeyController = TextEditingController(text: config?.apiKey);
    _baseUrlController = TextEditingController(
      text: config?.baseUrl ?? 'https://api.openai.com/v1',
    );
    _chatModelController = TextEditingController(text: config?.chatModel);
    _embeddingModelController = TextEditingController(
      text: config?.embeddingModel,
    );
    _isActive = config?.isActive ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _chatModelController.dispose();
    _embeddingModelController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    if (_saving || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _saving = true;
    });

    final database = AppDatabase.instance;
    final existing = widget.config;

    if (existing == null) {
      await database.createApiConfig(
        name: _nameController.text,
        apiKey: _apiKeyController.text,
        baseUrl: _baseUrlController.text,
        chatModel: _chatModelController.text,
        embeddingModel: _embeddingModelController.text,
        isActive: _isActive,
      );
    } else {
      await database.updateApiConfig(
        existing.copyWith(
          name: _nameController.text,
          apiKey: _apiKeyController.text,
          baseUrl: _baseUrlController.text,
          chatModel: _chatModelController.text,
          embeddingModel: _embeddingModelController.text,
          isActive: _isActive,
        ),
      );
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _fetchModels() async {
    if (_loadingModels || !_validateConnectionFields()) {
      return;
    }

    setState(() {
      _loadingModels = true;
    });

    try {
      final models = await const OpenAiApiService().fetchModels(_draftConfig());
      if (!mounted) {
        return;
      }
      await _showModelListDialog(models);
    } on ApiRequestException catch (error) {
      if (mounted) {
        await _showResultDialog(
          title: '获取模型列表失败',
          message: error.toString(),
          details: error.details,
        );
      }
    } catch (error) {
      if (mounted) {
        await _showResultDialog(title: '获取模型列表失败', message: error.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingModels = false;
        });
      }
    }
  }

  Future<void> _testApi() async {
    if (_testingApi || !_validateConnectionFields(requireChatModel: true)) {
      return;
    }

    setState(() {
      _testingApi = true;
    });

    try {
      final result = await const OpenAiApiService().testChat(_draftConfig());
      if (!mounted) {
        return;
      }
      await _showResultDialog(
        title: 'API 测试成功',
        message: '模型：${result.model}\n\n回复：${result.message}',
      );
    } on ApiRequestException catch (error) {
      if (mounted) {
        await _showResultDialog(
          title: 'API 测试失败',
          message: error.toString(),
          details: error.details,
        );
      }
    } catch (error) {
      if (mounted) {
        await _showResultDialog(title: 'API 测试失败', message: error.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _testingApi = false;
        });
      }
    }
  }

  bool _validateConnectionFields({bool requireChatModel = false}) {
    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final chatModel = _chatModelController.text.trim();

    if (apiKey.isEmpty) {
      _showSnackBar('请先填写 API 密钥');
      return false;
    }

    final urlError = _urlValidator(baseUrl);
    if (urlError != null) {
      _showSnackBar(urlError);
      return false;
    }

    if (requireChatModel && chatModel.isEmpty) {
      _showSnackBar('请先填写对话模型');
      return false;
    }

    return true;
  }

  ApiConfig _draftConfig() {
    final now = DateTime.now();
    return ApiConfig(
      id: widget.config?.id,
      name: _nameController.text.trim().isEmpty
          ? '未保存配置'
          : _nameController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      chatModel: _chatModelController.text.trim(),
      embeddingModel: _embeddingModelController.text.trim(),
      isActive: _isActive,
      createdAt: widget.config?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> _showModelListDialog(List<String> models) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('模型列表（${models.length}）'),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: ListView.builder(
              itemCount: models.length,
              itemBuilder: (context, index) {
                final model = models[index];
                return ListTile(
                  dense: true,
                  title: Text(model),
                  onTap: () {
                    _chatModelController.text = model;
                    Navigator.pop(context);
                    _showSnackBar('已填入对话模型：$model');
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showResultDialog({
    required String title,
    required String message,
    String details = '',
  }) async {
    final fullMessage = details.trim().isEmpty
        ? message
        : '$message\n\n原始响应：\n$details';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(child: SelectableText(fullMessage)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑 API 配置' : '新增 API 配置'),
        actions: [
          IconButton(
            tooltip: '保存',
            onPressed: _saving ? null : _saveConfig,
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
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例如：OpenAI、Talk、备用接口',
                ),
                textInputAction: TextInputAction.next,
                validator: _required('请输入配置名称'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: ApiConfig.openAiSpec,
                decoration: const InputDecoration(labelText: 'API规范'),
                items: const [
                  DropdownMenuItem(
                    value: ApiConfig.openAiSpec,
                    child: Text(ApiConfig.openAiSpec),
                  ),
                ],
                onChanged: (_) {},
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _apiKeyController,
                obscureText: !_showApiKey,
                decoration: InputDecoration(
                  labelText: 'API密钥',
                  hintText: 'sk-...',
                  suffixIcon: IconButton(
                    tooltip: _showApiKey ? '隐藏密钥' : '显示密钥',
                    onPressed: () {
                      setState(() {
                        _showApiKey = !_showApiKey;
                      });
                    },
                    icon: Icon(
                      _showApiKey
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                textInputAction: TextInputAction.next,
                validator: _required('请输入 API 密钥'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  labelText: 'API基础URL',
                  hintText: 'https://api.openai.com/v1',
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                validator: _urlValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _chatModelController,
                decoration: const InputDecoration(
                  labelText: '对话模型',
                  hintText: '例如：gpt-4.1-mini',
                ),
                textInputAction: TextInputAction.next,
                validator: _required('请输入对话模型'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _embeddingModelController,
                decoration: const InputDecoration(
                  labelText: '嵌入模型',
                  hintText: '例如：text-embedding-3-small',
                ),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('设为当前默认配置'),
                value: _isActive,
                onChanged: (value) {
                  setState(() {
                    _isActive = value;
                  });
                },
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving ? null : _saveConfig,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? '保存中' : '保存'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loadingModels ? null : _fetchModels,
                icon: _loadingModels
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.format_list_bulleted),
                label: Text(_loadingModels ? '获取中' : '获取模型列表'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _testingApi ? null : _testApi,
                icon: _testingApi
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.api_outlined),
                label: Text(_testingApi ? '测试中' : '测试API'),
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

  String? _urlValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '请输入 API 基础 URL';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '请输入有效的 URL';
    }
    return null;
  }
}
