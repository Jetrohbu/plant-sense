import 'package:flutter/material.dart';

/// Frosted-glass circular button used for AppBar actions over the gradient
/// background — softens the icons compared to bare white glyphs and accepts
/// an optional [iconColor] for a touch of semantic color (e.g. green for the
/// plant library, gold for settings).
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? iconColor;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: iconColor ?? Colors.white, size: 20),
          ),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
  }
}

/// Page background gradient. Derives its colors from the current
/// `ColorScheme` so changing the theme's seed re-tints every screen, and
/// dark mode lands on deeper shades automatically.
BoxDecoration appBackgroundGradient(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final base = cs.primary;
  if (dark) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(base, Colors.black, 0.55)!,
          Color.lerp(base, Colors.black, 0.70)!,
          Color.lerp(base, Colors.black, 0.82)!,
          Color.lerp(base, Colors.black, 0.92)!,
        ],
      ),
    );
  }
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.lerp(base, Colors.white, 0.45)!,
        Color.lerp(base, Colors.white, 0.20)!,
        base,
        Color.lerp(base, Colors.black, 0.35)!,
      ],
    ),
  );
}

/// Color used to summarize a sensor's overall status given how many of its
/// readings are out of the configured range.
Color statusDotColor(int outOfRange) {
  if (outOfRange == 0) return const Color(0xFF4CAF50);
  if (outOfRange == 1) return const Color(0xFFFFA726);
  return const Color(0xFFE53935);
}
