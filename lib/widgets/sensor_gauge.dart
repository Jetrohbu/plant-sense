import 'dart:math' as math;
import 'package:flutter/material.dart';

class SensorGauge extends StatelessWidget {
  final String label;
  final String unit;
  final double? value;
  final double minValue;
  final double maxValue;
  final double? warningLow;
  final double? warningHigh;
  final IconData icon;

  const SensorGauge({
    super.key,
    required this.label,
    required this.unit,
    this.value,
    this.minValue = 0,
    this.maxValue = 100,
    this.warningLow,
    this.warningHigh,
    required this.icon,
  });

  Color _getColor() {
    if (value == null) return Colors.grey;
    if (warningLow != null && value! < warningLow!) return Colors.red;
    if (warningHigh != null && value! > warningHigh!) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    final percentage = value != null
        ? ((value! - minValue) / (maxValue - minValue)).clamp(0.0, 1.0)
        : 0.0;

    final hasRange = warningLow != null || warningHigh != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: CustomPaint(
            painter: _GaugePainter(percentage: percentage, color: color),
            child: Center(
              child: Icon(icon, color: color, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value != null ? '${value!.toStringAsFixed(1)} $unit' : '-- $unit',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        if (hasRange)
          Text(
            _rangeText(),
            style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          )
        else
          const SizedBox(height: 12),
      ],
    );
  }

  String _rangeText() {
    final low = warningLow;
    final high = warningHigh;
    String fmt(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    if (low != null && high != null) return '${fmt(low)}–${fmt(high)}';
    if (low != null) return '>${fmt(low)}';
    if (high != null) return '<${fmt(high)}';
    return '';
  }
}

class _GaugePainter extends CustomPainter {
  final double percentage;
  final Color color;

  _GaugePainter({required this.percentage, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;

    final bgPaint = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi * 0.75,
      math.pi * 1.5,
      false,
      bgPaint,
    );

    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi * 0.75,
      math.pi * 1.5 * percentage,
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) =>
      oldDelegate.percentage != percentage || oldDelegate.color != color;
}
