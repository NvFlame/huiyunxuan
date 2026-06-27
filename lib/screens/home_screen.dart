import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/poem.dart';
import '../theme/app_typography.dart';
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
  Poem? _homePoem;

  @override
  void initState() {
    super.initState();
    _loadJinshiPoints();
    _loadHomePoem();
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

  Future<void> _loadHomePoem() async {
    final poem = await AppDatabase.instance.getRandomHomeDisplayPoem();
    if (!mounted) {
      return;
    }
    setState(() {
      _homePoem = poem;
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
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFF8E3),
              Color(0xFFFFFAEA),
              Color(0xFFFDF3DF),
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned(
              right: -112,
              bottom: 96,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.105,
                  child: Image(
                    image: AssetImage('assets/branding/cloud_mark.png'),
                    width: 390,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            CustomPaint(
              painter: const _HomeBackgroundPainter(),
              child: SafeArea(
                child: Column(
                  children: [
                    const _HomeTitleMark(),
                    Expanded(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 680),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, (1 - value) * 12),
                              child: child,
                            ),
                          );
                        },
                        child: _HomeMainStage(
                          poem: _homePoem,
                          points: _jinshiPoints,
                          onJinshiTap: _openJinshiHistory,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      child: Column(
                        children: [
                          Text(
                            '绘云诗人作品\nBy Cloudweaver Poet',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF8A7A4A),
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            height: 1,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFFC9A85D).withOpacity(0),
                                  const Color(0xFFC9A85D).withOpacity(0.55),
                                  const Color(0xFFC9A85D).withOpacity(0),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 7),
                          _HomeIconDock(
                            onLearningTap: () {
                              Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const LearningModeScreen(),
                                ),
                              );
                            },
                            onTrainingTap: () async {
                              await Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const TrainingModeScreen(),
                                ),
                              );
                              _loadJinshiPoints();
                            },
                            onLibraryTap: () async {
                              await Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const CollectionListScreen(),
                                ),
                              );
                              _loadJinshiPoints();
                            },
                            onSettingsTap: () async {
                              await Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const ApiSettingsScreen(),
                                ),
                              );
                              _loadJinshiPoints();
                            },
                          ),
                          const SizedBox(height: 3),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeTitleMark extends StatelessWidget {
  const _HomeTitleMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      width: double.infinity,
      child: CustomPaint(
        painter: const _HomeTitleMistPainter(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Opacity(
              opacity: 0.9,
              child: Image.asset(
                'assets/branding/home_title.png',
                height: 40,
                fit: BoxFit.contain,
                color: const Color(0xFF5B431B),
                colorBlendMode: BlendMode.srcIn,
                semanticLabel: '绘云轩',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeTitleMistPainter extends CustomPainter {
  const _HomeTitleMistPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.58);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFD8B85A).withOpacity(0.13),
          const Color(0xFFFFF8E3).withOpacity(0),
        ],
      ).createShader(
        Rect.fromCircle(center: center, radius: math.min(size.width, 380) / 2),
      );
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: math.min(size.width * 0.7, 360),
        height: 66,
      ),
      glow,
    );
  }

  @override
  bool shouldRepaint(covariant _HomeTitleMistPainter oldDelegate) => false;
}

class _HomeBackgroundPainter extends CustomPainter {
  const _HomeBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paperPaint = Paint()..color = const Color(0xFFFFFFFF).withOpacity(0.2);
    canvas.drawCircle(Offset(size.width * 0.12, 86), 1.4, paperPaint);
    canvas.drawCircle(Offset(size.width * 0.64, 160), 1.0, paperPaint);
    canvas.drawCircle(Offset(size.width * 0.86, 330), 1.2, paperPaint);

    final linePaint = Paint()
      ..color = const Color(0xFFE8DDAE).withOpacity(0.22)
      ..strokeWidth = 0.8;
    for (var x = 24.0; x < size.width; x += 36) {
      canvas.drawLine(Offset(x, 0), Offset(x + 8, size.height), linePaint);
    }

    final washPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFB8B097).withOpacity(0.1),
          const Color(0xFFB8B097).withOpacity(0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.18, size.height * 0.18),
          radius: size.width * 0.42,
        ),
      );
    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.18),
      size.width * 0.42,
      washPaint,
    );

    final rightMist = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF99977E).withOpacity(0.075),
          const Color(0xFF99977E).withOpacity(0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.92, size.height * 0.32),
          radius: size.width * 0.5,
        ),
      );
    canvas.drawCircle(
      Offset(size.width * 0.92, size.height * 0.32),
      size.width * 0.5,
      rightMist,
    );

    final warmInk = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFD8A935).withOpacity(0.09),
          const Color(0xFFD8A935).withOpacity(0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.18, size.height * 0.72),
          radius: size.width * 0.46,
        ),
      );
    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.72),
      size.width * 0.46,
      warmInk,
    );

    final moonPaint = Paint()
      ..color = const Color(0xFFFFF8DC).withOpacity(0.68)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.14),
      size.width * 0.16,
      moonPaint,
    );

    final sealPaint = Paint()
      ..color = const Color(0xFF9A5B3D).withOpacity(0.035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final sealRect = Rect.fromCenter(
      center: Offset(size.width * 0.83, size.height * 0.64),
      width: 46,
      height: 46,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(sealRect, const Radius.circular(4)),
      sealPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _HomeBackgroundPainter oldDelegate) => false;
}

class _HomeMainStage extends StatelessWidget {
  const _HomeMainStage({
    required this.poem,
    required this.points,
    required this.onJinshiTap,
  });

  final Poem? poem;
  final int? points;
  final VoidCallback onJinshiTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stageWidth = math.min(constraints.maxWidth - 32, 520.0);
        final stageHeight = constraints.maxHeight;
        final compact = stageHeight < 560;
        final diamondSize = compact ? 94.0 : 108.0;
        final poemTop = compact ? 144.0 : 184.0;
        final poemBottom = compact ? 14.0 : 24.0;
        final titleWidth = compact ? 58.0 : 68.0;
        final poemGap = compact ? 16.0 : 22.0;
        final poemLeft = compact ? 32.0 : 42.0;
        final poemFrameWidth = stageWidth - titleWidth - poemGap - 18;

        return Center(
          child: SizedBox(
            width: stageWidth,
            height: stageHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 18,
                  top: compact ? 8 : 18,
                  child: _JinshiDiamond(
                    size: diamondSize,
                    points: points,
                    onTap: onJinshiTap,
                  ),
                ),
                Positioned(
                  left: poemLeft,
                  top: poemTop,
                  bottom: poemBottom,
                  width: poemFrameWidth,
                  child: _HomePoemPanel(poem: poem),
                ),
                Positioned(
                  left: compact ? 18 : 24,
                  bottom: poemBottom + (compact ? 48 : 74),
                  child: _HomePoemAuthor(author: poem?.author ?? ''),
                ),
                Positioned(
                  left: poemFrameWidth + poemGap,
                  top: compact ? 58 : 86,
                  bottom: poemBottom + 32,
                  width: titleWidth,
                  child: _HomePoemTitle(title: poem?.title ?? ''),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomePoemPanel extends StatelessWidget {
  const _HomePoemPanel({required this.poem});

  final Poem? poem;

  @override
  Widget build(BuildContext context) {
    final lines = poem == null
        ? const <String>[]
        : _homeDisplayLines(poem!.content);
    final displayLines = lines.length == 4 ? lines : const <String>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
      child: displayLines.isEmpty
          ? Center(
              child: Text(
                '诗文',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFF4F3B12).withOpacity(0.36),
                      fontFamily: kSanjiXingKaiFontFamily,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            )
          : _VerticalPoemText(lines: displayLines),
    );
  }
}

class _VerticalPoemText extends StatelessWidget {
  const _VerticalPoemText({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final lineLength = lines.first.runes.length;
        final fontSize = lineLength == 7 ? 29.0 : 34.0;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.start,
          textDirection: TextDirection.rtl,
          children: [
            for (final line in lines)
              _VerticalTextColumn(
                text: line,
                fontSize: fontSize,
                color: const Color(0xFF4F3B12).withOpacity(0.70),
              ),
          ],
        );
      },
    );
  }
}

class _HomePoemTitle extends StatelessWidget {
  const _HomePoemTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final cleanedTitle = _stripDisplayPunctuation(title);
    return Align(
      alignment: Alignment.topCenter,
      child: _VerticalTextColumn(
        text: cleanedTitle.isEmpty ? '诗题' : cleanedTitle,
        fontSize: 28,
        color: const Color(0xFF4F3B12).withOpacity(0.70),
        allowOverflow: true,
      ),
    );
  }
}

class _HomePoemAuthor extends StatelessWidget {
  const _HomePoemAuthor({required this.author});

  final String author;

  @override
  Widget build(BuildContext context) {
    final cleanedAuthor = _stripDisplayPunctuation(author);
    if (cleanedAuthor.isEmpty) {
      return const SizedBox.shrink();
    }
    return _VerticalTextColumn(
      text: cleanedAuthor,
      fontSize: 28,
      color: const Color(0xFF4F3B12).withOpacity(0.70),
    );
  }
}

class _VerticalTextColumn extends StatelessWidget {
  const _VerticalTextColumn({
    required this.text,
    required this.fontSize,
    required this.color,
    this.allowOverflow = false,
  });

  final String text;
  final double fontSize;
  final Color color;
  final bool allowOverflow;

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final rune in text.runes)
        Text(
          String.fromCharCode(rune),
          softWrap: false,
          style: TextStyle(
            color: color,
            fontFamily: kSanjiXingKaiFontFamily,
            fontWeight: FontWeight.w500,
            fontSize: fontSize,
            height: 1.08,
          ),
        ),
    ];
    if (allowOverflow) {
      return OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: 0,
        maxHeight: double.infinity,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _HomeIconDock extends StatelessWidget {
  const _HomeIconDock({
    required this.onLearningTap,
    required this.onTrainingTap,
    required this.onLibraryTap,
    required this.onSettingsTap,
  });

  final VoidCallback onLearningTap;
  final VoidCallback onTrainingTap;
  final VoidCallback onLibraryTap;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _HomeDockItem(
          label: '学文',
          assetPath: 'assets/home_icons/learning_scroll.png',
          onTap: onLearningTap,
        ),
        _HomeDockItem(
          label: '展才',
          assetPath: 'assets/home_icons/training_brush.png',
          assetSize: 44,
          onTap: onTrainingTap,
        ),
        _HomeDockItem(
          label: '书架',
          icon: Icons.folder_outlined,
          onTap: onLibraryTap,
        ),
        _HomeDockItem(
          label: '设置',
          icon: Icons.settings_outlined,
          onTap: onSettingsTap,
        ),
      ],
    );
  }
}

class _HomeDockItem extends StatefulWidget {
  const _HomeDockItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.assetPath,
    this.assetSize = 38,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final String? assetPath;
  final double assetSize;

  @override
  State<_HomeDockItem> createState() => _HomeDockItemState();
}

class _HomeDockItemState extends State<_HomeDockItem> {
  bool _showLabel = false;

  void _setLabelVisible(bool visible) {
    if (_showLabel == visible) {
      return;
    }
    setState(() {
      _showLabel = visible;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPressStart: (_) => _setLabelVisible(true),
      onLongPressEnd: (_) => _setLabelVisible(false),
      onLongPressCancel: () => _setLabelVisible(false),
      child: SizedBox(
        width: 68,
        height: 64,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            AnimatedOpacity(
              opacity: _showLabel ? 0.5 : 0,
              duration: const Duration(milliseconds: 120),
              child: Transform.translate(
                offset: const Offset(0, 24),
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF4F3B12),
                        fontFamily: kFeiHuaSongTiFontFamily,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        height: 1,
                      ),
                ),
              ),
            ),
            _HomeDockIcon(
              icon: widget.icon,
              assetPath: widget.assetPath,
              assetSize: widget.assetSize,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeDockIcon extends StatelessWidget {
  const _HomeDockIcon({
    required this.icon,
    required this.assetPath,
    required this.assetSize,
  });

  final IconData? icon;
  final String? assetPath;
  final double assetSize;

  @override
  Widget build(BuildContext context) {
    final imagePath = assetPath;
    if (imagePath != null) {
      return SizedBox(
        width: assetSize,
        height: assetSize,
        child: Image.asset(
          imagePath,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      );
    }
    return Icon(
      icon,
      color: const Color(0xFF5B431B),
      size: 34,
    );
  }
}

List<String> _homeDisplayLines(String content) {
  return content
      .split(RegExp(r'[\r\n]+'))
      .map(_stripDisplayPunctuation)
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

String _stripDisplayPunctuation(String value) {
  return value.replaceAll(
    RegExp(r'[\s　，。、“”‘’：；！？《》（）()【】\[\]「」『』,.!?;:·…—-]'),
    '',
  );
}

class _JinshiDiamond extends StatelessWidget {
  const _JinshiDiamond({
    required this.size,
    required this.points,
    required this.onTap,
  });

  final double size;
  final int? points;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final labelStyle = theme.textTheme.titleMedium?.copyWith(
      color: const Color(0xFF4F3B12),
      fontFamily: kFeiHuaSongTiFontFamily,
      fontWeight: FontWeight.w700,
      fontSize: 22,
      height: 1.1,
    );

    return SizedBox(
      width: size,
      height: size,
      child: Semantics(
        button: true,
        label: '既成',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: size * 0.78,
                  height: size * 0.78,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFFFFFF),
                        Color(0xFFF9F5EC),
                      ],
                    ),
                    border: Border.all(
                      color: primary.withOpacity(0.58),
                      width: 1.1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6D5318).withOpacity(0.07),
                        blurRadius: 20,
                        offset: const Offset(0, 9),
                      ),
                      BoxShadow(
                        color: Colors.white.withOpacity(0.72),
                        blurRadius: 8,
                        offset: const Offset(-3, -3),
                      ),
                    ],
                  ),
                ),
              ),
              Transform.rotate(
                angle: math.pi / 4,
                child: ClipRect(
                  child: SizedBox(
                    width: size * 0.62,
                    height: size * 0.62,
                    child: Transform.rotate(
                      angle: -math.pi / 4,
                      child: Opacity(
                        opacity: 0.12,
                        child: Image.asset(
                          'assets/branding/cloud_mark.png',
                          fit: BoxFit.cover,
                          color: const Color(0xFFD1A34A),
                          colorBlendMode: BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: size * 0.58,
                  height: size * 0.58,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFFE7D8B5).withOpacity(0.82),
                      width: 0.9,
                    ),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('既成', style: labelStyle),
                  const SizedBox(height: 4),
                  Text(
                    points == null ? '...' : points.toString(),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: const Color(0xFF4F3B12),
                      fontFamily: kFeiHuaSongTiFontFamily,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ],
              ),
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
      appBar: AppBar(
        title: Text(
          '进士记录',
          style: theme.textTheme.headlineSmall?.copyWith(
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
                    titleAlignment: ListTileTitleAlignment.center,
                    leading: SizedBox(
                      width: 56,
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: const Color(0xFF8A6A00),
                            fontFamily: kFeiHuaSongTiFontFamily,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      poem.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFamily: kFeiHuaSongTiFontFamily,
                        fontWeight: FontWeight.w700,
                      ),
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
