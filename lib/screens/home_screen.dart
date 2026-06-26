import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../theme/app_typography.dart';
import '../widgets/huiyun_visuals.dart';
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final topPadding =
                          constraints.maxHeight < 560 ? 10.0 : 24.0;
                      return Padding(
                        padding: EdgeInsets.fromLTRB(16, topPadding, 16, 12),
                        child: Align(
                          alignment: Alignment.topCenter,
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
                            child: _HomeCompass(
                              points: _jinshiPoints,
                              onJinshiTap: _openJinshiHistory,
                              onTrainingReturn: _loadJinshiPoints,
                              onLibraryReturn: _loadJinshiPoints,
                              onSettingsReturn: _loadJinshiPoints,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Text(
                    '绘云诗人作品\nBy Cloudweaver Poet',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF8A7A4A),
                      height: 1.45,
                    ),
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

    final brush = Paint()
      ..color = const Color(0xFFCDB56D).withOpacity(0.14)
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.22, size.height * 0.76),
      Offset(size.width * 0.42, size.height * 0.7),
      brush,
    );
    canvas.drawLine(
      Offset(size.width * 0.58, size.height * 0.7),
      Offset(size.width * 0.78, size.height * 0.76),
      brush,
    );

    HuiyunCloudArt.drawRibbonCloud(
      canvas,
      center: Offset(size.width * 0.24, size.height * 0.62),
      width: math.min(size.width * 0.28, 128),
      color: const Color(0xFFC7A65D),
      opacity: 0.24,
      strokeWidth: 1.0,
    );
    HuiyunCloudArt.drawRibbonCloud(
      canvas,
      center: Offset(size.width * 0.76, size.height * 0.63),
      width: math.min(size.width * 0.28, 128),
      color: const Color(0xFFC7A65D),
      opacity: 0.20,
      strokeWidth: 1.0,
      mirror: true,
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

    HuiyunCloudArt.drawCloudWash(
      canvas,
      center: Offset(size.width * 0.72, size.height * 0.30),
      width: size.width * 0.42,
      color: const Color(0xFFD5B66C),
      opacity: 0.05,
      mirror: true,
    );
    HuiyunCloudArt.drawRibbonCloud(
      canvas,
      center: Offset(size.width * 0.76, size.height * 0.31),
      width: size.width * 0.34,
      color: const Color(0xFFC7A65D),
      opacity: 0.12,
      strokeWidth: 1.1,
      mirror: true,
    );
    HuiyunCloudArt.drawRibbonCloud(
      canvas,
      center: Offset(size.width * 0.24, size.height * 0.46),
      width: size.width * 0.32,
      color: const Color(0xFF8E9278),
      opacity: 0.08,
      strokeWidth: 1.0,
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

    final mountainPaint = Paint()
      ..color = const Color(0xFF8E9278).withOpacity(0.09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final mountainPath = Path()
      ..moveTo(-20, size.height * 0.58)
      ..cubicTo(
        size.width * 0.16,
        size.height * 0.48,
        size.width * 0.28,
        size.height * 0.66,
        size.width * 0.46,
        size.height * 0.55,
      )
      ..cubicTo(
        size.width * 0.62,
        size.height * 0.45,
        size.width * 0.76,
        size.height * 0.64,
        size.width + 20,
        size.height * 0.5,
      );
    canvas.drawPath(mountainPath, mountainPaint);

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

class _HomeCompass extends StatelessWidget {
  const _HomeCompass({
    required this.points,
    required this.onJinshiTap,
    required this.onTrainingReturn,
    required this.onLibraryReturn,
    required this.onSettingsReturn,
  });

  final int? points;
  final VoidCallback onJinshiTap;
  final VoidCallback onTrainingReturn;
  final VoidCallback onLibraryReturn;
  final VoidCallback onSettingsReturn;

  Future<void> _open(
    BuildContext context,
    Widget destination, {
    VoidCallback? onReturn,
  }) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (context) => destination),
    );
    onReturn?.call();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boardWidth = math.min(constraints.maxWidth, 520.0);
        final gap = boardWidth < 360 ? 8.0 : 10.0;
        final cardWidth = (boardWidth - gap) / 2;
        final cardHeight = (boardWidth * 0.38).clamp(134.0, 188.0).toDouble();
        final boardHeight = cardHeight * 2 + gap;
        final diamondSize = (boardWidth * 0.35).clamp(118.0, 164.0).toDouble();

        return SizedBox(
          width: boardWidth,
          height: boardHeight,
          child: CustomPaint(
            painter: _CompassFramePainter(
              gap: gap,
              diamondSize: diamondSize,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: cardWidth,
                  height: cardHeight,
                  child: _HomeCompassTile(
                    title: '学文',
                    icon: Icons.menu_book_outlined,
                    accentColor: Color(0xFF8E9278),
                    onTap: () => _open(context, const LearningModeScreen()),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  width: cardWidth,
                  height: cardHeight,
                  child: _HomeCompassTile(
                    title: '展才',
                    icon: Icons.edit_note_outlined,
                    accentColor: Color(0xFFC39A32),
                    onTap: () => _open(
                      context,
                      const TrainingModeScreen(),
                      onReturn: onTrainingReturn,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  bottom: 0,
                  width: cardWidth,
                  height: cardHeight,
                  child: _HomeCompassTile(
                    title: '书架',
                    icon: Icons.folder_outlined,
                    accentColor: Color(0xFF9A7B48),
                    onTap: () => _open(
                      context,
                      const CollectionListScreen(),
                      onReturn: onLibraryReturn,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  width: cardWidth,
                  height: cardHeight,
                  child: _HomeCompassTile(
                    title: '设置',
                    icon: Icons.settings_outlined,
                    accentColor: Color(0xFF8E8872),
                    onTap: () => _open(
                      context,
                      const ApiSettingsScreen(),
                      onReturn: onSettingsReturn,
                    ),
                  ),
                ),
                _JinshiDiamond(
                  size: diamondSize,
                  points: points,
                  onTap: onJinshiTap,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CompassFramePainter extends CustomPainter {
  const _CompassFramePainter({
    required this.gap,
    required this.diamondSize,
  });

  final double gap;
  final double diamondSize;

  @override
  void paint(Canvas canvas, Size size) {
    final hairline = Paint()
      ..color = const Color(0xFFD6BF77).withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final accent = Paint()
      ..color = const Color(0xFF8A6500).withOpacity(0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final center = Offset(size.width / 2, size.height / 2);
    final halfGap = gap / 2;
    final diamondReserve = diamondSize * 0.45;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-4, -4, size.width + 8, size.height + 8),
        const Radius.circular(12),
      ),
      hairline,
    );
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, center.dy - diamondReserve),
      hairline,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy + diamondReserve),
      Offset(center.dx, size.height),
      hairline,
    );
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(center.dx - diamondReserve, center.dy),
      hairline,
    );
    canvas.drawLine(
      Offset(center.dx + diamondReserve, center.dy),
      Offset(size.width, center.dy),
      hairline,
    );

    const corner = 28.0;
    canvas.drawLine(const Offset(0, 0), const Offset(corner, 0), accent);
    canvas.drawLine(const Offset(0, 0), const Offset(0, corner), accent);
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width - corner, 0),
      accent,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, corner),
      accent,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(corner, size.height),
      accent,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(0, size.height - corner),
      accent,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - corner, size.height),
      accent,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - corner),
      accent,
    );

    final nodePaint = Paint()
      ..color = const Color(0xFFD6BF77).withOpacity(0.28)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(center.dx - halfGap, center.dy), 2.2, nodePaint);
    canvas.drawCircle(Offset(center.dx + halfGap, center.dy), 2.2, nodePaint);
    canvas.drawCircle(Offset(center.dx, center.dy - halfGap), 2.2, nodePaint);
    canvas.drawCircle(Offset(center.dx, center.dy + halfGap), 2.2, nodePaint);
  }

  @override
  bool shouldRepaint(covariant _CompassFramePainter oldDelegate) {
    return oldDelegate.gap != gap || oldDelegate.diamondSize != diamondSize;
  }
}

class _HomeCompassTile extends StatelessWidget {
  const _HomeCompassTile({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = Color.lerp(
      const Color(0xFFE6D08A),
      accentColor,
      0.16,
    )!;
    final endColor = Color.lerp(
      const Color(0xFFFFF5D8),
      accentColor,
      0.055,
    )!;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6D5318).withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderColor, width: 1.1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFFFFDF4),
                endColor,
              ],
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  right: -14,
                  bottom: -12,
                  child: Icon(
                    icon,
                    size: 118,
                    color: accentColor.withOpacity(0.11),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TileFiberPainter(accentColor: accentColor),
                  ),
                ),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFF4F3B12),
                    fontFamily: kFeiHuaSongTiFontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 26,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TileFiberPainter extends CustomPainter {
  const _TileFiberPainter({required this.accentColor});

  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE8DDAE).withOpacity(0.26)
      ..strokeWidth = 0.6;
    canvas.drawLine(
      Offset(size.width * 0.13, size.height * 0.22),
      Offset(size.width * 0.82, size.height * 0.18),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.18, size.height * 0.78),
      Offset(size.width * 0.88, size.height * 0.74),
      paint,
    );

    HuiyunCloudArt.drawRibbonCloud(
      canvas,
      center: Offset(size.width * 0.50, size.height * 0.53),
      width: size.width * 0.56,
      color: accentColor,
      opacity: 0.11,
      strokeWidth: 0.9,
    );
  }

  @override
  bool shouldRepaint(covariant _TileFiberPainter oldDelegate) {
    return oldDelegate.accentColor != accentColor;
  }
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
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      color: const Color(0xFF4F3B12),
      fontFamily: kFeiHuaSongTiFontFamily,
      fontWeight: FontWeight.w700,
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
