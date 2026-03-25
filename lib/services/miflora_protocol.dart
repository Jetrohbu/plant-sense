import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/sensor_reading.dart';
import 'ble_connection.dart';

class MiFloraProtocol {
  // Short UUIDs for flexible matching
  static const String _serviceShort = '1204';
  static const String _modeShort = '1a00';
  static const String _dataShort = '1a01';
  static const String _batteryShort = '1a02';

  /// Command to activate real-time data mode
  static const List<int> realTimeCommand = [0xA0, 0x1F];

  static Future<SensorReading?> readSensor(
    BluetoothDevice device,
    int sensorId,
  ) async {
    try {
      final services = await BleConnection.connectAndDiscover(device);

      // Find the data service — search ALL services for the one containing
      // characteristics 1a00/1a01 (most reliable method)
      BluetoothService? dataService;

      // Method 1: Find by service UUID
      for (final service in services) {
        if (_uuidContains(service.uuid, _serviceShort)) {
          dataService = service;
          break;
        }
      }

      // Method 2: Find by characteristic presence
      if (dataService == null) {
        for (final service in services) {
          for (final c in service.characteristics) {
            if (_uuidContains(c.uuid, _dataShort)) {
              dataService = service;
              break;
            }
          }
          if (dataService != null) break;
        }
      }

      if (dataService == null) {
        // Dump ALL services and ALL characteristics for debugging
        final dump = StringBuffer();
        for (final s in services) {
          dump.write('[${s.uuid}] chars: ');
          dump.write(s.characteristics.map((c) => c.uuid).join(', '));
          dump.write(' | ');
        }
        await BleConnection.safeDisconnect(device);
        throw Exception(
          'Service Mi Flora non trouvé. '
          '${services.length} services: $dump',
        );
      }

      // Dump characteristics of the found service for debug
      final charDump = dataService.characteristics
          .map((c) => c.uuid.toString())
          .join(', ');

      // Write real-time mode command on characteristic 1A00
      final modeChar = _findChar(dataService, _modeShort);
      if (modeChar != null) {
        await modeChar.write(realTimeCommand, withoutResponse: false);
        await Future.delayed(const Duration(seconds: 1));
      }

      // Read sensor data from characteristic 1A01 → 16 bytes
      final dataChar = _findChar(dataService, _dataShort);
      if (dataChar == null) {
        await BleConnection.safeDisconnect(device);
        throw Exception(
          'Char 1A01 non trouvée dans service. '
          'Chars trouvées: $charDump',
        );
      }

      final data = await dataChar.read();
      if (data.length < 10) {
        await BleConnection.safeDisconnect(device);
        throw Exception(
          'Données Mi Flora: ${data.length} octets (min 10). '
          'Raw: $data',
        );
      }

      // Parse data according to spec:
      // Bytes 0-1: Temperature (int16 LE, /10 → °C)
      // Byte 2:    padding
      // Bytes 3-6: Light (uint32 LE → lux)
      // Byte 7:    Moisture (uint8 → %)
      // Bytes 8-9: Conductivity (uint16 LE → µS/cm)
      final temperature = _readInt16LE(data, 0) / 10.0;
      final rawLight = _readUint32LE(data, 3);
      final light = rawLight <= 200000 ? rawLight.toDouble() : null;
      final rawMoisture = data[7].toDouble();
      final moisture = (rawMoisture >= 0 && rawMoisture <= 100) ? rawMoisture : null;
      final rawConductivity = _readUint16LE(data, 8).toDouble();
      final conductivity = (rawConductivity >= 0 && rawConductivity <= 10000) ? rawConductivity : null;

      // Read battery (1A02, first byte = uint8 %)
      int? batteryLevel;
      final batteryChar = _findChar(dataService, _batteryShort);
      if (batteryChar != null) {
        try {
          final batteryData = await batteryChar.read();
          if (batteryData.isNotEmpty) {
            batteryLevel = batteryData[0];
          }
        } catch (_) {}
      }

      await BleConnection.safeDisconnect(device);

      return SensorReading(
        sensorId: sensorId,
        temperature: temperature,
        moisture: moisture,
        light: light,
        conductivity: conductivity,
        battery: batteryLevel,
      );
    } catch (e) {
      await BleConnection.safeDisconnect(device);
      rethrow;
    }
  }

  /// Read firmware version from characteristic 1A02.
  /// Bytes: [0]=battery, [1]=separator, [2..]=firmware version ASCII (e.g. "3.2.1")
  static Future<String?> readFirmwareVersion(BluetoothDevice device) async {
    try {
      final services = await BleConnection.connectAndDiscover(device);

      BluetoothService? dataService;
      for (final service in services) {
        if (_uuidContains(service.uuid, _serviceShort)) {
          dataService = service;
          break;
        }
      }
      if (dataService == null) {
        for (final service in services) {
          for (final c in service.characteristics) {
            if (_uuidContains(c.uuid, _batteryShort)) {
              dataService = service;
              break;
            }
          }
          if (dataService != null) break;
        }
      }

      if (dataService == null) {
        await BleConnection.safeDisconnect(device);
        return null;
      }

      final batteryChar = _findChar(dataService, _batteryShort);
      if (batteryChar == null) {
        await BleConnection.safeDisconnect(device);
        return null;
      }

      final data = await batteryChar.read();
      await BleConnection.safeDisconnect(device);

      if (data.length < 3) return null;
      // Bytes 2+ are the firmware version as ASCII
      return String.fromCharCodes(data.sublist(2)).trim();
    } catch (e) {
      await BleConnection.safeDisconnect(device);
      return null;
    }
  }

  /// Flexible UUID match — checks if the UUID string contains the short form
  static bool _uuidContains(dynamic uuid, String shortUuid) {
    return uuid.toString().toLowerCase().contains(shortUuid.toLowerCase());
  }

  /// Find a characteristic by short UUID (e.g. '1a01')
  static BluetoothCharacteristic? _findChar(
    BluetoothService service,
    String shortUuid,
  ) {
    for (final c in service.characteristics) {
      if (_uuidContains(c.uuid, shortUuid)) {
        return c;
      }
    }
    return null;
  }

  static int _readInt16LE(List<int> data, int offset) {
    final value = data[offset] | (data[offset + 1] << 8);
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  static int _readUint16LE(List<int> data, int offset) {
    return data[offset] | (data[offset + 1] << 8);
  }

  static int _readUint32LE(List<int> data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }
}
