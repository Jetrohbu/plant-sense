import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/plant_sensor.dart';
import '../models/sensor_reading.dart';
import 'parrot_protocol.dart';
import 'miflora_protocol.dart';

class BleService {
  static final BleService _instance = BleService._();
  factory BleService() => _instance;
  BleService._();

  final _scanResultsController =
      StreamController<List<ScanResult>>.broadcast();
  Stream<List<ScanResult>> get scanResults => _scanResultsController.stream;

  StreamSubscription? _scanSubscription;
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  Future<bool> isBluetoothOn() async {
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {
    if (_isScanning) {
      await stopScan();
    }
    _isScanning = true;

    // Cancel previous subscription to avoid listener leak
    await _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      // Filter for known plant sensors by name or service UUID
      final filtered = results.where((r) => _isKnownSensor(r)).toList();
      _scanResultsController.add(filtered);
    });

    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidScanMode: AndroidScanMode.lowLatency,
    );
    _isScanning = false;
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _isScanning = false;
  }

  /// Check if a scan result is a known plant sensor (by name or service UUID)
  static bool _isKnownSensor(ScanResult r) {
    final platformName = r.device.platformName.toLowerCase();
    final advName = r.advertisementData.advName.toLowerCase();
    if (_isParrotName(platformName) || _isParrotName(advName)) return true;
    if (_isMiFloraName(platformName) || _isMiFloraName(advName)) return true;
    // Parrot also detectable by service UUID in advertising
    final serviceUuids = r.advertisementData.serviceUuids
        .map((u) => u.toString().toLowerCase())
        .toList();
    if (serviceUuids.any((u) => u.contains('39e1fa00'))) return true;
    // Mi Flora: MAC prefix 5C:85:7E
    final mac = r.device.remoteId.toString().toUpperCase();
    if (mac.startsWith('5C:85:7E')) return true;
    return false;
  }

  static bool _isParrotName(String name) {
    return name.contains('flower power') || name.contains('parrot');
  }

  static bool _isMiFloraName(String name) {
    return name.contains('flower care') ||
        name.contains('flower mate') ||
        name.contains('hhccjcy');
  }

  SensorType? detectSensorType(ScanResult result) {
    final platformName = result.device.platformName.toLowerCase();
    final advName = result.advertisementData.advName.toLowerCase();
    // Check Parrot by name or service UUID
    if (_isParrotName(platformName) || _isParrotName(advName)) {
      return SensorType.parrotFlowerPower;
    }
    final serviceUuids = result.advertisementData.serviceUuids
        .map((u) => u.toString().toLowerCase())
        .toList();
    if (serviceUuids.any((u) => u.contains('39e1fa00'))) {
      return SensorType.parrotFlowerPower;
    }
    // Check Mi Flora by name or MAC prefix
    if (_isMiFloraName(platformName) || _isMiFloraName(advName)) {
      return SensorType.xiaomiMiFlora;
    }
    final mac = result.device.remoteId.toString().toUpperCase();
    if (mac.startsWith('5C:85:7E')) {
      return SensorType.xiaomiMiFlora;
    }
    return null;
  }

  /// Ensure Bluetooth permissions are granted before any BLE operation.
  Future<void> ensurePermissions() async {
    final btConnect = await Permission.bluetoothConnect.request();
    final btScan = await Permission.bluetoothScan.request();
    final location = await Permission.locationWhenInUse.request();

    if (!btConnect.isGranted) {
      throw Exception('Permission Bluetooth Connect refusée');
    }
    if (!btScan.isGranted) {
      throw Exception('Permission Bluetooth Scan refusée');
    }
    if (!location.isGranted) {
      throw Exception('Permission localisation refusée');
    }

    final btOn = await isBluetoothOn();
    if (!btOn) {
      throw Exception('Le Bluetooth est désactivé');
    }
  }

  Future<SensorReading?> readSensor(
    PlantSensor sensor, {
    void Function(String?)? onFirmware,
  }) async {
    await ensurePermissions();

    final device = BluetoothDevice.fromId(sensor.macAddress);

    switch (sensor.sensorType) {
      case SensorType.parrotFlowerPower:
        return await ParrotProtocol.readSensor(device, sensor.id!,
            onFirmware: onFirmware);
      case SensorType.xiaomiMiFlora:
        return await MiFloraProtocol.readSensor(device, sensor.id!);
    }
  }

  Future<String?> readFirmwareVersion(PlantSensor sensor) async {
    await ensurePermissions();

    final device = BluetoothDevice.fromId(sensor.macAddress);

    switch (sensor.sensorType) {
      case SensorType.parrotFlowerPower:
        return await ParrotProtocol.readFirmwareVersion(device);
      case SensorType.xiaomiMiFlora:
        return await MiFloraProtocol.readFirmwareVersion(device);
    }
  }

  void dispose() {
    _scanResultsController.close();
  }
}
