class SensorReading {
  final int? id;
  final int sensorId;
  final double? temperature;
  final double? soilTemperature;
  final double? moisture;
  final double? light;
  final double? conductivity;
  final int? battery;
  final DateTime readAt;

  SensorReading({
    this.id,
    required this.sensorId,
    this.temperature,
    this.soilTemperature,
    this.moisture,
    this.light,
    this.conductivity,
    this.battery,
    DateTime? readAt,
  }) : readAt = readAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'sensor_id': sensorId,
      'temperature': temperature,
      'soil_temperature': soilTemperature,
      'moisture': moisture,
      'light': light,
      'conductivity': conductivity,
      'battery': battery,
      'read_at': readAt.toIso8601String(),
    };
  }

  factory SensorReading.fromMap(Map<String, dynamic> map) {
    return SensorReading(
      id: map['id'] as int?,
      sensorId: map['sensor_id'] as int,
      temperature: map['temperature'] as double?,
      soilTemperature: map['soil_temperature'] as double?,
      moisture: map['moisture'] as double?,
      light: map['light'] as double?,
      conductivity: map['conductivity'] as double?,
      battery: map['battery'] as int?,
      readAt: DateTime.parse(map['read_at'] as String),
    );
  }
}
