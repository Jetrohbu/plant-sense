import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Soil-moisture visualization with two display modes:
///   * Glass pot only — drawn with a Flutter [CustomPainter] (compact, 300dp).
///   * Full flower scene — the original CSS art by Md Usman Ansari embedded as
///     a WebView (taller, 500dp). The pot's water level is driven from
///     Flutter via `window.setMoisture(pct)` over JS.
///
/// The percentage is overlaid as Flutter text in both modes.
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
  // Persist the user's mode choice within the session. Flower scene is the
  // default so the moisture screen lands on the full animation.
  static bool _showFlowersDefault = true;

  late final AnimationController _wave;
  late final AnimationController _shimmer;
  late final AnimationController _breath;
  late final AnimationController _bubble;
  InAppWebViewController? _web;
  late bool _showFlowers;
  bool _webReady = false;
  // After the WebView has played its initial blooming animations we capture
  // a screenshot, store it here, and swap the WebView out for a regular
  // [Image.memory] of the snapshot. This removes the platform view from the
  // tree entirely so scrolls past the widget cost nothing. The animation
  // replays on the next visit to this screen, when a fresh WebView is
  // created.
  Timer? _freezeTimer;
  Uint8List? _frozenSnapshot;
  static const Duration _freezeAfter = Duration(seconds: 8);

  static const double _potOnlyHeight = 300.0;
  static const double _flowersHeight = 250.0;

  @override
  void initState() {
    super.initState();
    _showFlowers = _showFlowersDefault;
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
    _bubble = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant WaterPotWidget old) {
    super.didUpdateWidget(old);
    if (widget.moisturePercent != old.moisturePercent) {
      _pushMoistureToWeb();
    }
  }

  @override
  void dispose() {
    _freezeTimer?.cancel();
    _wave.dispose();
    _shimmer.dispose();
    _breath.dispose();
    _bubble.dispose();
    super.dispose();
  }

  void _scheduleFreeze() {
    _freezeTimer?.cancel();
    _freezeTimer = Timer(_freezeAfter, _captureAndFreeze);
  }

  Future<void> _captureAndFreeze() async {
    final web = _web;
    if (web == null || !_webReady || !mounted) return;
    try {
      final bytes = await web.takeScreenshot();
      if (bytes != null && mounted) {
        setState(() => _frozenSnapshot = bytes);
      }
    } catch (_) {
      // takeScreenshot can fail on some Android versions; if that happens we
      // just keep the WebView visible — worse perf, but not broken.
    }
  }

  void _pushMoistureToWeb() {
    final web = _web;
    if (web == null || !_webReady) return;
    final m = (widget.moisturePercent ?? 0).clamp(0.0, 100.0);
    web.evaluateJavascript(
        source:
            'window.setMoisture && window.setMoisture(${m.toStringAsFixed(1)});');
  }

  void _toggleFlowers() {
    setState(() {
      _showFlowers = !_showFlowers;
      _showFlowersDefault = _showFlowers;
    });
  }

  @override
  Widget build(BuildContext context) {
    final moisture = (widget.moisturePercent ?? 0).clamp(0.0, 100.0);
    final totalHeight = _showFlowers ? _flowersHeight : _potOnlyHeight;
    // Visible pot region inside the WebView: the CSS pot is 26vmin tall,
    // anchored to the bottom. With the flowers viewport now 250dp the pot
    // collapses to roughly 65dp; centering text in 70dp lands it on the pot.
    final potRegionHeight = _showFlowers ? 70.0 : _potOnlyHeight;

    return SizedBox(
      height: totalHeight,
      child: Stack(
        children: [
          if (_showFlowers && _frozenSnapshot != null)
            Positioned.fill(
              child: Image.memory(
                _frozenSnapshot!,
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            )
          else if (_showFlowers)
            Positioned.fill(
              child: ClipRect(
                child: InAppWebView(
                  initialFile: 'assets/animations/flower_pot.html',
                  initialSettings: InAppWebViewSettings(
                    transparentBackground: true,
                    supportZoom: false,
                    disableHorizontalScroll: true,
                    disableVerticalScroll: true,
                    useWideViewPort: false,
                  ),
                  onWebViewCreated: (c) => _web = c,
                  onLoadStop: (c, url) async {
                    _webReady = true;
                    _pushMoistureToWeb();
                    _scheduleFreeze();
                  },
                ),
              ),
            )
          else
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation:
                      Listenable.merge([_wave, _shimmer, _breath, _bubble]),
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _PotPainter(
                        moisture: moisture / 100.0,
                        wavePhase: _wave.value * 2 * pi,
                        shimmer: _shimmer.value,
                        breath: _breath.value,
                        bubblePhase: _bubble.value,
                      ),
                    );
                  },
                ),
              ),
            ),

          // Percentage overlay — anchored on the visible pot region.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: potRegionHeight,
            child: IgnorePointer(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${moisture.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: _showFlowers ? 24 : 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withValues(alpha: 0.95),
                        height: 1.0,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    if (!_showFlowers)
                      Text(
                        'Humidite de la\nterre',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.85),
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Toggle button — top right.
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.white.withValues(alpha: 0.18),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _toggleFlowers,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    _showFlowers
                        ? Icons.water_drop_outlined
                        : Icons.local_florist,
                    color: Colors.white.withValues(alpha: 0.9),
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PotPainter extends CustomPainter {
  final double moisture; // 0..1
  final double wavePhase; // radians
  final double shimmer; // 0..1 alternating
  final double breath; // 0..1 looping
  final double bubblePhase; // 0..1 looping

  static const _cyan = Color(0xFF23F0FF);
  static const _lightCyan = Color(0xFFA7FFEE);
  static const _midTeal = Color(0xFF14757A);
  static const _waterDeep = Color(0xFF08325F);
  static const _bodyTop = Color(0x33072036);
  static const _bodyBottom = Color(0x66041424);

  _PotPainter({
    required this.moisture,
    required this.wavePhase,
    required this.shimmer,
    required this.breath,
    required this.bubblePhase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final potW = w * 0.7;
    final potH = h * 0.86;
    final potX = (w - potW) / 2;
    final potY = h * 0.07;
    final p = Rect.fromLTWH(potX, potY, potW, potH);

    final topLeft = Offset(p.left + p.width * 0.02, p.top);
    final topRight = Offset(p.left + p.width * 0.98, p.top);
    final bottomRight = Offset(p.left + p.width * 0.88, p.bottom);
    final bottomLeft = Offset(p.left + p.width * 0.12, p.bottom);

    final bodyPath = Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(topRight.dx, topRight.dy)
      ..lineTo(bottomRight.dx, bottomRight.dy)
      ..lineTo(bottomLeft.dx, bottomLeft.dy)
      ..close();

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [_bodyTop, _bodyBottom],
      ).createShader(p);
    canvas.drawPath(bodyPath, bodyPaint);

    canvas.save();
    canvas.clipPath(bodyPath);

    final innerGlow = Paint()
      ..shader = RadialGradient(
        center: Alignment.bottomCenter,
        radius: 1.2,
        colors: [
          _cyan.withValues(alpha: 0.18),
          Colors.transparent,
        ],
      ).createShader(p);
    canvas.drawRect(p, innerGlow);

    final breathOsc = sin(breath * 2 * pi) * 0.025;
    final waterFraction = (moisture + breathOsc).clamp(0.0, 1.0);

    if (waterFraction > 0.005) {
      final waterTop = p.bottom - waterFraction * p.height;
      final t = (waterTop - p.top) / p.height;
      final waterLeft = topLeft.dx * (1 - t) + bottomLeft.dx * t;
      final waterRight = topRight.dx * (1 - t) + bottomRight.dx * t;

      final wavePath = Path()..moveTo(waterLeft, waterTop);
      const segments = 60;
      for (int i = 0; i <= segments; i++) {
        final f = i / segments;
        final x = waterLeft + (waterRight - waterLeft) * f;
        final y = waterTop +
            sin(f * 4 * pi + wavePhase) * 2.5 +
            sin(f * 8 * pi - wavePhase * 1.4) * 1.0;
        wavePath.lineTo(x, y);
      }
      wavePath.lineTo(waterRight, waterTop);
      wavePath.lineTo(bottomRight.dx, p.bottom);
      wavePath.lineTo(bottomLeft.dx, p.bottom);
      wavePath.close();

      final waterPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _cyan.withValues(alpha: 0.35),
            _midTeal.withValues(alpha: 0.55),
            _waterDeep.withValues(alpha: 0.75),
          ],
        ).createShader(Rect.fromLTRB(p.left, waterTop, p.right, p.bottom));
      canvas.drawPath(wavePath, waterPaint);

      final surfaceRect = Rect.fromLTRB(
        waterLeft - 6,
        waterTop - 3,
        waterRight + 6,
        waterTop + 3,
      );
      final surfacePaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            _lightCyan.withValues(alpha: 0.0),
            _lightCyan.withValues(alpha: 0.55),
            _lightCyan.withValues(alpha: 0.05),
            _lightCyan.withValues(alpha: 0.4),
            _lightCyan.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
        ).createShader(surfaceRect);
      canvas.drawRect(surfaceRect, surfacePaint);

      final shimmerArea =
          Rect.fromLTRB(waterLeft, waterTop, waterRight, p.bottom);
      final shimmer1 = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.5, -0.4),
          radius: 0.5,
          colors: [
            _lightCyan.withValues(alpha: 0.18 * (1 - shimmer * 0.5)),
            Colors.transparent,
          ],
        ).createShader(shimmerArea);
      canvas.drawRect(shimmerArea, shimmer1);

      final shimmer2 = Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.5, 0.2),
          radius: 0.4,
          colors: [
            _cyan.withValues(alpha: 0.15 * (0.5 + shimmer * 0.5)),
            Colors.transparent,
          ],
        ).createShader(shimmerArea);
      canvas.drawRect(shimmerArea, shimmer2);

      _drawBubble(canvas, p, waterLeft, waterRight, waterTop,
          xFrac: 0.22, delay: 0.0, size: 4.5);
      _drawBubble(canvas, p, waterLeft, waterRight, waterTop,
          xFrac: 0.65, delay: 1.8, size: 3.0);
      _drawBubble(canvas, p, waterLeft, waterRight, waterTop,
          xFrac: 0.45, delay: 3.2, size: 3.6);
      _drawBubble(canvas, p, waterLeft, waterRight, waterTop,
          xFrac: 0.78, delay: 4.1, size: 2.7);
    }

    canvas.restore();

    canvas.save();
    canvas.translate(p.left + p.width * 0.13, p.top + p.height * 0.5);
    canvas.rotate(0.07);
    final shineLeftRect = Rect.fromCenter(
      center: Offset.zero,
      width: 5,
      height: p.height * 0.78,
    );
    final shineLeftPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.45),
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.25, 0.7, 1.0],
      ).createShader(shineLeftRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(shineLeftRect, const Radius.circular(2)),
      shineLeftPaint,
    );
    canvas.restore();

    canvas.save();
    canvas.translate(p.left + p.width * 0.84, p.top + p.height * 0.5);
    canvas.rotate(-0.05);
    final shineRightRect = Rect.fromCenter(
      center: Offset.zero,
      width: 3,
      height: p.height * 0.72,
    );
    final shineRightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(shineRightRect);
    canvas.drawRect(shineRightRect, shineRightPaint);
    canvas.restore();

    final gaugeAnchorX = p.left + p.width * 0.78;
    final gaugeTop = p.top + p.height * 0.22;
    final gaugeHeight = p.height * 0.65;
    for (int i = 0; i < 7; i++) {
      final y = gaugeTop + (gaugeHeight / 6) * i;
      final isLong = i % 2 == 0;
      final tickW = isLong ? p.width * 0.06 : p.width * 0.035;
      final tickPaint = Paint()
        ..color = _lightCyan.withValues(alpha: isLong ? 0.35 : 0.21)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
          Offset(gaugeAnchorX - tickW, y), Offset(gaugeAnchorX, y), tickPaint);
    }

    final bodyStroke = Paint()
      ..color = _lightCyan.withValues(alpha: 0.7)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(bodyPath, bodyStroke);

    final topBorder = Paint()
      ..color = _lightCyan.withValues(alpha: 0.85)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(topLeft, topRight, topBorder);

    final rimRect = Rect.fromLTWH(
      p.left - p.width * 0.026,
      p.top - p.height * 0.027,
      p.width * 1.052,
      p.height * 0.085,
    );
    final rimGlow = Paint()
      ..color = _cyan.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawOval(rimRect, rimGlow);

    final rimPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Color(0xFF8CE6F5),
          Color(0xFF3C96BE),
          Color(0xFF0F3250),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(rimRect);
    canvas.drawOval(rimRect, rimPaint);
  }

  void _drawBubble(
    Canvas canvas,
    Rect pot,
    double waterLeft,
    double waterRight,
    double waterTop, {
    required double xFrac,
    required double delay,
    required double size,
  }) {
    var progress = (bubblePhase * 5 - delay) / 5;
    progress = progress - progress.floorToDouble();
    if (progress.isNaN) return;

    final waterHeight = pot.bottom - waterTop;
    final by = pot.bottom - 0.05 * waterHeight - progress * 0.57 * waterHeight;
    if (by < waterTop) return;

    double op;
    if (progress < 0.15) {
      op = (progress / 0.15) * 0.9;
    } else if (progress < 0.9) {
      op = 0.9 - ((progress - 0.15) / 0.75) * 0.3;
    } else {
      op = 0.6 * (1 - (progress - 0.9) / 0.1);
    }

    final bx = waterLeft + xFrac * (waterRight - waterLeft) + progress * 4.5;

    final body = Paint()
      ..color = _lightCyan.withValues(alpha: 0.3 * op)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(bx, by), size, body);

    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.9 * op)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(bx - size * 0.3, by - size * 0.3),
      size * 0.35,
      highlight,
    );
  }

  @override
  bool shouldRepaint(_PotPainter old) => true;
}
