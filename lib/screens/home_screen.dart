import 'package:flutter/material.dart';

import 'api_settings_screen.dart';
import 'collection_list_screen.dart';
import 'learning_mode_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('绘云轩')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: const [
            _HomeSection(
              title: '学习模式',
              icon: Icons.menu_book_outlined,
              destination: LearningModeScreen(),
            ),
            _HomeSection(
              title: '训练模式',
              icon: Icons.edit_note_outlined,
              destination: PlaceholderFeatureScreen(title: '训练模式'),
            ),
            _HomeSection(
              title: '诗词库管理',
              icon: Icons.folder_outlined,
              destination: CollectionListScreen(),
            ),
            _HomeSection(
              title: 'API管理',
              icon: Icons.settings_outlined,
              destination: ApiSettingsScreen(),
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
  });

  final String title;
  final IconData icon;
  final Widget destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (context) => destination),
          );
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
