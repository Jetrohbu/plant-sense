import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/plant_sensor.dart';
import '../models/sensor_reading.dart';
import '../models/plant_profile.dart';
import '../providers/sensor_provider.dart';
import '../widgets/history_chart.dart';
import '../widgets/ui_helpers.dart';
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
                final provider = context.read<SensorProvider>();
                final navigator = Navigator.of(context);
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
                  await provider.deleteSensor(widget.sensor.id!);
                  if (mounted) navigator.pop();
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
        decoration: appBackgroundGradient(context),
        child: Consumer<SensorProvider>(
          builder: (context, provider, _) {
            final reading = provider.latestReadings[widget.sensor.id];
            final profile = provider.getProfile(widget.sensor.id!);

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  SizedBox(height: MediaQuery.of(context).padding.top + 8),
                  if (profile != null && reading != null)
                    _buildStatusBanner(profile, reading),
                  const SizedBox(height: 16),
                  _buildMetricTabs(reading),
                  _buildTabContent(reading, profile),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildPlantProfileCard(profile),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildSensorInfoCard(provider, reading),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildHistorySection(),
                  ),
                  const SizedBox(height: 32),
                ],
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
          ? reading!.light!.toStringAsFixed(0) : '--'),
      _MetricTab(Icons.thermostat, 'Temp.', 2, reading?.temperature != null
          ? '${reading!.temperature!.toStringAsFixed(1)}°' : '--'),
      _MetricTab(Icons.electric_bolt, 'Engrais', 3, reading?.conductivity != null
          ? reading!.conductivity!.toStringAsFixed(0) : '--'),
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
    // For each metric out of range, surface its name + direction so the user
    // knows what to fix without opening every tab.
    final issues = <String>[];
    String labelFor(String name, double v, double min, double max) =>
        v < min ? '$name basse' : '$name haute';
    if (reading.moisture != null &&
        (reading.moisture! < profile.moistureMin ||
            reading.moisture! > profile.moistureMax)) {
      issues.add(labelFor('Humidite', reading.moisture!, profile.moistureMin,
          profile.moistureMax));
    }
    if (reading.temperature != null &&
        (reading.temperature! < profile.temperatureMin ||
            reading.temperature! > profile.temperatureMax)) {
      issues.add(labelFor('Temperature', reading.temperature!,
          profile.temperatureMin, profile.temperatureMax));
    }
    if (reading.light != null &&
        (reading.light! < profile.lightMin ||
            reading.light! > profile.lightMax)) {
      issues.add(labelFor(
          'Lumiere', reading.light!, profile.lightMin, profile.lightMax));
    }
    if (reading.conductivity != null &&
        (reading.conductivity! < profile.conductivityMin ||
            reading.conductivity! > profile.conductivityMax)) {
      issues.add(labelFor('Engrais', reading.conductivity!,
          profile.conductivityMin, profile.conductivityMax));
    }

    final color = issues.isEmpty
        ? const Color(0xFF4CAF50)
        : issues.length == 1
            ? Colors.orange
            : Colors.red;
    final text = issues.isEmpty
        ? 'Votre plante va bien'
        : issues.length == 1
            ? issues.first
            : issues.join(' • ');
    final icon = issues.isEmpty ? Icons.check_circle : Icons.warning;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
    final isReading = provider.isReading(widget.sensor.id!);
    final isReadingFw = provider.isFirmwareLoading(widget.sensor.id!);
    final busy = isReading || isReadingFw;

    final fwLabel = isReadingFw
        ? 'Connexion...'
        : (firmwareVersion != null
            ? 'Firmware : ${_shortFirmware(firmwareVersion)}'
            : 'Verifier firmware');

    final actions = <_ActionItem>[
      _ActionItem(
        icon: Icons.system_update,
        label: fwLabel,
        isLoading: isReadingFw,
        onTap: busy
            ? null
            : () async {
                final version = await _runWithLoading<String?>(
                  title: 'Lecture du firmware',
                  task: () => provider.readFirmwareVersion(widget.sensor),
                );
                if (!mounted) return;
                final error = provider.firmwareError;
                if (version != null) {
                  _showReport(
                    title: 'Firmware',
                    headerIcon: Icons.system_update,
                    accent: const Color(0xFF22C55E),
                    rows: {'Version': version},
                  );
                } else if (error != null) {
                  _showReport(
                    title: 'Firmware',
                    headerIcon: Icons.error_outline,
                    accent: const Color(0xFFEF4444),
                    rows: {'Erreur': error},
                  );
                }
              },
      ),
      if (isParrot)
        _ActionItem(
          icon: Icons.fact_check_outlined,
          label: 'Diagnostic',
          onTap: isReading ? null : _startDiagnostic,
        ),
      if (isParrot)
        _ActionItem(
          icon: Icons.restart_alt,
          label: 'Reinitialiser',
          isDestructive: true,
          onTap: isReading ? null : _startReset,
        ),
      if (!isParrot)
        _ActionItem(
          icon: Icons.open_in_new,
          label: 'Mettre a jour (Flower Care)',
          onTap: () async {
            final uri = Uri.parse(
              'https://play.google.com/store/apps/details?id=com.huahuacaocao.flowercare',
            );
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(isParrot ? Icons.sensors : Icons.bluetooth,
                  color: Colors.white70, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isParrot ? 'Parrot Flower Power' : 'Xiaomi Mi Flora',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
              ),
              if (reading?.battery != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                        color: reading.battery! > 20
                            ? Colors.greenAccent.shade100
                            : Colors.redAccent.shade100,
                      ),
                      const SizedBox(width: 4),
                      Text('${reading.battery}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          )),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _DropdownActionsMenu(
            label: 'Actions',
            icon: Icons.tune,
            items: actions,
          ),
        ],
      ),
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
    final results = await _runWithLoading<Map<String, String>?>(
      title: 'Reinitialisation',
      subtitle: 'Nettoyage du nom BLE, mode live, cache GATT',
      task: () => provider.resetParrotSensor(widget.sensor),
    );

    if (!mounted || results == null || results.isEmpty) return;

    final hasError = results.keys.any((k) => k == 'Erreur');
    _showReport(
      title: 'Reinitialisation',
      headerIcon: hasError ? Icons.warning_amber : Icons.check_circle_outline,
      accent:
          hasError ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
      rows: results,
    );
  }

  Future<void> _startDiagnostic() async {
    final provider = context.read<SensorProvider>();
    final results = await _runWithLoading<Map<String, String>?>(
      title: 'Diagnostic en cours',
      subtitle: 'Lecture des registres du capteur',
      task: () => provider.runDiagnostic(widget.sensor),
    );

    if (!mounted || results == null || results.isEmpty) return;

    final hasError = results.keys.any((k) => k == 'Erreur');
    _showReport(
      title: 'Diagnostic capteur',
      headerIcon: hasError ? Icons.warning_amber : Icons.fact_check_outlined,
      accent:
          hasError ? const Color(0xFFEF4444) : const Color(0xFF06B6D4),
      rows: results,
    );
  }

  /// Show a non-dismissable animated loading dialog while [task] runs,
  /// dismiss it once the task settles, and forward the task's result.
  Future<R?> _runWithLoading<R>({
    required String title,
    String? subtitle,
    required Future<R> Function() task,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => _AnimatedLoadingDialog(title: title, subtitle: subtitle),
    );
    R? result;
    try {
      result = await task();
    } finally {
      if (mounted && navigator.canPop()) navigator.pop();
    }
    return result;
  }

  Future<void> _showReport({
    required String title,
    required IconData headerIcon,
    required Color accent,
    required Map<String, String> rows,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _ReportDialog(
        title: title,
        headerIcon: headerIcon,
        accent: accent,
        rows: rows,
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

class _ActionItem {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;
  final bool isLoading;

  const _ActionItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.isDestructive = false,
    this.isLoading = false,
  });
}

/// Dropdown actions menu — single button that toggles a list below it.
/// Visual style adapted from a profile dropdown UI: dark navy surface,
/// chevron rotates on open, items slide in.
class _DropdownActionsMenu extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<_ActionItem> items;

  const _DropdownActionsMenu({
    required this.label,
    required this.icon,
    required this.items,
  });

  @override
  State<_DropdownActionsMenu> createState() => _DropdownActionsMenuState();
}

class _DropdownActionsMenuState extends State<_DropdownActionsMenu> {
  static const _navy = Color(0xFF1C2230);
  static const _navyHover = Color(0xFF2A3142);
  static const _accent = Color(0xFF3B82F6);

  bool _open = false;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: _open ? _navyHover : _navy,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _toggle,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(widget.icon, color: Colors.white70, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 250),
                    turns: _open ? 0.5 : 0.0,
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.white70,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !_open
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _navy,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < widget.items.length; i++)
                          Padding(
                            padding: EdgeInsets.only(
                                bottom:
                                    i == widget.items.length - 1 ? 0 : 4),
                            child: _DropdownItem(
                              item: widget.items[i],
                              index: i,
                              accent: _accent,
                              onAfterTap: () =>
                                  setState(() => _open = false),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _DropdownItem extends StatefulWidget {
  final _ActionItem item;
  final int index;
  final Color accent;
  final VoidCallback onAfterTap;

  const _DropdownItem({
    required this.item,
    required this.index,
    required this.accent,
    required this.onAfterTap,
  });

  @override
  State<_DropdownItem> createState() => _DropdownItemState();
}

class _DropdownItemState extends State<_DropdownItem> {
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + widget.index * 50),
      curve: Curves.easeOut,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(-6 * (1 - t), 0),
          child: child,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: widget.accent.withValues(alpha: 0.15),
          splashColor: widget.accent.withValues(alpha: 0.18),
          onTap: item.onTap == null
              ? null
              : () {
                  widget.onAfterTap();
                  item.onTap!();
                },
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (item.isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  )
                else
                  Icon(
                    item.icon,
                    size: 18,
                    color: item.onTap == null
                        ? Colors.white38
                        : (item.isDestructive
                            ? Colors.redAccent.shade100
                            : Colors.white70),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: item.onTap == null
                          ? Colors.white38
                          : (item.isDestructive
                              ? Colors.redAccent.shade100
                              : Colors.white),
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal loading dialog with a custom rotating arc + pulsing icon.
/// Used while a BLE action (firmware read, diagnostic, reset) is running.
class _AnimatedLoadingDialog extends StatefulWidget {
  final String title;
  final String? subtitle;

  const _AnimatedLoadingDialog({required this.title, this.subtitle});

  @override
  State<_AnimatedLoadingDialog> createState() => _AnimatedLoadingDialogState();
}

class _AnimatedLoadingDialogState extends State<_AnimatedLoadingDialog>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _pulse;
  late final AnimationController _dots;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    _dots = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C2230),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 88,
                height: 88,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _spin,
                      builder: (_, __) => Transform.rotate(
                        angle: _spin.value * 2 * pi,
                        child: const CustomPaint(
                          size: Size(88, 88),
                          painter: _SpinnerArcPainter(),
                        ),
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, __) => Transform.scale(
                        scale: 0.92 + 0.08 * _pulse.value,
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF23F0FF)
                                .withValues(alpha: 0.12),
                          ),
                          child: const Icon(
                            Icons.local_florist,
                            color: Color(0xFFA7FFEE),
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              AnimatedBuilder(
                animation: _dots,
                builder: (_, __) {
                  final n = (_dots.value * 3).floor() % 3 + 1;
                  return Text(
                    '${widget.title}${'.' * n}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  widget.subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SpinnerArcPainter extends CustomPainter {
  const _SpinnerArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 4;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Faint background ring
    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, bgPaint);

    // Foreground rotating arc with cyan sweep gradient
    final arcPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * pi,
        colors: const [
          Color(0x0023F0FF),
          Color(0xFFA7FFEE),
          Color(0xFF23F0FF),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -pi / 2, pi * 1.4, false, arcPaint);
  }

  @override
  bool shouldRepaint(_SpinnerArcPainter old) => false;
}

/// Pretty result dialog for diagnostic / reset / firmware.
/// Header with colored icon, list of label/value rows with optional
/// status icons, scale-in entrance animation, single Close action.
class _ReportDialog extends StatelessWidget {
  final String title;
  final IconData headerIcon;
  final Color accent;
  final Map<String, String> rows;

  const _ReportDialog({
    required this.title,
    required this.headerIcon,
    required this.accent,
    required this.rows,
  });

  bool _rowIsError(String key, String value) {
    if (key.toLowerCase() == 'erreur') return true;
    final v = value.toLowerCase();
    return v.contains('erreur') ||
        v.contains('echec') ||
        v.contains('échec') ||
        v.startsWith('❌');
  }

  @override
  Widget build(BuildContext context) {
    final entries = rows.entries.toList();
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1C2230),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: accent.withValues(alpha: 0.45),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(headerIcon, color: accent, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Rows
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(entries.length, (i) {
                        final e = entries[i];
                        final isError = _rowIsError(e.key, e.value);
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: Duration(milliseconds: 260 + i * 50),
                          curve: Curves.easeOut,
                          builder: (_, t, child) => Opacity(
                            opacity: t,
                            child: Transform.translate(
                              offset: Offset(-8 * (1 - t), 0),
                              child: child,
                            ),
                          ),
                          child: _ReportRow(
                            label: e.key,
                            value: e.value,
                            isError: isError,
                            isLast: i == entries.length - 1,
                          ),
                        );
                      }),
                    ),
                  ),
                ),

                // Footer
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Fermer',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isError;
  final bool isLast;

  const _ReportRow({
    required this.label,
    required this.value,
    required this.isError,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFFCA5A5) : Colors.white;
    final muted = isError
        ? const Color(0xFFFCA5A5)
        : Colors.white.withValues(alpha: 0.55);
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isError
              ? const Color(0xFFEF4444).withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: isError ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
