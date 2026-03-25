import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/sensor_provider.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PlantSenseApp());
}

class PlantSenseApp extends StatelessWidget {
  const PlantSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SensorProvider(),
      child: MaterialApp(
        title: 'PlantSense',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF2196F3),
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF42A5F5),
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.system,
        home: const SplashScreen(),
      ),
    );
  }
}
