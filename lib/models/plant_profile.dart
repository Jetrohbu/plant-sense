enum PlantCategory {
  legume,
  fruit,
  fleur,
  aromatique,
  interieur;

  String get label {
    switch (this) {
      case PlantCategory.legume:
        return 'Légume';
      case PlantCategory.fruit:
        return 'Fruit';
      case PlantCategory.fleur:
        return 'Fleur';
      case PlantCategory.aromatique:
        return 'Aromatique';
      case PlantCategory.interieur:
        return 'Intérieur';
    }
  }
}

class PlantProfile {
  final int? id;
  final String name;
  final String? scientificName;
  final PlantCategory category;
  final String? imageUrl;
  final double temperatureMin;
  final double temperatureMax;
  final double moistureMin;
  final double moistureMax;
  final double lightMin;
  final double lightMax;
  final double conductivityMin;
  final double conductivityMax;
  final int? apiId;

  PlantProfile({
    this.id,
    required this.name,
    this.scientificName,
    required this.category,
    this.imageUrl,
    required this.temperatureMin,
    required this.temperatureMax,
    required this.moistureMin,
    required this.moistureMax,
    required this.lightMin,
    required this.lightMax,
    required this.conductivityMin,
    required this.conductivityMax,
    this.apiId,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'scientific_name': scientificName,
      'category': category.name,
      'image_url': imageUrl,
      'temperature_min': temperatureMin,
      'temperature_max': temperatureMax,
      'moisture_min': moistureMin,
      'moisture_max': moistureMax,
      'light_min': lightMin,
      'light_max': lightMax,
      'conductivity_min': conductivityMin,
      'conductivity_max': conductivityMax,
      'api_id': apiId,
    };
  }

  factory PlantProfile.fromMap(Map<String, dynamic> map) {
    return PlantProfile(
      id: map['id'] as int?,
      name: map['name'] as String,
      scientificName: map['scientific_name'] as String?,
      category: PlantCategory.values.firstWhere(
        (c) => c.name == map['category'],
        orElse: () => PlantCategory.interieur,
      ),
      imageUrl: map['image_url'] as String?,
      temperatureMin: (map['temperature_min'] as num).toDouble(),
      temperatureMax: (map['temperature_max'] as num).toDouble(),
      moistureMin: (map['moisture_min'] as num).toDouble(),
      moistureMax: (map['moisture_max'] as num).toDouble(),
      lightMin: (map['light_min'] as num).toDouble(),
      lightMax: (map['light_max'] as num).toDouble(),
      conductivityMin: (map['conductivity_min'] as num).toDouble(),
      conductivityMax: (map['conductivity_max'] as num).toDouble(),
      apiId: map['api_id'] as int?,
    );
  }

  PlantProfile copyWith({
    int? id,
    String? name,
    String? scientificName,
    PlantCategory? category,
    String? imageUrl,
    double? temperatureMin,
    double? temperatureMax,
    double? moistureMin,
    double? moistureMax,
    double? lightMin,
    double? lightMax,
    double? conductivityMin,
    double? conductivityMax,
    int? apiId,
  }) {
    return PlantProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      scientificName: scientificName ?? this.scientificName,
      category: category ?? this.category,
      imageUrl: imageUrl ?? this.imageUrl,
      temperatureMin: temperatureMin ?? this.temperatureMin,
      temperatureMax: temperatureMax ?? this.temperatureMax,
      moistureMin: moistureMin ?? this.moistureMin,
      moistureMax: moistureMax ?? this.moistureMax,
      lightMin: lightMin ?? this.lightMin,
      lightMax: lightMax ?? this.lightMax,
      conductivityMin: conductivityMin ?? this.conductivityMin,
      conductivityMax: conductivityMax ?? this.conductivityMax,
      apiId: apiId ?? this.apiId,
    );
  }
}
