import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sensor_reading.dart';

enum ChartMetric { temperature, soilTemperature, moisture, light, conductivity }

class HistoryChart extends StatelessWidget {
  final List<SensorReading> readings;
  final ChartMetric metric;

  const HistoryChart({
    super.key,
    required this.readings,
    required this.metric,
  });

  String get _title {
    switch (metric) {
      case ChartMetric.temperature:
        return 'Température air (°C)';
      case ChartMetric.soilTemperature:
        return 'Température sol (°C)';
      case ChartMetric.moisture:
        return 'Humidité (%)';
      case ChartMetric.light:
        return 'Lumière DLI (mol/m²/d)';
      case ChartMetric.conductivity:
        return 'Conductivité (µS/cm)';
    }
  }

  Color get _color {
    switch (metric) {
      case ChartMetric.temperature:
        return Colors.deepOrange;
      case ChartMetric.soilTemperature:
        return Colors.brown;
      case ChartMetric.moisture:
        return Colors.blue;
      case ChartMetric.light:
        return Colors.amber.shade700;
      case ChartMetric.conductivity:
        return Colors.teal;
    }
  }

  double? _getValue(SensorReading r) {
    switch (metric) {
      case ChartMetric.temperature:
        return r.temperature;
      case ChartMetric.soilTemperature:
        return r.soilTemperature;
      case ChartMetric.moisture:
        return r.moisture;
      case ChartMetric.light:
        return r.light;
      case ChartMetric.conductivity:
        return r.conductivity;
    }
  }

  /// Format a Y-axis value appropriately for the metric.
  String _formatValue(double value) {
    switch (metric) {
      case ChartMetric.temperature:
      case ChartMetric.soilTemperature:
        return '${value.toStringAsFixed(1)}°';
      case ChartMetric.moisture:
        return '${value.toStringAsFixed(1)}%';
      case ChartMetric.light:
        // DLI typical range 0-50 mol/m²/d
        return value.toStringAsFixed(value >= 10 ? 0 : 1);
      case ChartMetric.conductivity:
        if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
        return value.toStringAsFixed(0);
    }
  }

  /// Compute a "nice" interval for Y-axis labels (e.g. 1, 2, 5, 10, 20, 50...).
  double _niceInterval(double range, int targetTicks) {
    if (range <= 0) return 1;
    final rough = range / targetTicks;
    final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor());
    final residual = rough / magnitude;
    double nice;
    if (residual <= 1.5) {
      nice = 1;
    } else if (residual <= 3) {
      nice = 2;
    } else if (residual <= 7) {
      nice = 5;
    } else {
      nice = 10;
    }
    return nice * magnitude;
  }

  /// Snap a value down to the nearest multiple of step.
  double _floorTo(double value, double step) {
    return (value / step).floor() * step;
  }

  /// Snap a value up to the nearest multiple of step.
  double _ceilTo(double value, double step) {
    return (value / step).ceil() * step;
  }

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (final r in readings) {
      final val = _getValue(r);
      if (val != null) {
        spots.add(FlSpot(
          r.readAt.millisecondsSinceEpoch.toDouble(),
          val,
        ));
      }
    }

    if (spots.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'Pas de données pour $_title',
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final dataMinY = spots.map((s) => s.y).reduce(math.min);
    final dataMaxY = spots.map((s) => s.y).reduce(math.max);
    final range = dataMaxY - dataMinY;

    // Compute nice Y-axis bounds and interval
    const targetTicks = 4;
    final interval = _niceInterval(range == 0 ? 5 : range, targetTicks);
    var minY = _floorTo(dataMinY - interval * 0.2, interval);
    var maxY = _ceilTo(dataMaxY + interval * 0.2, interval);

    // Ensure at least 2 interior labels (edges are hidden to prevent clipping)
    if ((maxY - minY) <= interval * 1.5) {
      minY -= interval;
      maxY += interval;
    }

    // Reserved size for left labels — wider for large numbers (conductivity)
    final reservedSize = metric == ChartMetric.conductivity ? 48.0 : 44.0;

    // Time interval for X-axis
    final timeInterval = _getTimeInterval(spots);

    // Date format based on time span
    final totalMs = spots.length > 1 ? spots.last.x - spots.first.x : 0.0;
    final totalHours = totalMs / 3600000;
    final dateFormat =
        totalHours > 48 ? DateFormat('d/M') : DateFormat.Hm();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            _title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _color,
            ),
          ),
        ),
        SizedBox(
          height: 200,
          child: Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 8),
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: reservedSize,
                      interval: interval,
                      getTitlesWidget: (value, meta) {
                        // Skip labels at the very edges to avoid overlap
                        if (value == meta.min || value == meta.max) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            _formatValue(value),
                            style: const TextStyle(fontSize: 10),
                            textAlign: TextAlign.right,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: timeInterval,
                      getTitlesWidget: (value, meta) {
                        // Skip edge labels to avoid clipping
                        if (value == meta.min || value == meta.max) {
                          return const SizedBox.shrink();
                        }
                        final date = DateTime.fromMillisecondsSinceEpoch(
                            value.toInt());
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            dateFormat.format(date),
                            style: const TextStyle(fontSize: 9),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minY: minY,
                maxY: maxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.2,
                    preventCurveOverShooting: true,
                    color: _color,
                    barWidth: 2,
                    dotData: FlDotData(
                      show: spots.length < 30,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                        radius: 2,
                        color: _color,
                        strokeWidth: 0,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: _color.withValues(alpha: 0.1),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItems: (spots) => spots
                        .map((s) => LineTooltipItem(
                              '${_formatValue(s.y)}\n${DateFormat('d/M HH:mm').format(DateTime.fromMillisecondsSinceEpoch(s.x.toInt()))}',
                              TextStyle(
                                color: _color,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _getTimeInterval(List<FlSpot> spots) {
    if (spots.length < 2) return 3600000;
    final totalMs = spots.last.x - spots.first.x;
    final totalHours = totalMs / 3600000;

    // Choose interval to get ~4-6 labels, never overlapping
    if (totalHours <= 6) return 3600000; // 1h
    if (totalHours <= 24) return 4 * 3600000; // 4h
    if (totalHours <= 72) return 12 * 3600000; // 12h
    if (totalHours <= 168) return 24 * 3600000; // 1 day
    return 72 * 3600000; // 3 days
  }
}
