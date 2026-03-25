import 'dart:math';
import 'package:flutter/material.dart';

/// Animated pot/glass visualization showing soil moisture level
/// with bubble animation, inspired by Parrot Flower Power app.
class WaterPotWidget extends StatefulWidget {
  final double? moisturePercent;
  final String? plantImageUrl;

  const WaterPotWidget({
    super.key,
    this.moisturePercent,
    this.plantImageUrl,
  });

  @override
  State<WaterPotWidget> createState() => _WaterPotWidgetState();
}

class _WaterPotWidgetState extends State<WaterPotWidget>
    with TickerProviderStateMixin {
  late AnimationController _waveCtrl;
  late AnimationController _bubbleCtrl;
  final _random = Random();
  late List<_Bubble> _bubbles;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _bubbleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _bubbles = List.generate(12, (_) => _Bubble.random(_random));
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    _bubbleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final moisture = widget.moisturePercent ?? 0;

    return SizedBox(
      height: 300,
      child: AnimatedBuilder(
        animation: Listenable.merge([_waveCtrl, _bubbleCtrl]),
        builder: (context, _) {
          return CustomPaint(
            painter: _PotPainter(
              waterLevel: moisture / 100.0,
              wavePhase: _waveCtrl.value * 2 * pi,
              bubbles: _bubbles,
              bubblePhase: _bubbleCtrl.value,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${moisture.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withValues(alpha: 0.95),
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Humidite de la\nterre',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.8),
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Bubble {
  final double x; // 0-1 horizontal position
  final double startY; // 0-1 start vertical offset
  final double size; // radius
  final double speed; // speed multiplier

  _Bubble(this.x, this.startY, this.size, this.speed);

  static _Bubble random(Random r) {
    return _Bubble(
      r.nextDouble(),
      r.nextDouble(),
      2.0 + r.nextDouble() * 4.0,
      0.5 + r.nextDouble() * 1.0,
    );
  }
}

class _PotPainter extends CustomPainter {
  final double waterLevel; // 0.0 to 1.0
  final double wavePhase;
  final List<_Bubble> bubbles;
  final double bubblePhase;

  _PotPainter({
    required this.waterLevel,
    required this.wavePhase,
    required this.bubbles,
    required this.bubblePhase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Pot dimensions (glass/cup shape)
    final potLeft = w * 0.15;
    final potRight = w * 0.85;
    final potTop = h * 0.05;
    final potBottom = h * 0.92;
    final potHeight = potBottom - potTop;

    // Slight taper: bottom narrower than top
    final topLeft = potLeft;
    final topRight = potRight;
    final bottomLeft = potLeft + w * 0.05;
    final bottomRight = potRight - w * 0.05;

    // Draw pot outline
    final potPath = Path()
      ..moveTo(topLeft, potTop)
      ..lineTo(bottomLeft, potBottom)
      ..lineTo(bottomRight, potBottom)
      ..lineTo(topRight, potTop)
      ..close();

    // Pot glass background
    final potBgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawPath(potPath, potBgPaint);

    // Water area
    final clampedLevel = waterLevel.clamp(0.0, 1.0);
    if (clampedLevel > 0.01) {
      final waterTop = potBottom - (potHeight * clampedLevel);

      // Interpolate left/right edges at water level
      final t = 1.0 - clampedLevel; // 0=bottom, 1=top of pot
      final waterLeft = bottomLeft + (topLeft - bottomLeft) * (1 - t);
      final waterRight = bottomRight + (topRight - bottomRight) * (1 - t);

      // Wave path
      final wavePath = Path();
      wavePath.moveTo(waterLeft, waterTop);

      // Draw wavy top
      for (double x = waterLeft; x <= waterRight; x += 2) {
        final normalX = (x - waterLeft) / (waterRight - waterLeft);
        final waveY = sin(normalX * 4 * pi + wavePhase) * 3.0 +
            sin(normalX * 6 * pi + wavePhase * 1.3) * 1.5;
        wavePath.lineTo(x, waterTop + waveY);
      }

      wavePath.lineTo(waterRight, waterTop);
      wavePath.lineTo(bottomRight, potBottom);
      wavePath.lineTo(bottomLeft, potBottom);
      wavePath.close();

      // Clip to pot shape
      canvas.save();
      canvas.clipPath(potPath);

      // Water gradient
      final waterPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF4FC3F7).withValues(alpha: 0.6),
            const Color(0xFF0288D1).withValues(alpha: 0.8),
            const Color(0xFF01579B).withValues(alpha: 0.9),
          ],
        ).createShader(Rect.fromLTRB(0, waterTop, w, potBottom));
      canvas.drawPath(wavePath, waterPaint);

      // Draw bubbles
      final bubblePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;

      for (final b in bubbles) {
        final bx = waterLeft + b.x * (waterRight - waterLeft);
        final waterHeight = potBottom - waterTop;
        final rawY = (b.startY + bubblePhase * b.speed) % 1.0;
        final by = potBottom - rawY * waterHeight;

        if (by > waterTop && by < potBottom) {
          canvas.drawCircle(Offset(bx, by), b.size, bubblePaint);
          // Highlight on bubble
          final highlightPaint = Paint()
            ..color = Colors.white.withValues(alpha: 0.15)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(
              Offset(bx - b.size * 0.3, by - b.size * 0.3),
              b.size * 0.4,
              highlightPaint);
        }
      }

      canvas.restore();
    }

    // Pot outline border
    final potOutlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(potPath, potOutlinePaint);

    // Pot rim (thicker line at top)
    final rimPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(topLeft - 4, potTop), Offset(topRight + 4, potTop), rimPaint);
  }

  @override
  bool shouldRepaint(_PotPainter old) => true;
}
