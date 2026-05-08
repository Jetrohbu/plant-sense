import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/plant_sensor.dart';
import '../models/sensor_reading.dart';
import '../models/plant_profile.dart';
import '../models/api_provider.dart';
import '../services/database_service.dart';
import '../services/ble_service.dart';
import '../services/plant_api_service.dart';
import '../services/parrot_oad_service.dart';
import '../services/parrot_protocol.dart';

class SensorProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final BleService _ble = BleService();

  List<PlantSensor> _sensors = [];
  List<PlantSensor> get sensors => _sensors;

  final Map<int, SensorReading?> _latestReadings = {};
  Map<int, SensorReading?> get latestReadings => _latestReadings;

  final Map<int, bool> _readingInProgress = {};
  bool isReading(int sensorId) => _readingInProgress[sensorId] ?? false;

  final Map<int, String?> _firmwareVersions = {};
  Map<int, String?> get firmwareVersions => _firmwareVersions;

  final Map<int, bool> _firmwareLoading = {};
  bool isFirmwareLoading(int sensorId) => _firmwareLoading[sensorId] ?? false;

  String? _firmwareError;
  String? get firmwareError => _firmwareError;

  bool _isRefreshingAll = false;
  bool get isRefreshingAll => _isRefreshingAll;

  List<String> _errors = [];
  String? get lastError => _errors.isNotEmpty ? _errors.join('\n') : null;

  // Plant profiles
  Map<int, PlantProfile> _plantProfiles = {};
  Map<int, PlantProfile> get plantProfiles => _plantProfiles;

  // API providers
  List<ApiProvider> _apiProviders = [];
  List<ApiProvider> get apiProviders => _apiProviders;

  bool _imageEnrichmentRunning = false;

  // OAD firmware flash state
  final Map<int, bool> _oadInProgress = {};
  bool isOadInProgress(int sensorId) => _oadInProgress[sensorId] ?? false;

  final Map<int, double> _oadProgress = {};
  double oadProgress(int sensorId) => _oadProgress[sensorId] ?? 0.0;

  String? _oadStatus;
  String? get oadStatus => _oadStatus;

  String? _oadError;
  String? get oadError => _oadError;

  void clearErrors() {
    _errors = [];
    notifyListeners();
  }

  Future<void> loadSensors() async {
    // Clean up any corrupted readings from previous bugs
    await _db.sanitizeReadings();
    _sensors = await _db.getAllSensors();
    for (final sensor in _sensors) {
      if (sensor.id != null) {
        _latestReadings[sensor.id!] = await _db.getLatestReading(sensor.id!);
      }
    }
    await loadProfiles();
    await loadApiProviders();
    notifyListeners();

    // Enrich images in background (retry each launch if some are missing)
    if (!_imageEnrichmentRunning) {
      final hasUnenriched = _plantProfiles.values.any((p) => p.imageUrl == null);
      if (hasUnenriched) {
        _imageEnrichmentRunning = true;
        _enrichProfileImages().whenComplete(() {
          _imageEnrichmentRunning = false;
        });
      }
    }
  }

  Future<void> loadProfiles() async {
    final profiles = await _db.getAllPlantProfiles();
    _plantProfiles = {
      for (final p in profiles)
        if (p.id != null) p.id!: p,
    };
  }

  Future<void> loadApiProviders() async {
    _apiProviders = await _db.getAllApiProviders();
  }

  List<PlantApiService> _getAllApiServices() {
    return _apiProviders
        .where((p) => p.enabled && p.apiKey.isNotEmpty)
        .map((p) => PlantApiService.fromProvider(p))
        .toList();
  }

  Future<void> addApiProvider(ApiProvider provider) async {
    final id = await _db.insertApiProvider(provider);
    _apiProviders.add(provider.copyWith(id: id));
    notifyListeners();
  }

  Future<void> updateApiProvider(ApiProvider provider) async {
    await _db.updateApiProvider(provider);
    final index = _apiProviders.indexWhere((p) => p.id == provider.id);
    if (index >= 0) _apiProviders[index] = provider;
    notifyListeners();
  }

  Future<void> deleteApiProvider(int id) async {
    await _db.deleteApiProvider(id);
    _apiProviders.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  Future<void> toggleApiProvider(int id, bool enabled) async {
    final index = _apiProviders.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final updated = _apiProviders[index].copyWith(enabled: enabled);
    await _db.updateApiProvider(updated);
    _apiProviders[index] = updated;
    notifyListeners();
  }

  /// Background: fetch images from all active APIs for profiles that have none.
  Future<void> _enrichProfileImages() async {
    final apis = _getAllApiServices();
    if (apis.isEmpty) return;

    final toEnrich = _plantProfiles.values
        .where((p) => p.imageUrl == null && p.id != null)
        .toList();

    if (toEnrich.isEmpty) return;

    for (final profile in toEnrich) {
      String? imageUrl;

      // Try each active provider until we get an image
      for (final api in apis) {
        try {
          // Try scientific name first, then common name
          imageUrl = await api.fetchImageUrl(
              profile.scientificName ?? profile.name);
          if (imageUrl != null) break;

          // If scientific name gave nothing, try common name
          if (profile.scientificName != null) {
            imageUrl = await api.fetchImageUrl(profile.name);
            if (imageUrl != null) break;
          }
        } catch (_) {
          // Try next provider
        }
      }

      if (imageUrl != null) {
        final updated = profile.copyWith(imageUrl: imageUrl);
        await _db.updatePlantProfile(updated);
        _plantProfiles[profile.id!] = updated;
        notifyListeners();
      }

      // Rate-limit: 300ms between plants
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  PlantProfile? getProfile(int sensorId) {
    final sensor = _sensors.firstWhere(
      (s) => s.id == sensorId,
      orElse: () => PlantSensor(
        name: '',
        macAddress: '',
        sensorType: SensorType.xiaomiMiFlora,
      ),
    );
    if (sensor.plantProfileId == null) return null;
    return _plantProfiles[sensor.plantProfileId];
  }

  Future<void> assignProfile(int sensorId, int? profileId) async {
    final index = _sensors.indexWhere((s) => s.id == sensorId);
    if (index < 0) return;

    final updated = profileId == null
        ? _sensors[index].copyWith(clearPlantProfileId: true)
        : _sensors[index].copyWith(plantProfileId: profileId);
    await _db.updateSensor(updated);
    _sensors[index] = updated;
    notifyListeners();
  }

  /// Returns list of parameter names that are out of the plant profile range.
  List<String> getOutOfRangeParams(int sensorId) {
    final reading = _latestReadings[sensorId];
    final profile = getProfile(sensorId);
    if (reading == null || profile == null) return [];
    return outOfRangeParams(reading, profile);
  }

  static List<String> outOfRangeParams(
      SensorReading reading, PlantProfile profile) {
    final out = <String>[];
    if (reading.temperature != null) {
      if (reading.temperature! < profile.temperatureMin ||
          reading.temperature! > profile.temperatureMax) {
        out.add('temperature');
      }
    }
    if (reading.moisture != null) {
      if (reading.moisture! < profile.moistureMin ||
          reading.moisture! > profile.moistureMax) {
        out.add('moisture');
      }
    }
    if (reading.light != null) {
      if (reading.light! < profile.lightMin ||
          reading.light! > profile.lightMax) {
        out.add('light');
      }
    }
    if (reading.conductivity != null) {
      if (reading.conductivity! < profile.conductivityMin ||
          reading.conductivity! > profile.conductivityMax) {
        out.add('conductivity');
      }
    }
    return out;
  }

  Future<PlantSensor> addSensor(PlantSensor sensor) async {
    final id = await _db.insertSensor(sensor);
    final saved = sensor.copyWith(id: id);
    _sensors.add(saved);
    notifyListeners();
    return saved;
  }

  Future<void> updateSensor(PlantSensor sensor) async {
    await _db.updateSensor(sensor);
    final index = _sensors.indexWhere((s) => s.id == sensor.id);
    if (index >= 0) {
      _sensors[index] = sensor;
    }
    notifyListeners();
  }

  Future<void> deleteSensor(int id) async {
    await _db.deleteSensor(id);
    _sensors.removeWhere((s) => s.id == id);
    _latestReadings.remove(id);
    notifyListeners();
  }

  Future<String?> readFirmwareVersion(PlantSensor sensor) async {
    if (sensor.id == null) return null;
    // Don't start firmware read if a sensor read is already in progress
    if (_readingInProgress[sensor.id!] == true) {
      _firmwareError = 'Lecture capteur en cours, réessayez après';
      notifyListeners();
      return null;
    }
    _firmwareLoading[sensor.id!] = true;
    _firmwareError = null;
    notifyListeners();

    try {
      final version = await _ble.readFirmwareVersion(sensor);
      _firmwareVersions[sensor.id!] = version;
      if (version == null) {
        _firmwareError = 'Service firmware non trouvé sur ce capteur';
      }
      _firmwareLoading[sensor.id!] = false;
      notifyListeners();
      return version;
    } catch (e) {
      _firmwareError = 'Erreur lecture firmware : $e';
      _firmwareLoading[sensor.id!] = false;
      notifyListeners();
      return null;
    }
  }

  Future<SensorReading?> readSensor(PlantSensor sensor) async {
    if (sensor.id == null) return null;
    _readingInProgress[sensor.id!] = true;
    _errors = [];
    notifyListeners();

    try {
      // For Parrot: read firmware during the same BLE connection to avoid
      // a separate reconnect that often fails.
      final needsFirmware = !_firmwareVersions.containsKey(sensor.id!);

      final reading = await _ble.readSensor(
        sensor,
        onFirmware: needsFirmware
            ? (version) {
                if (version != null) {
                  _firmwareVersions[sensor.id!] = version;
                }
              }
            : null,
      );
      if (reading != null) {
        await _db.insertReading(reading);
        _latestReadings[sensor.id!] = reading;
      }
      _readingInProgress[sensor.id!] = false;
      notifyListeners();

      // For Mi Flora (or if Parrot firmware wasn't read during connection),
      // try a separate connection as fallback
      if (!_firmwareVersions.containsKey(sensor.id!)) {
        readFirmwareVersion(sensor);
      }

      return reading;
    } catch (e) {
      var msg = e.toString();
      msg = msg.replaceAll(RegExp(r'Exception: '), '');
      _errors.add(msg);
      _readingInProgress[sensor.id!] = false;
      notifyListeners();
      return null;
    }
  }

  /// Flash OAD firmware onto a Parrot Flower Power sensor.
  Future<bool> flashFirmware(PlantSensor sensor, Uint8List firmwareBytes) async {
    if (sensor.id == null) return false;
    if (_readingInProgress[sensor.id!] == true) {
      _oadError = 'Lecture capteur en cours, reessayez apres';
      notifyListeners();
      return false;
    }

    _oadInProgress[sensor.id!] = true;
    _oadProgress[sensor.id!] = 0.0;
    _oadStatus = 'Demarrage...';
    _oadError = null;
    notifyListeners();

    String lastStatus = '';
    try {
      final device = BluetoothDevice.fromId(sensor.macAddress);
      final success = await ParrotOadService.flashFirmware(
        device,
        firmwareBytes,
        onProgress: (sent, total) {
          _oadProgress[sensor.id!] = sent / total;
          notifyListeners();
        },
        onStatus: (status) {
          lastStatus = status;
          _oadStatus = status;
          notifyListeners();
        },
      );

      _oadInProgress[sensor.id!] = false;
      if (success) {
        _oadStatus = 'Flash reussi!';
        _oadProgress[sensor.id!] = 1.0;
        _firmwareVersions.remove(sensor.id!);
      } else {
        _oadError = lastStatus.isNotEmpty ? lastStatus : 'Echec du flash';
        _oadStatus = null;
      }
      notifyListeners();
      return success;
    } catch (e) {
      _oadInProgress[sensor.id!] = false;
      _oadError = 'Erreur: $e';
      _oadStatus = null;
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshAll() async {
    _isRefreshingAll = true;
    _errors = [];
    notifyListeners();

    for (final sensor in _sensors) {
      await readSensor(sensor);
      await Future.delayed(const Duration(seconds: 3));
    }

    _isRefreshingAll = false;
    notifyListeners();
  }

  Future<List<SensorReading>> getHistory(
    int sensorId, {
    Duration period = const Duration(days: 7),
  }) async {
    final since = DateTime.now().subtract(period);
    return await _db.getReadings(sensorId, since: since);
  }

  Future<void> purgeOldData(int keepDays) async {
    await _db.purgeOldReadings(keepDays);
  }

  // Reset state
  final Map<int, bool> _resetInProgress = {};
  bool isResetInProgress(int sensorId) => _resetInProgress[sensorId] ?? false;

  /// Reset a Parrot sensor (clean name, clear cache).
  Future<Map<String, String>?> resetParrotSensor(PlantSensor sensor) async {
    if (sensor.id == null) return null;
    if (_readingInProgress[sensor.id!] == true) return null;

    _resetInProgress[sensor.id!] = true;
    notifyListeners();

    try {
      final device = BluetoothDevice.fromId(sensor.macAddress);
      final results = await ParrotProtocol.resetSensor(device);
      _resetInProgress[sensor.id!] = false;
      notifyListeners();
      return results;
    } catch (e) {
      _resetInProgress[sensor.id!] = false;
      notifyListeners();
      return {'Erreur': '$e'};
    }
  }

  // Diagnostic state
  final Map<int, bool> _diagInProgress = {};
  bool isDiagInProgress(int sensorId) => _diagInProgress[sensorId] ?? false;

  Map<String, String>? _diagResults;
  Map<String, String>? get diagResults => _diagResults;

  /// Run calibration diagnostic on a Parrot sensor.
  Future<Map<String, String>?> runDiagnostic(PlantSensor sensor) async {
    if (sensor.id == null) return null;
    if (_readingInProgress[sensor.id!] == true) return null;

    _diagInProgress[sensor.id!] = true;
    _diagResults = null;
    notifyListeners();

    try {
      final device = BluetoothDevice.fromId(sensor.macAddress);
      final results = await ParrotProtocol.runDiagnostic(device);
      _diagResults = results;
      _diagInProgress[sensor.id!] = false;
      notifyListeners();
      return results;
    } catch (e) {
      _diagResults = {'Erreur': '$e'};
      _diagInProgress[sensor.id!] = false;
      notifyListeners();
      return _diagResults;
    }
  }
}
