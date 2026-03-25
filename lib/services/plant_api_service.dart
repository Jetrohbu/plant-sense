import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/plant_profile.dart';
import '../models/api_provider.dart';

/// Abstract base for all plant API services.
abstract class PlantApiService {
  Future<List<PlantProfile>> searchPlants(String query);
  Future<PlantProfile?> getPlantDetails(int id);
  Future<String?> fetchImageUrl(String query);

  /// Factory: returns the right implementation based on provider type.
  factory PlantApiService.fromProvider(ApiProvider provider) {
    switch (provider.type) {
      case 'trefle':
        return TrefleApiService(
          baseUrl: provider.baseUrl,
          apiKey: provider.apiKey,
        );
      case 'perenual':
      default:
        return PerenualApiService(
          baseUrl: provider.baseUrl,
          apiKey: provider.apiKey,
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Perenual
// ---------------------------------------------------------------------------

class PerenualApiService implements PlantApiService {
  final String _baseUrl;
  final String _apiKey;

  PerenualApiService({required String baseUrl, required String apiKey})
      : _baseUrl = baseUrl,
        _apiKey = apiKey;

  @override
  Future<List<PlantProfile>> searchPlants(String query) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/species-list?key=$_apiKey&q=${Uri.encodeComponent(query)}',
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'] as List<dynamic>? ?? [];

      return data.map((item) => _mapSearchResult(item)).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<PlantProfile?> getPlantDetails(int id) async {
    try {
      final uri = Uri.parse('$_baseUrl/species/details/$id?key=$_apiKey');
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _mapDetailResult(json);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> fetchImageUrl(String query) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/species-list?key=$_apiKey&q=${Uri.encodeComponent(query)}',
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'] as List<dynamic>? ?? [];
      if (data.isEmpty) return null;

      return _extractImageUrl(data.first['default_image']);
    } catch (_) {
      return null;
    }
  }

  PlantProfile _mapSearchResult(Map<String, dynamic> item) {
    final commonNames = item['common_name'] as String? ?? 'Inconnu';
    final scientificName =
        (item['scientific_name'] as List<dynamic>?)?.firstOrNull as String?;
    final imageUrl = _extractImageUrl(item['default_image']);
    final apiId = item['id'] as int?;

    return PlantProfile(
      name: commonNames,
      scientificName: scientificName,
      category: PlantCategory.interieur,
      imageUrl: imageUrl,
      temperatureMin: 15,
      temperatureMax: 30,
      moistureMin: 30,
      moistureMax: 60,
      lightMin: 5000,
      lightMax: 30000,
      conductivityMin: 100,
      conductivityMax: 350,
      apiId: apiId,
    );
  }

  PlantProfile _mapDetailResult(Map<String, dynamic> json) {
    final commonName = json['common_name'] as String? ?? 'Inconnu';
    final scientificName =
        (json['scientific_name'] as List<dynamic>?)?.firstOrNull as String?;
    final imageUrl = _extractImageUrl(json['default_image']);
    final apiId = json['id'] as int?;

    final watering = (json['watering'] as String? ?? '').toLowerCase();
    double moistureMin = 30, moistureMax = 60;
    if (watering.contains('frequent')) {
      moistureMin = 50;
      moistureMax = 80;
    } else if (watering.contains('average') ||
        watering.contains('moderate')) {
      moistureMin = 30;
      moistureMax = 60;
    } else if (watering.contains('minimum') || watering.contains('none')) {
      moistureMin = 10;
      moistureMax = 35;
    }

    final sunlight = json['sunlight'] as List<dynamic>? ?? [];
    final sunText = sunlight.join(' ').toLowerCase();
    double lightMin = 5000, lightMax = 30000;
    if (sunText.contains('full sun')) {
      lightMin = 25000;
      lightMax = 80000;
    } else if (sunText.contains('part shade') ||
        sunText.contains('part sun')) {
      lightMin = 10000;
      lightMax = 40000;
    } else if (sunText.contains('full shade')) {
      lightMin = 1000;
      lightMax = 10000;
    }

    final hardiness = json['hardiness'] as Map<String, dynamic>?;
    double tempMin = 15, tempMax = 30;
    if (hardiness != null) {
      final minZone =
          int.tryParse(hardiness['min']?.toString() ?? '') ?? 7;
      tempMin = _zoneToMinTemp(minZone);
      tempMax = 35;
    }

    final type = (json['type'] as String? ?? '').toLowerCase();
    PlantCategory category = PlantCategory.interieur;
    if (type.contains('herb')) {
      category = PlantCategory.aromatique;
    } else if (type.contains('tree') || type.contains('fruit')) {
      category = PlantCategory.fruit;
    } else if (type.contains('flower')) {
      category = PlantCategory.fleur;
    } else if (type.contains('vegetable')) {
      category = PlantCategory.legume;
    }

    return PlantProfile(
      name: commonName,
      scientificName: scientificName,
      category: category,
      imageUrl: imageUrl,
      temperatureMin: tempMin,
      temperatureMax: tempMax,
      moistureMin: moistureMin,
      moistureMax: moistureMax,
      lightMin: lightMin,
      lightMax: lightMax,
      conductivityMin: 100,
      conductivityMax: 350,
      apiId: apiId,
    );
  }

  String? _extractImageUrl(dynamic imageData) {
    if (imageData == null || imageData is! Map<String, dynamic>) return null;
    return imageData['regular_url'] as String? ??
        imageData['medium_url'] as String? ??
        imageData['small_url'] as String? ??
        imageData['thumbnail'] as String?;
  }

  double _zoneToMinTemp(int zone) {
    const zoneTemps = {
      1: -51.0, 2: -45.0, 3: -40.0, 4: -34.0, 5: -29.0,
      6: -23.0, 7: -18.0, 8: -12.0, 9: -7.0, 10: -1.0,
      11: 4.0, 12: 10.0, 13: 15.0,
    };
    return zoneTemps[zone] ?? 5.0;
  }
}

// ---------------------------------------------------------------------------
// Trefle.io
// ---------------------------------------------------------------------------

class TrefleApiService implements PlantApiService {
  final String _baseUrl;
  final String _apiKey;

  TrefleApiService({required String baseUrl, required String apiKey})
      : _baseUrl = baseUrl,
        _apiKey = apiKey;

  @override
  Future<List<PlantProfile>> searchPlants(String query) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/plants/search?token=$_apiKey&q=${Uri.encodeComponent(query)}',
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'] as List<dynamic>? ?? [];

      return data.map((item) => _mapSearchResult(item)).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<PlantProfile?> getPlantDetails(int id) async {
    try {
      final uri = Uri.parse('$_baseUrl/plants/$id?token=$_apiKey');
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>? ?? {};
      return _mapDetailResult(data);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> fetchImageUrl(String query) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/plants/search?token=$_apiKey&q=${Uri.encodeComponent(query)}',
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'] as List<dynamic>? ?? [];
      if (data.isEmpty) return null;

      return data.first['image_url'] as String?;
    } catch (_) {
      return null;
    }
  }

  PlantProfile _mapSearchResult(Map<String, dynamic> item) {
    final commonName = item['common_name'] as String? ??
        item['scientific_name'] as String? ??
        'Inconnu';
    final scientificName = item['scientific_name'] as String?;
    final imageUrl = item['image_url'] as String?;
    final apiId = item['id'] as int?;

    return PlantProfile(
      name: commonName,
      scientificName: scientificName,
      category: PlantCategory.interieur,
      imageUrl: imageUrl,
      temperatureMin: 15,
      temperatureMax: 30,
      moistureMin: 30,
      moistureMax: 60,
      lightMin: 5000,
      lightMax: 30000,
      conductivityMin: 100,
      conductivityMax: 350,
      apiId: apiId,
    );
  }

  PlantProfile _mapDetailResult(Map<String, dynamic> json) {
    final commonName = json['common_name'] as String? ??
        json['scientific_name'] as String? ??
        'Inconnu';
    final scientificName = json['scientific_name'] as String?;
    final imageUrl = json['image_url'] as String?;
    final apiId = json['id'] as int?;

    // Main species data
    final mainSpecies =
        json['main_species'] as Map<String, dynamic>? ?? json;

    // Growth data
    final growth = mainSpecies['growth'] as Map<String, dynamic>? ?? {};

    // Temperature from growth
    final tempMinC = growth['minimum_temperature'] as Map<String, dynamic>?;
    final tempMaxC = growth['maximum_temperature'] as Map<String, dynamic>?;
    double tempMin = 15, tempMax = 30;
    if (tempMinC != null && tempMinC['deg_c'] != null) {
      tempMin = (tempMinC['deg_c'] as num).toDouble();
    }
    if (tempMaxC != null && tempMaxC['deg_c'] != null) {
      tempMax = (tempMaxC['deg_c'] as num).toDouble();
    }

    // Light from growth (0-10 scale → lux)
    final light = growth['light'] as int?;
    double lightMin = 5000, lightMax = 30000;
    if (light != null) {
      lightMin = (light * 8000).toDouble();
      lightMax = ((light + 2).clamp(0, 10) * 10000).toDouble();
    }

    // Atmospheric humidity → soil moisture approximation
    final humidity = growth['atmospheric_humidity'] as int?;
    double moistureMin = 30, moistureMax = 60;
    if (humidity != null) {
      moistureMin = (humidity * 8).toDouble().clamp(10, 80);
      moistureMax = ((humidity + 2) * 10).toDouble().clamp(30, 95);
    }

    // Soil nutriments → conductivity
    final nutriments = growth['soil_nutriments'] as int?;
    double condMin = 100, condMax = 350;
    if (nutriments != null) {
      condMin = (nutriments * 50).toDouble().clamp(50, 500);
      condMax = ((nutriments + 2) * 80).toDouble().clamp(150, 800);
    }

    // Category from family
    final family = (json['family_common_name'] as String? ?? '').toLowerCase();
    final genus = (json['genus'] as Map<String, dynamic>?)?['name'] as String? ?? '';
    PlantCategory category = PlantCategory.interieur;
    if (family.contains('mint') ||
        family.contains('lami') ||
        genus.toLowerCase().contains('mentha') ||
        genus.toLowerCase().contains('ocimum') ||
        genus.toLowerCase().contains('rosmarinus')) {
      category = PlantCategory.aromatique;
    } else if (family.contains('rose') || family.contains('daisy') ||
        family.contains('aster')) {
      category = PlantCategory.fleur;
    }

    return PlantProfile(
      name: commonName,
      scientificName: scientificName,
      category: category,
      imageUrl: imageUrl,
      temperatureMin: tempMin,
      temperatureMax: tempMax,
      moistureMin: moistureMin,
      moistureMax: moistureMax,
      lightMin: lightMin,
      lightMax: lightMax,
      conductivityMin: condMin,
      conductivityMax: condMax,
      apiId: apiId,
    );
  }
}
