import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sensor_provider.dart';
import '../widgets/plant_card.dart';
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
    Future.microtask(() {
      context.read<SensorProvider>().loadSensors();
    });
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
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                );
              }
              return IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: 'Rafraichir tout',
                onPressed: () => provider.refreshAll(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.eco, color: Colors.white),
            tooltip: 'Bibliotheque de plantes',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const PlantSearchScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF4FC3F7),
              Color(0xFF29B6F6),
              Color(0xFF0288D1),
              Color(0xFF01579B),
            ],
          ),
        ),
        child: Consumer<SensorProvider>(
          builder: (context, provider, _) {
            if (provider.sensors.isEmpty) {
              return SafeArea(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.eco, size: 64,
                          color: Colors.white.withValues(alpha: 0.6)),
                      const SizedBox(height: 16),
                      const Text(
                        'Aucun capteur',
                        style: TextStyle(
                            fontSize: 18, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Appuyez sur + pour scanner',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7)),
                      ),
                    ],
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
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ScanScreen()),
          );
          if (mounted) {
            context.read<SensorProvider>().loadSensors();
          }
        },
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0288D1),
        child: const Icon(Icons.add),
      ),
    );
  }
}
