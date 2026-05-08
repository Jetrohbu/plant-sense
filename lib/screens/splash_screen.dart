import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sensor_provider.dart';
import '../widgets/ui_helpers.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late AnimationController _slideCtrl;
  late Animation<double> _logoFade;
  late Animation<Offset> _logoSlide;
  late Animation<double> _titleFade;
  late Animation<double> _taglineFade;
  late Animation<double> _pillsFade;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    );
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _logoFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: const Interval(0, 0.3, curve: Curves.easeOut)),
    );
    _logoSlide = Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic),
    );
    _titleFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: const Interval(0.2, 0.5, curve: Curves.easeOut)),
    );
    _taglineFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: const Interval(0.35, 0.65, curve: Curves.easeOut)),
    );
    _pillsFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: const Interval(0.5, 0.8, curve: Curves.easeOut)),
    );

    _fadeCtrl.forward();
    _slideCtrl.forward();

    _initAndNavigate();
  }

  Future<void> _initAndNavigate() async {
    final provider = context.read<SensorProvider>();
    await provider.loadSensors();
    await Future.delayed(const Duration(milliseconds: 5000));

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: appBackgroundGradient(context),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _fadeCtrl,
            builder: (context, _) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Logo
                SlideTransition(
                  position: _logoSlide,
                  child: Opacity(
                    opacity: _logoFade.value,
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 32,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Image.asset(
                        'assets/icon.png',
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.eco,
                          size: 80,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Title
                Opacity(
                  opacity: _titleFade.value,
                  child: RichText(
                    text: const TextSpan(
                      style: TextStyle(fontSize: 38, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                      children: [
                        TextSpan(text: 'Plant', style: TextStyle(color: Colors.white)),
                        TextSpan(text: 'Sense', style: TextStyle(color: Color(0xFFB3E5FC))),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Tagline
                Opacity(
                  opacity: _taglineFade.value,
                  child: Column(
                    children: [
                      Text(
                        'SMART PLANT CARE',
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Prenez soin de vos plantes,\nintelligemment.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white.withValues(alpha: 0.8),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Feature pills
                Opacity(
                  opacity: _pillsFade.value,
                  child: const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      _FeaturePill(icon: Icons.water_drop, label: 'Humidite'),
                      _FeaturePill(icon: Icons.thermostat, label: 'Temperature'),
                      _FeaturePill(icon: Icons.light_mode, label: 'Luminosite'),
                      _FeaturePill(icon: Icons.electric_bolt, label: 'Conductivite'),
                    ],
                  ),
                ),

                const Spacer(flex: 3),

                Opacity(
                  opacity: _pillsFade.value * 0.5,
                  child: const Text(
                    'v1.0',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white54,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
