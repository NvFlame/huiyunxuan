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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('绘云轩')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            _JinshiPointCard(points: _jinshiPoints),
            _HomeSection(
              title: '学习模式',
              icon: Icons.menu_book_outlined,
              destination: const LearningModeScreen(),
            ),
            _HomeSection(
              title: '训练模式',
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
              title: 'API管理',
              icon: Icons.settings_outlined,
              destination: const ApiSettingsScreen(),
            ),
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
  const _JinshiPointCard({required this.points});

  final int? points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
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
                  Text('默写点数', style: theme.textTheme.titleMedium),
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
          ],
        ),
      ),
    );
  }
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
