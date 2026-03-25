import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../models/plant_sensor.dart';
import '../models/sensor_reading.dart';
import '../models/plant_profile.dart';
import '../providers/sensor_provider.dart';
import '../widgets/sensor_gauge.dart';
import '../widgets/history_chart.dart';
import '../widgets/water_pot_widget.dart';
import 'plant_search_screen.dart';

class PlantDetailScreen extends StatefulWidget {
  final PlantSensor sensor;

  const PlantDetailScreen({super.key, required this.sensor});

  @override
  State<PlantDetailScreen> createState() => _PlantDetailScreenState();
}

class _PlantDetailScreenState extends State<PlantDetailScreen> {
  int _selectedPeriodIndex = 1;
  int _selectedTab = 0; // 0=moisture, 1=light, 2=temp, 3=conductivity

  static String _shortFirmware(String fw) {
    final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(fw);
    return match != null ? 'v${match.group(1)}' : fw;
  }

  List<SensorReading> _history = [];
  bool _loading = true;

  static const _periods = [
    Duration(hours: 24),
    Duration(days: 7),
    Duration(days: 30),
  ];
  static const _periodLabels = ['24h', '7 jours', '30 jours'];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    final provider = context.read<SensorProvider>();
    _history = await provider.getHistory(
      widget.sensor.id!,
      period: _periods[_selectedPeriodIndex],
    );
    setState(() => _loading = false);
  }

  Future<void> _choosePlant() async {
    final profile = await Navigator.push<PlantProfile>(
      context,
      MaterialPageRoute(builder: (_) => const PlantSearchScreen()),
    );
    if (profile != null && mounted) {
      final provider = context.read<SensorProvider>();
      await provider.assignProfile(widget.sensor.id!, profile.id);
      await provider.loadProfiles();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          widget.sensor.plantName ?? widget.sensor.cleanName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Consumer<SensorProvider>(
            builder: (context, provider, _) {
              final isReading = provider.isReading(widget.sensor.id!);
              return IconButton(
                icon: isReading
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.refresh),
                onPressed: isReading
                    ? null
                    : () async {
                        await provider.readSensor(widget.sensor);
                        _loadHistory();
                      },
              );
            },
          ),
          PopupMenuButton<String>(
            iconColor: Colors.white,
            onSelected: (value) async {
              if (value == 'delete') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Supprimer ce capteur ?'),
                    content: Text(
                        'Le capteur "${widget.sensor.cleanName}" et tout son historique seront supprimes.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Annuler'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Supprimer'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await context
                      .read<SensorProvider>()
                      .deleteSensor(widget.sensor.id!);
                  if (mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Supprimer'),
                  ],
                ),
              ),
            ],
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
            final reading = provider.latestReadings[widget.sensor.id];
            final profile = provider.getProfile(widget.sensor.id!);

            return RefreshIndicator(
              color: Colors.white,
              backgroundColor: const Color(0xFF0288D1),
              onRefresh: () async {
                await provider.readSensor(widget.sensor);
                await _loadHistory();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // Top spacing for app bar
                    SizedBox(height: MediaQuery.of(context).padding.top + 56),

                    // Metric tab icons (like Parrot: moisture, light, temp, conductivity)
                    _buildMetricTabs(reading),
                    const SizedBox(height: 8),

                    // Status banner
                    if (profile != null && reading != null)
                      _buildStatusBanner(profile, reading),

                    // Main content based on selected tab
                    _buildTabContent(reading, profile),

                    const SizedBox(height: 16),

                    // Plant profile card
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildPlantProfileCard(profile),
                    ),

                    // Sensor info
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildSensorInfoCard(provider, reading),
                    ),

                    const SizedBox(height: 16),

                    // History section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildHistorySection(),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMetricTabs(SensorReading? reading) {
    final tabs = [
      _MetricTab(Icons.water_drop, 'Humidite', 0, reading?.moisture != null
          ? '${reading!.moisture!.toStringAsFixed(0)}%' : '--'),
      _MetricTab(Icons.light_mode, 'Lumiere', 1, reading?.light != null
          ? '${reading!.light!.toStringAsFixed(0)}' : '--'),
      _MetricTab(Icons.thermostat, 'Temp.', 2, reading?.temperature != null
          ? '${reading!.temperature!.toStringAsFixed(1)}°' : '--'),
      _MetricTab(Icons.electric_bolt, 'Engrais', 3, reading?.conductivity != null
          ? '${reading!.conductivity!.toStringAsFixed(0)}' : '--'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: tabs.map((tab) {
          final selected = _selectedTab == tab.index;
          return GestureDetector(
            onTap: () => setState(() => _selectedTab = tab.index),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.1),
                    border: Border.all(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.8)
                          : Colors.white.withValues(alpha: 0.2),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Icon(tab.icon, color: Colors.white, size: 24),
                ),
                const SizedBox(height: 4),
                Text(
                  tab.value,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: selected ? 1.0 : 0.6),
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatusBanner(PlantProfile profile, SensorReading reading) {
    // Check overall status
    int issues = 0;
    if (reading.moisture != null &&
        (reading.moisture! < profile.moistureMin ||
            reading.moisture! > profile.moistureMax)) issues++;
    if (reading.temperature != null &&
        (reading.temperature! < profile.temperatureMin ||
            reading.temperature! > profile.temperatureMax)) issues++;
    if (reading.light != null &&
        (reading.light! < profile.lightMin ||
            reading.light! > profile.lightMax)) issues++;
    if (reading.conductivity != null &&
        (reading.conductivity! < profile.conductivityMin ||
            reading.conductivity! > profile.conductivityMax)) issues++;

    final color = issues == 0
        ? const Color(0xFF4CAF50)
        : issues <= 1
            ? Colors.orange
            : Colors.red;
    final text = issues == 0
        ? 'Votre plante va bien'
        : '$issues parametre${issues > 1 ? 's' : ''} a surveiller';
    final icon = issues == 0 ? Icons.check_circle : Icons.warning;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildTabContent(SensorReading? reading, PlantProfile? profile) {
    if (reading == null) {
      return SizedBox(
        height: 300,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app, size: 48,
                  color: Colors.white.withValues(alpha: 0.5)),
              const SizedBox(height: 8),
              Text('Appuyez sur rafraichir pour lire le capteur',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7))),
            ],
          ),
        ),
      );
    }

    switch (_selectedTab) {
      case 0: // Moisture - pot visualization
        return WaterPotWidget(moisturePercent: reading.moisture);
      case 1: // Light
        return _buildMetricDisplay(
          value: reading.light,
          unit: reading.light != null ? 'lux' : '',
          label: reading.light != null
              ? 'Luminosite'
              : 'Capteur de lumiere HS',
          icon: Icons.light_mode,
          min: profile?.lightMin,
          max: profile?.lightMax,
          color: const Color(0xFFFFC107),
        );
      case 2: // Temperature
        return _buildMetricDisplay(
          value: reading.temperature,
          unit: '°C',
          label: 'Temperature',
          icon: Icons.thermostat,
          min: profile?.temperatureMin,
          max: profile?.temperatureMax,
          color: const Color(0xFFFF5722),
          soilTemp: reading.soilTemperature,
        );
      case 3: // Conductivity
        return _buildMetricDisplay(
          value: reading.conductivity,
          unit: 'uS/cm',
          label: 'Conductivite',
          icon: Icons.electric_bolt,
          min: profile?.conductivityMin,
          max: profile?.conductivityMax,
          color: const Color(0xFF9C27B0),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMetricDisplay({
    required double? value,
    required String unit,
    required String label,
    required IconData icon,
    required Color color,
    double? min,
    double? max,
    double? soilTemp,
  }) {
    return SizedBox(
      height: 300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Colors.white.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(
            value != null ? value.toStringAsFixed(value > 1000 ? 0 : 1) : '--',
            style: TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.bold,
              color: Colors.white.withValues(alpha: 0.95),
              shadows: [
                Shadow(
                    color: Colors.black.withValues(alpha: 0.2), blurRadius: 8),
              ],
            ),
          ),
          Text(
            unit,
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          if (min != null && max != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'Ideal: ${min.toStringAsFixed(0)} - ${max.toStringAsFixed(0)} $unit',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ),
          ],
          if (soilTemp != null) ...[
            const SizedBox(height: 8),
            Text(
              'Sol: ${soilTemp.toStringAsFixed(1)}°C',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Historique',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        // Period selector
        Row(
          children: List.generate(_periodLabels.length, (i) {
            final selected = _selectedPeriodIndex == i;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() => _selectedPeriodIndex = i);
                  _loadHistory();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.6)
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    _periodLabels[i],
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: selected ? 1.0 : 0.6),
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const SizedBox(
            height: 200,
            child: Center(
                child: CircularProgressIndicator(color: Colors.white)),
          )
        else ...[
          // Show chart based on selected tab
          _buildChartCard(
            _selectedTab == 0
                ? ChartMetric.moisture
                : _selectedTab == 1
                    ? ChartMetric.light
                    : _selectedTab == 2
                        ? ChartMetric.temperature
                        : ChartMetric.conductivity,
          ),
          const SizedBox(height: 12),
          // Also show other charts
          if (_selectedTab != 0) _buildChartCard(ChartMetric.moisture),
          if (_selectedTab != 0) const SizedBox(height: 12),
          if (_selectedTab != 2) _buildChartCard(ChartMetric.temperature),
          if (_selectedTab != 2) const SizedBox(height: 12),
          if (_selectedTab != 1) _buildChartCard(ChartMetric.light),
          if (_selectedTab != 1) const SizedBox(height: 12),
          if (_selectedTab != 3) _buildChartCard(ChartMetric.conductivity),
        ],
      ],
    );
  }

  Widget _buildChartCard(ChartMetric metric) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(8),
      child: HistoryChart(readings: _history, metric: metric),
    );
  }

  Future<void> _removePlant() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer la plante ?'),
        content: const Text(
          'Le profil de plante sera dissocie de ce capteur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final provider = context.read<SensorProvider>();
      await provider.assignProfile(widget.sensor.id!, null);
      setState(() {});
    }
  }

  Widget _buildPlantProfileCard(PlantProfile? profile) {
    if (profile == null) {
      return GestureDetector(
        onTap: _choosePlant,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.eco, color: Colors.white70, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Aucune plante associee',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    Text('Appuyez pour choisir',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Choisir',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56, height: 56,
                  child: profile.imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: profile.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: Colors.white.withValues(alpha: 0.1),
                            child: const Icon(Icons.eco,
                                color: Colors.white54, size: 28),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.white.withValues(alpha: 0.1),
                            child: const Icon(Icons.eco,
                                color: Colors.white54, size: 28),
                          ),
                        )
                      : Container(
                          color: Colors.white.withValues(alpha: 0.1),
                          child: const Icon(Icons.eco,
                              color: Colors.white54, size: 28),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white)),
                    if (profile.scientificName != null)
                      Text(profile.scientificName!,
                          style: TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.6))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _GlassButton(
                  label: 'Modifier',
                  icon: Icons.swap_horiz,
                  onTap: _choosePlant,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _GlassButton(
                  label: 'Retirer',
                  icon: Icons.close,
                  onTap: _removePlant,
                  isDestructive: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSensorInfoCard(SensorProvider provider, SensorReading? reading) {
    final firmwareVersion = provider.firmwareVersions[widget.sensor.id];
    final isParrot = widget.sensor.sensorType == SensorType.parrotFlowerPower;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isParrot ? Icons.sensors : Icons.bluetooth,
                  color: Colors.white70),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isParrot ? 'Parrot Flower Power' : 'Xiaomi Mi Flora',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    Text(widget.sensor.macAddress,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12)),
                    if (firmwareVersion != null)
                      Text('Firmware : ${_shortFirmware(firmwareVersion)}',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12)),
                  ],
                ),
              ),
              if (reading?.battery != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        reading!.battery! > 20
                            ? Icons.battery_full
                            : Icons.battery_alert,
                        size: 16,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Text('${reading.battery}%',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _GlassButton(
            label: provider.isFirmwareLoading(widget.sensor.id!)
                ? 'Connexion...'
                : 'Verifier firmware',
            icon: Icons.system_update,
            onTap: provider.isReading(widget.sensor.id!) ||
                    provider.isFirmwareLoading(widget.sensor.id!)
                ? null
                : () async {
                    final version =
                        await provider.readFirmwareVersion(widget.sensor);
                    if (!mounted) return;
                    final error = provider.firmwareError;
                    if (version != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Firmware : $version')),
                      );
                    } else if (error != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error)),
                      );
                    }
                  },
            small: true,
          ),
          if (isParrot)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _buildOadButton(provider),
            ),
          if (isParrot)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _buildDiagButton(provider),
            ),
          if (isParrot)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _buildResetButton(provider),
            ),
          if (!isParrot)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _GlassButton(
                label: 'Mettre a jour via Flower Care',
                icon: Icons.open_in_new,
                onTap: () async {
                  final uri = Uri.parse(
                    'https://play.google.com/store/apps/details?id=com.huahuacaocao.flowercare',
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                small: true,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOadButton(SensorProvider provider) {
    final isFlashing = provider.isOadInProgress(widget.sensor.id!);
    final progress = provider.oadProgress(widget.sensor.id!);

    if (isFlashing) {
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              color: Colors.white,
              backgroundColor: Colors.white24,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            provider.oadStatus ?? 'Flash en cours...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
            ),
          ),
          Text(
            '${(progress * 100).toStringAsFixed(1)}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    return _GlassButton(
      label: 'Flash firmware (OAD)',
      icon: Icons.system_update_alt,
      onTap: provider.isReading(widget.sensor.id!) ? null : _startOadFlash,
      small: true,
    );
  }

  Future<void> _startOadFlash() async {
    // Show warning dialog first
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Flash firmware OAD'),
        content: const Text(
          'Cette operation va mettre a jour le firmware du capteur Parrot Flower Power.\n\n'
          'Ne deconnectez pas le capteur et gardez le telephone a proximite pendant le transfert (~5 min).\n\n'
          'Choisissez le fichier .bin du firmware.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Choisir le fichier'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // Pick firmware file
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    Uint8List? bytes;

    if (file.bytes != null) {
      bytes = file.bytes!;
    } else if (file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }

    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de lire le fichier')),
        );
      }
      return;
    }

    // Validate firmware file
    if (bytes.length < 16) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fichier firmware invalide (trop petit)')),
        );
      }
      return;
    }

    // Show file info confirmation
    final sizeKb = (bytes.length / 1024).toStringAsFixed(1);
    final totalBlocks = (bytes.length / 16).ceil();
    final fileName = file.name;

    if (!mounted) return;

    final startFlash = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer le flash'),
        content: Text(
          'Fichier: $fileName\n'
          'Taille: $sizeKb KB ($totalBlocks blocs)\n\n'
          'Lancer le flash OAD ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Flasher'),
          ),
        ],
      ),
    );

    if (startFlash != true || !mounted) return;

    final provider = context.read<SensorProvider>();
    final success = await provider.flashFirmware(widget.sensor, bytes);

    if (mounted) {
      final errorMsg = provider.oadError ?? 'Echec du flash';
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Firmware flashe avec succes!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      } else {
        // Show detailed error in dialog for debugging
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Echec du flash OAD'),
            content: Text(errorMsg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Widget _buildDiagButton(SensorProvider provider) {
    final isDiag = provider.isDiagInProgress(widget.sensor.id!);

    if (isDiag) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white70,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Diagnostic en cours...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ],
      );
    }

    return _GlassButton(
      label: 'Diagnostic capteur',
      icon: Icons.troubleshoot,
      onTap: provider.isReading(widget.sensor.id!) ? null : _startDiagnostic,
      small: true,
    );
  }

  Widget _buildResetButton(SensorProvider provider) {
    final isResetting = provider.isResetInProgress(widget.sensor.id!);

    if (isResetting) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.orange,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Reinitialisation en cours...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ],
      );
    }

    return _GlassButton(
      label: 'Reinitialiser capteur',
      icon: Icons.restart_alt,
      onTap: provider.isReading(widget.sensor.id!) ? null : _startReset,
      small: true,
    );
  }

  Future<void> _startReset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reinitialiser le capteur ?'),
        content: const Text(
          'Cette operation va :\n'
          '- Nettoyer le nom BLE (supprimer les caracteres parasites)\n'
          '- Desactiver le mode live\n'
          '- Effacer le cache GATT Android\n\n'
          'Les donnees de calibration ne seront pas modifiees.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Reinitialiser'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final provider = context.read<SensorProvider>();
    final results = await provider.resetParrotSensor(widget.sensor);

    if (!mounted || results == null || results.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reinitialisation'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: results.entries.map((e) {
              final isError = e.key == 'Erreur';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        '${e.key}:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isError ? Colors.red : null,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        e.value,
                        style: TextStyle(
                          fontSize: 13,
                          color: isError ? Colors.red : null,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _startDiagnostic() async {
    final provider = context.read<SensorProvider>();
    final results = await provider.runDiagnostic(widget.sensor);

    if (!mounted || results == null || results.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Diagnostic capteur'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: results.entries.map((e) {
              final isError = e.key == 'Erreur';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        '${e.key}:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isError ? Colors.red : null,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        e.value,
                        style: TextStyle(
                          fontSize: 13,
                          color: isError ? Colors.red : null,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}

class _MetricTab {
  final IconData icon;
  final String label;
  final int index;
  final String value;
  _MetricTab(this.icon, this.label, this.index, this.value);
}

class _GlassButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDestructive;
  final bool small;

  const _GlassButton({
    required this.label,
    required this.icon,
    this.onTap,
    this.isDestructive = false,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: small ? 12 : 16, vertical: small ? 8 : 10),
        decoration: BoxDecoration(
          color: isDestructive
              ? Colors.red.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(small ? 8 : 10),
          border: Border.all(
            color: isDestructive
                ? Colors.red.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: small ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Icon(icon,
                size: small ? 14 : 16,
                color: isDestructive ? Colors.red.shade200 : Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isDestructive ? Colors.red.shade200 : Colors.white,
                fontSize: small ? 12 : 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
