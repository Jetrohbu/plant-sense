enum SensorType { parrotFlowerPower, xiaomiMiFlora }

class PlantSensor {
  final int? id;
  final String name;
  final String macAddress;
  final SensorType sensorType;
  final String? plantName;
  final int? plantProfileId;
  final DateTime createdAt;

  PlantSensor({
    this.id,
    required this.name,
    required this.macAddress,
    required this.sensorType,
    this.plantName,
    this.plantProfileId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'mac_address': macAddress,
      'sensor_type': sensorType == SensorType.parrotFlowerPower
          ? 'parrot_flower_power'
          : 'xiaomi_miflora',
      'plant_name': plantName,
      'plant_profile_id': plantProfileId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PlantSensor.fromMap(Map<String, dynamic> map) {
    return PlantSensor(
      id: map['id'] as int?,
      name: map['name'] as String,
      macAddress: map['mac_address'] as String,
      sensorType: map['sensor_type'] == 'parrot_flower_power'
          ? SensorType.parrotFlowerPower
          : SensorType.xiaomiMiFlora,
      plantName: map['plant_name'] as String?,
      plantProfileId: map['plant_profile_id'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Clean display name: strip non-ASCII garbage from BLE name
  String get cleanName {
    return name.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
  }

  PlantSensor copyWith({
    int? id,
    String? name,
    String? macAddress,
    SensorType? sensorType,
    String? plantName,
    int? plantProfileId,
    bool clearPlantProfileId = false,
  }) {
    return PlantSensor(
      id: id ?? this.id,
      name: name ?? this.name,
      macAddress: macAddress ?? this.macAddress,
      sensorType: sensorType ?? this.sensorType,
      plantName: plantName ?? this.plantName,
      plantProfileId:
          clearPlantProfileId ? null : (plantProfileId ?? this.plantProfileId),
      createdAt: createdAt,
    );
  }
}
