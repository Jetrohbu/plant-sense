import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sensor_provider.dart';
import '../widgets/plant_card.dart';
import '../widgets/ui_helpers.dart';
import 'plant_detail_screen.dart';
import 'plant_search_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<SensorProvider>();
    Future.microtask(provider.loadSensors);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Mon jardin',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Consumer<SensorProvider>(
            builder: (context, provider, _) {
              if (provider.isRefreshingAll) {
                return const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                );
              }
              return GlassIconButton(
                icon: Icons.sync,
                tooltip: 'Rafraichir tout',
                iconColor: const Color(0xFF80D8FF),
                onPressed: () => provider.refreshAll(),
              );
            },
          ),
          GlassIconButton(
            icon: Icons.local_florist,
            tooltip: 'Bibliotheque de plantes',
            iconColor: const Color(0xFFA5D6A7),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const PlantSearchScreen()),
              );
            },
          ),
          GlassIconButton(
            icon: Icons.settings,
            tooltip: 'Reglages',
            iconColor: const Color(0xFFFFE082),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Container(
        decoration: appBackgroundGradient(context),
        child: Consumer<SensorProvider>(
          builder: (context, provider, _) {
            if (provider.sensors.isEmpty) {
              return SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.local_florist,
                            size: 56,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Aucune plante connectee',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Scanne un capteur Bluetooth pour suivre l\'humidite, la lumiere et la temperature de tes plantes.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 14,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () async {
                            final provider = context.read<SensorProvider>();
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ScanScreen()),
                            );
                            if (mounted) provider.loadSensors();
                          },
                          icon: const Icon(Icons.bluetooth_searching),
                          label: const Text('Scanner un capteur'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF0288D1),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return SafeArea(
              child: Column(
                children: [
                  if (provider.lastError != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade400.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              provider.lastError!,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close,
                                size: 16, color: Colors.white),
                            onPressed: () => provider.clearErrors(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 8),
                      itemCount: provider.sensors.length,
                      itemBuilder: (context, index) {
                        final sensor = provider.sensors[index];
                        final profile = sensor.id != null
                            ? provider.getProfile(sensor.id!)
                            : null;
                        final outOfRange = sensor.id != null
                            ? provider.getOutOfRangeParams(sensor.id!)
                            : <String>[];

                        return PlantCard(
                          sensor: sensor,
                          latestReading: sensor.id != null
                              ? provider.latestReadings[sensor.id]
                              : null,
                          plantProfile: profile,
                          outOfRangeParams: outOfRange,
                          isReading: sensor.id != null
                              ? provider.isReading(sensor.id!)
                              : false,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PlantDetailScreen(sensor: sensor),
                              ),
                            );
                          },
                          onRefresh: () {
                            provider.readSensor(sensor);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final provider = context.read<SensorProvider>();
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ScanScreen()),
          );
          if (mounted) provider.loadSensors();
        },
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0288D1),
        child: const Icon(Icons.add),
      ),
    );
  }
}
