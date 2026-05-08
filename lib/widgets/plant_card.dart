import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/plant_sensor.dart';
import '../models/sensor_reading.dart';
import '../models/plant_profile.dart';
import 'ui_helpers.dart';

class PlantCard extends StatelessWidget {
  final PlantSensor sensor;
  final SensorReading? latestReading;
  final PlantProfile? plantProfile;
  final List<String> outOfRangeParams;
  final bool isReading;
  final VoidCallback onTap;
  final VoidCallback onRefresh;

  const PlantCard({
    super.key,
    required this.sensor,
    this.latestReading,
    this.plantProfile,
    this.outOfRangeParams = const [],
    this.isReading = false,
    required this.onTap,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final reading = latestReading;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                // Plant photo with a status ring summarising health.
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: statusDotColor(outOfRangeParams.length),
                      width: 2.5,
                    ),
                  ),
                  child: ClipOval(
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: plantProfile?.imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: plantProfile!.imageUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: Colors.white.withValues(alpha: 0.2),
                                child: const Icon(Icons.local_florist,
                                    color: Colors.white70, size: 28),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: Colors.white.withValues(alpha: 0.2),
                                child: const Icon(Icons.local_florist,
                                    color: Colors.white70, size: 28),
                              ),
                            )
                          : Container(
                              color: Colors.white.withValues(alpha: 0.2),
                              child: Icon(_plantIcon(),
                                  color: Colors.white70, size: 28),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Name + sync time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sensor.plantName ?? sensor.cleanName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      if (reading != null)
                        Text(
                          'Derniere synchro ${_timeAgo(reading.readAt)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        )
                      else
                        Text(
                          'Aucune donnee',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      const SizedBox(height: 6),
                      // Status indicator icons
                      if (reading != null)
                        Row(
                          children: [
                            _StatusDot(
                              icon: Icons.water_drop,
                              color: _getParamStatusColor(
                                  reading.moisture, 'moisture'),
                            ),
                            const SizedBox(width: 8),
                            _StatusDot(
                              icon: Icons.light_mode,
                              color: _getParamStatusColor(
                                  reading.light, 'light'),
                            ),
                            const SizedBox(width: 8),
                            _StatusDot(
                              icon: Icons.thermostat,
                              color: _getParamStatusColor(
                                  reading.temperature, 'temperature'),
                            ),
                            const SizedBox(width: 8),
                            _StatusDot(
                              icon: Icons.electric_bolt,
                              color: _getParamStatusColor(
                                  reading.conductivity, 'conductivity'),
                            ),
                            if (reading.battery != null) ...[
                              const Spacer(),
                              Icon(
                                reading.battery! > 20
                                    ? Icons.battery_full
                                    : Icons.battery_alert,
                                size: 16,
                                color: reading.battery! > 20
                                    ? Colors.white70
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${reading.battery}%',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),

                // Refresh or loading
                if (isReading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  )
                else
                  Icon(Icons.chevron_right,
                      color: Colors.white.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getParamStatusColor(double? value, String param) {
    if (value == null) return Colors.grey;
    if (plantProfile == null) return const Color(0xFF4CAF50);

    double min, max;
    switch (param) {
      case 'moisture':
        min = plantProfile!.moistureMin;
        max = plantProfile!.moistureMax;
        break;
      case 'temperature':
        min = plantProfile!.temperatureMin;
        max = plantProfile!.temperatureMax;
        break;
      case 'light':
        min = plantProfile!.lightMin;
        max = plantProfile!.lightMax;
        break;
      case 'conductivity':
        min = plantProfile!.conductivityMin;
        max = plantProfile!.conductivityMax;
        break;
      default:
        return Colors.grey;
    }

    if (value < min) return Colors.red;
    if (value > max) return Colors.orange;
    return const Color(0xFF4CAF50);
  }

  IconData _plantIcon() {
    if (plantProfile != null) {
      switch (plantProfile!.category) {
        case PlantCategory.legume:
          return Icons.grass;
        case PlantCategory.fruit:
          return Icons.apple;
        case PlantCategory.fleur:
          return Icons.local_florist;
        case PlantCategory.aromatique:
          return Icons.spa;
        case PlantCategory.interieur:
          return Icons.yard;
      }
    }
    return Icons.eco;
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return "a l'instant";
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours}h';
    return 'il y a ${diff.inDays}j';
  }
}

class _StatusDot extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _StatusDot({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.3),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 13, color: color == Colors.grey
          ? Colors.grey
          : color == Colors.red || color == Colors.orange
              ? color
              : Colors.white),
    );
  }
}
