import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/api_config.dart';
import '../services/app_backup_service.dart';
import '../theme/app_typography.dart';
import '../widgets/huiyun_visuals.dart';
import 'api_config_editor_screen.dart';

class ApiSettingsScreen extends StatefulWidget {
  const ApiSettingsScreen({super.key});

  @override
  State<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends State<ApiSettingsScreen> {
  static const _backupService = AppBackupService();

  final _searchController = TextEditingController();
  late Future<List<ApiConfig>> _configsFuture;
  bool _showSearch = false;
  bool _backupBusy = false;

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadConfigs() {
    _configsFuture = AppDatabase.instance.getApiConfigs(
      query: _searchController.text,
    );
  }

  Future<void> _refreshConfigs() async {
    setState(_loadConfigs);
    await _configsFuture;
  }

  Future<void> _openEditor({ApiConfig? config}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ApiConfigEditorScreen(config: config),
      ),
    );

    if (saved == true && mounted) {
      await _refreshConfigs();
    }
  }

  Future<void> _setActive(ApiConfig config) async {
    final id = config.id;
    if (id == null || config.isActive) {
      return;
    }

    await AppDatabase.instance.setActiveApiConfig(id);
    if (mounted) {
      await _refreshConfigs();
    }
  }

  Future<void> _deleteConfig(ApiConfig config) async {
    final id = config.id;
    if (id == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除 API 配置'),
          content: Text('确定删除“${config.name}”吗？'),
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

    await AppDatabase.instance.deleteApiConfig(id);
    if (mounted) {
      await _refreshConfigs();
    }
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchController.clear();
      }
      _loadConfigs();
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

  Future<void> _showBackupActions() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('生成备份包'),
                  subtitle: const Text('导出诗词库、设置、笔记、格律校准与学习训练进度，备份包会包含 API Key'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportBackup();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.restore_outlined),
                  title: const Text('从备份包导入'),
                  subtitle: const Text('导入会覆盖当前 App 内的全部数据'),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmAndImportBackup();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportBackup() async {
    if (_backupBusy) {
      return;
    }
    setState(() {
      _backupBusy = true;
    });
    try {
      final result = await _backupService.exportBackup();
      if (!mounted) {
        return;
      }
      if (result == null) {
        _showSnackBar('已取消备份');
        return;
      }
      _showSnackBar(
        '备份已生成：${result.collectionCount} 个诗词库，${result.poemCount} 首诗词',
      );
    } catch (error) {
      _showSnackBar('生成备份失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _backupBusy = false;
        });
      }
    }
  }

  Future<void> _confirmAndImportBackup() async {
    if (_backupBusy) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('导入备份包'),
          content: const Text(
            '导入会覆盖当前诗词库、设置、API 配置、学习笔记、格律校准、对话记录和训练进度。当前数据不会自动保留，确定继续吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定导入'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _backupBusy = true;
    });
    try {
      final result = await _backupService.pickAndImportBackup();
      if (!mounted) {
        return;
      }
      if (result == null) {
        _showSnackBar('已取消导入');
        return;
      }
      await _refreshConfigs();
      _showSnackBar(
        '导入完成：${result.collectionCount} 个诗词库，${result.poemCount} 首诗词',
      );
    } on BackupImportException catch (error) {
      _showSnackBar(error.message);
    } catch (error) {
      _showSnackBar('导入失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _backupBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '设置',
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
        actions: [
          IconButton(
            tooltip: _showSearch ? '关闭搜索' : '搜索',
            onPressed: _toggleSearch,
            icon: Icon(_showSearch ? Icons.close : Icons.search),
          ),
          IconButton(
            tooltip: '新增 API 配置',
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: '搜索名称、URL 或模型',
                ),
                onChanged: (_) => _refreshConfigs(),
              ),
            ),
          Expanded(
            child: FutureBuilder<List<ApiConfig>>(
              future: _configsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return _ApiMessageView(
                    icon: Icons.error_outline,
                    title: 'API 配置读取失败',
                    message: snapshot.error.toString(),
                  );
                }

                final configs = snapshot.data ?? const <ApiConfig>[];
                if (configs.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refreshConfigs,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 150),
                        _ApiMessageView(
                          icon: Icons.add_link_outlined,
                          title: '还没有 API 配置',
                          message: '点击右上角按钮添加第一个 OpenAI 兼容配置。',
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refreshConfigs,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 10, bottom: 20),
                    itemCount: configs.length,
                    itemBuilder: (context, index) {
                      final config = configs[index];
                      return HuiyunPageEntrance(
                        index: index,
                        child: _ApiConfigCard(
                          config: config,
                          onTap: () => _openEditor(config: config),
                          onSelect: () => _setActive(config),
                          onDelete: () => _deleteConfig(config),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _backupBusy ? null : _showBackupActions,
                  icon: _backupBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.inventory_2_outlined),
                  label: Text(_backupBusy ? '处理中' : '备份与导入'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiConfigCard extends StatelessWidget {
  const _ApiConfigCard({
    required this.config,
    required this.onTap,
    required this.onSelect,
    required this.onDelete,
  });

  final ApiConfig config;
  final VoidCallback onTap;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return HuiyunPaperCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
      child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            config.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (config.isActive)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF4C7),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              child: Text(
                                '当前',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _ApiInfoLine(
                      icon: Icons.vpn_key_outlined,
                      text: config.maskedApiKey,
                    ),
                    _ApiInfoLine(
                      icon: Icons.link,
                      text: config.baseUrl,
                    ),
                    _ApiInfoLine(
                      icon: Icons.chat_bubble_outline,
                      text: config.chatModel,
                    ),
                    if (config.embeddingModel.isNotEmpty)
                      _ApiInfoLine(
                        icon: Icons.psychology_outlined,
                        text: config.embeddingModel,
                      ),
                    _ApiInfoLine(
                      icon: Icons.public,
                      text: config.isSearchEnabled
                          ? '${config.searchProvider} 搜索已启用'
                          : '未启用联网搜索',
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    tooltip: '设为当前配置',
                    onPressed: onSelect,
                    icon: Icon(
                      config.isActive
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                  ),
                  PopupMenuButton<_ApiConfigAction>(
                    onSelected: (action) {
                      switch (action) {
                        case _ApiConfigAction.delete:
                          onDelete();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _ApiConfigAction.delete,
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('删除'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
    );
  }
}

enum _ApiConfigAction { delete }

class _ApiInfoLine extends StatelessWidget {
  const _ApiInfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 19, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text.isEmpty ? '未填写' : text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiMessageView extends StatelessWidget {
  const _ApiMessageView({
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
