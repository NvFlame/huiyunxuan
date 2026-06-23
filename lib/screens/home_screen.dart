import 'package:flutter/material.dart';

import '../data/app_database.dart';
import 'api_settings_screen.dart';
import 'collection_list_screen.dart';
import 'learning_mode_screen.dart';
import 'training_mode_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int? _jinshiPoints;

  @override
  void initState() {
    super.initState();
    _loadJinshiPoints();
  }

  Future<void> _loadJinshiPoints() async {
    final points = await AppDatabase.instance.getJinshiPointCount();
    if (!mounted) {
      return;
    }
    setState(() {
      _jinshiPoints = points;
    });
  }

  Future<void> _openJinshiHistory() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (context) => const JinshiHistoryScreen()),
    );
    _loadJinshiPoints();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('绘云轩')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            _JinshiPointCard(
              points: _jinshiPoints,
              onTap: _openJinshiHistory,
            ),
            _HomeSection(
              title: '学文',
              icon: Icons.menu_book_outlined,
              destination: const LearningModeScreen(),
            ),
            _HomeSection(
              title: '展才',
              icon: Icons.edit_note_outlined,
              destination: const TrainingModeScreen(),
              onReturn: () {
                _loadJinshiPoints();
              },
            ),
            _HomeSection(
              title: '诗词库管理',
              icon: Icons.folder_outlined,
              destination: const CollectionListScreen(),
              onReturn: () {
                _loadJinshiPoints();
              },
            ),
            _HomeSection(
              title: '设置',
              icon: Icons.settings_outlined,
              destination: const ApiSettingsScreen(),
              onReturn: () {
                _loadJinshiPoints();
              },
            ),
            const SizedBox(height: 18),
            Text(
              '绘云诗人作品\nBy Cloudweaver Poet',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({
    required this.title,
    required this.icon,
    required this.destination,
    this.onReturn,
  });

  final String title;
  final IconData icon;
  final Widget destination;
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (context) => destination),
          );
          onReturn?.call();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Row(
            children: [
              Icon(icon, size: 30, color: theme.colorScheme.primary),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _JinshiPointCard extends StatelessWidget {
  const _JinshiPointCard({required this.points, required this.onTap});

  final int? points;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
          children: [
            Icon(
              Icons.workspace_premium_outlined,
              size: 30,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('默诵值', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(
                    '首次通过进士模式的诗词数量',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              points == null ? '...' : points.toString(),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF4F3B12),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
      ),
    );
  }
}

class JinshiHistoryScreen extends StatefulWidget {
  const JinshiHistoryScreen({super.key});

  @override
  State<JinshiHistoryScreen> createState() => _JinshiHistoryScreenState();
}

class _JinshiHistoryScreenState extends State<JinshiHistoryScreen> {
  late final Future<List<JinshiAchievementEntry>> _future =
      AppDatabase.instance.getJinshiAchievementHistory();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('进士记录')),
      body: SafeArea(
        child: FutureBuilder<List<JinshiAchievementEntry>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '读取进士记录失败：${snapshot.error}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              );
            }

            final entries = snapshot.data ?? const <JinshiAchievementEntry>[];
            if (entries.isEmpty) {
              return Center(
                child: Text(
                  '还没有通过进士模式的诗词。',
                  style: theme.textTheme.titleMedium,
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final poem = entry.poem;
                final authorLine = [
                  poem.dynasty,
                  poem.author,
                ].where((part) => part.trim().isNotEmpty).join(' · ');
                final remark = poem.remark.trim();

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(
                      poem.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        [
                          if (authorLine.isNotEmpty) authorLine,
                          if (remark.isNotEmpty) '备注：$remark',
                          '达成：${_formatJinshiTime(entry.firstJinshiAt)}',
                        ].join('\n'),
                      ),
                    ),
                    isThreeLine: remark.isNotEmpty || authorLine.isNotEmpty,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

String _formatJinshiTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}

class PlaceholderFeatureScreen extends StatelessWidget {
  const PlaceholderFeatureScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text('暂未开发', style: theme.textTheme.titleMedium),
      ),
    );
  }
}
