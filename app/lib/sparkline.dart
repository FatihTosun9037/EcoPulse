import 'package:flutter/material.dart';

import 'theme.dart';

/// Neon çizgili, hafif ışımalı canlı sensör grafiği.
class Sparkline extends StatelessWidget {
  const Sparkline({
    required this.label,
    required this.valueText,
    required this.values,
    required this.color,
    this.icon,
    this.height = 92,
    super.key,
  });

  final String label;
  final String valueText;
  final List<double> values;
  final Color color;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
              ],
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                child: Text(
                  valueText,
                  key: ValueKey(valueText),
                  style: EcoText.mono(size: 13, color: color, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, progress, child) {
                return CustomPaint(painter: _SparkPainter(values, color, progress));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.progress);

  final List<double> values;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 8 || size.height < 8) {
      return;
    }

    final guide = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guide);
    }

    if (values.length < 2) {
      return;
    }

    var min = values.reduce((a, b) => a < b ? a : b);
    var max = values.reduce((a, b) => a > b ? a : b);
    final pad = (max - min) * 0.16;
    min -= pad < 0.001 ? 1 : pad;
    max += pad < 0.001 ? 1 : pad;
    final span = max - min;

    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = index * size.width / (values.length - 1);
      final y = size.height - ((values[index] - min) / span * size.height);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) {
      return;
    }

    final metric = metrics.first;
    final drawn = metric.extractPath(0, metric.length * progress.clamp(0, 1));
    final fill = Path.from(drawn)
      ..lineTo(size.width * progress.clamp(0.001, 1), size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      drawn,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final last = metric.getTangentForOffset(metric.length * progress.clamp(0, 1));
    if (last != null) {
      canvas.drawCircle(last.position, 2.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color || oldDelegate.progress != progress;
}
