import 'dart:math' as math;

import 'package:flutter/material.dart';

class HuiyunPalette {
  const HuiyunPalette._();

  static const ink = Color(0xFF3F3218);
  static const inkSoft = Color(0xFF6C5932);
  static const gold = Color(0xFFC99A25);
  static const goldDeep = Color(0xFF8A6A00);
  static const paper = Color(0xFFFFFBF0);
  static const paperWarm = Color(0xFFFFF6D6);
  static const paperDeep = Color(0xFFFFE9AD);
  static const border = Color(0xFFE7CF83);
  static const borderQuiet = Color(0xFFEEDFA8);
  static const cinnabar = Color(0xFF9D3B2E);
  static const moss = Color(0xFF7B8068);
}

class HuiyunPaperCard extends StatelessWidget {
  const HuiyunPaperCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.radius = 8,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? HuiyunPalette.gold : HuiyunPalette.border;
    final borderWidth = selected ? 1.35 : 1.0;

    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.92),
                HuiyunPalette.paper,
                HuiyunPalette.paperWarm.withOpacity(0.58),
              ],
              stops: const [0, 0.58, 1],
            ),
            border: Border.all(color: borderColor, width: borderWidth),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: HuiyunPalette.goldDeep.withOpacity(selected ? 0.12 : 0.06),
                blurRadius: selected ? 16 : 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onTap,
            onLongPress: onLongPress,
            child: CustomPaint(
              painter: _HuiyunCornerPainter(
                color: borderColor.withOpacity(selected ? 0.58 : 0.36),
                radius: radius,
              ),
              child: Padding(
                padding: padding,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HuiyunPageEntrance extends StatelessWidget {
  const HuiyunPageEntrance({
    super.key,
    required this.child,
    this.index = 0,
  });

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    final delay = math.min(index, 6) * 32;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class HuiyunEmptyState extends StatelessWidget {
  const HuiyunEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: HuiyunPaperCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: HuiyunPalette.paperDeep.withOpacity(0.42),
                    shape: BoxShape.circle,
                    border: Border.all(color: HuiyunPalette.borderQuiet),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Icon(
                      icon,
                      size: 34,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: HuiyunPalette.inkSoft,
                    height: 1.55,
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

class _HuiyunCornerPainter extends CustomPainter {
  const _HuiyunCornerPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 48 || size.height < 48) {
      return;
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    const inset = 6.0;
    const length = 28.0;

    void corner(Offset origin, double sx, double sy) {
      final path = Path()
        ..moveTo(origin.dx + sx * inset, origin.dy)
        ..lineTo(origin.dx + sx * length, origin.dy)
        ..moveTo(origin.dx, origin.dy + sy * inset)
        ..lineTo(origin.dx, origin.dy + sy * length);
      canvas.drawPath(path, paint);
    }

    corner(Offset(radius, radius), 1, 1);
    corner(Offset(size.width - radius, radius), -1, 1);
    corner(Offset(radius, size.height - radius), 1, -1);
    corner(Offset(size.width - radius, size.height - radius), -1, -1);
  }

  @override
  bool shouldRepaint(covariant _HuiyunCornerPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
