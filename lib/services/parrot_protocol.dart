import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/sensor_reading.dart';
import 'ble_connection.dart';
import 'log_service.dart';

class ParrotProtocol {
  // Live mode service
  static const String serviceUuid = '39e1fa00-84a8-11e2-afba-0002a5d5c51b';
  static const String liveModeUuid = '39e1fa06-84a8-11e2-afba-0002a5d5c51b';

  // Raw live characteristics (uint16 LE) — always available
  static const String lightRawUuid = '39e1fa01-84a8-11e2-afba-0002a5d5c51b';
  static const String soilEcRawUuid = '39e1fa02-84a8-11e2-afba-0002a5d5c51b';
  static const String soilTempRawUuid =
      '39e1fa03-84a8-11e2-afba-0002a5d5c51b';
  static const String airTempRawUuid =
      '39e1fa04-84a8-11e2-afba-0002a5d5c51b';
  static const String soilVwcRawUuid =
      '39e1fa05-84a8-11e2-afba-0002a5d5c51b';

  // Calibrated characteristics (float32 LE, firmware >= 1.1)
  static const String moistureCalUuid =
      '39e1fa09-84a8-11e2-afba-0002a5d5c51b';
  static const String airTempCalUuid =
      '39e1fa0a-84a8-11e2-afba-0002a5d5c51b';
  static const String lightCalUuid =
      '39e1fa0b-84a8-11e2-afba-0002a5d5c51b';
  static const String eaCalUuid = '39e1fa0c-84a8-11e2-afba-0002a5d5c51b';
  static const String ecbCalUuid = '39e1fa0d-84a8-11e2-afba-0002a5d5c51b';
  static const String ecPorousCalUuid =
      '39e1fa0e-84a8-11e2-afba-0002a5d5c51b';

  // History service (39e1FC00) — offline measurement log on the sensor
  static const String historyServiceUuid =
      '39e1fc00-84a8-11e2-afba-0002a5d5c51b';
  static const String historyNbEntriesUuid =
      '39e1fc01-84a8-11e2-afba-0002a5d5c51b'; // U16 LE
  static const String historyLastEntryUuid =
      '39e1fc02-84a8-11e2-afba-0002a5d5c51b'; // U32 LE
  static const String historyTransferStartUuid =
      '39e1fc03-84a8-11e2-afba-0002a5d5c51b'; // U32 LE R/W
  static const String historySessionIdUuid =
      '39e1fc04-84a8-11e2-afba-0002a5d5c51b'; // U16 LE
  static const String historySessionStartUuid =
      '39e1fc05-84a8-11e2-afba-0002a5d5c51b'; // U32 LE
  static const String historySessionPeriodUuid =
      '39e1fc06-84a8-11e2-afba-0002a5d5c51b'; // U16 LE (seconds)

  // Clock service (39e1FD00) — sensor's internal time
  static const String clockServiceUuid =
      '39e1fd00-84a8-11e2-afba-0002a5d5c51b';
  static const String clockTimeUuid =
      '39e1fd01-84a8-11e2-afba-0002a5d5c51b'; // U32 LE (seconds since boot)

  // Battery (standard BLE)
  static const String batteryUuid = '00002a19-0000-1000-8000-00805f9b34fb';

  // Device Information Service (standard BLE)
  static const String firmwareRevisionUuid =
      '00002a26-0000-1000-8000-00805f9b34fb';

  /// Read float32 little-endian from 4 bytes
  static double readFloat32LE(List<int> data) {
    if (data.length < 4) return 0.0;
    final bytes = ByteData.sublistView(Uint8List.fromList(data.sublist(0, 4)));
    return bytes.getFloat32(0, Endian.little);
  }

  /// Read uint16 little-endian from 2 bytes
  static int readUint16LE(List<int> data) {
    if (data.length < 2) return 0;
    return data[0] | (data[1] << 8);
  }

  /// Read uint32 little-endian from 4 bytes
  static int readUint32LE(List<int> data) {
    if (data.length < 4) return 0;
    return data[0] |
        (data[1] << 8) |
        (data[2] << 16) |
        (data[3] << 24);
  }

  /// Estimate soil temperature from NTC thermistor raw readings.
  static double estimateSoilTemp(
      double airTempCal, int airRaw, int soilRaw) {
    const vcc = 3.3;
    const adcMax = 2047.0;
    const ntcB = 3380.0;

    final vAir = airRaw * vcc / adcMax;
    final vSoil = soilRaw * vcc / adcMax;

    if (vAir <= 0 || vSoil <= 0 || vAir >= vcc || vSoil >= vcc) {
      return airTempCal;
    }

    final rRatioAir = vcc / vAir - 1;
    final rRatioSoil = vcc / vSoil - 1;

    if (rRatioAir <= 0 || rRatioSoil <= 0) return airTempCal;

    final lnRatio = log(rRatioSoil / rRatioAir);
    final tAirK = airTempCal + 273.15;
    final tSoilK = 1.0 / (1.0 / tAirK + lnRatio / ntcB);

    final result = tSoilK - 273.15;
    return (result * 10).roundToDouble() / 10;
  }

  // ──────────────────────────────────────────────
  // Firmware
  // ──────────────────────────────────────────────

  static Future<String?> readFirmwareVersion(BluetoothDevice device) async {
    try {
      appLog('Parrot', 'readFirmwareVersion: connexion à ${device.remoteId}...');
      final services = await BleConnection.connectAndDiscover(device);
      appLog('Parrot', 'readFirmwareVersion: ${services.length} services');
      final version = await readFirmwareFromServices(services);
      appLog('Parrot', 'readFirmwareVersion: résultat = $version');
      await BleConnection.safeDisconnect(device);
      return version;
    } catch (e) {
      appLog('Parrot', 'readFirmwareVersion: ERREUR = $e');
      await BleConnection.safeDisconnect(device);
      return null;
    }
  }

  static Future<String?> readFirmwareFromServices(
      List<BluetoothService> services) async {
    appLog('Parrot', 'Services découverts (${services.length}):');
    for (final service in services) {
      final sUuid = service.uuid.toString().toLowerCase();
      final chars = service.characteristics
          .map((c) => c.uuid.toString().toLowerCase())
          .toList();
      appLog('Parrot', '  $sUuid → ${chars.length} chars: $chars');
    }

    // Find Device Information Service (0x180A)
    BluetoothService? deviceInfoService;
    for (final service in services) {
      if (_shortUuid(service.uuid.toString()) == '180a') {
        deviceInfoService = service;
        break;
      }
    }

    if (deviceInfoService == null) {
      final found = services
          .map((s) => s.uuid.toString().toLowerCase())
          .toList();
      appLog('Parrot', '⚠ Device Info (0x180A) NON TROUVÉ parmi: $found');

      // Fallback: some Parrot devices may use a different UUID format
      // Try matching any service that contains "180a" anywhere
      for (final service in services) {
        for (final c in service.characteristics) {
          final cUuid = c.uuid.toString().toLowerCase();
          if (cUuid.contains('2a26')) {
            appLog('Parrot', '✓ Trouvé 0x2A26 dans service ${service.uuid}');
            try {
              final data = await c.read();
              if (data.isNotEmpty) {
                return String.fromCharCodes(data).trim();
              }
            } catch (e) {
              appLog('Parrot', 'Erreur lecture 2A26 fallback: $e');
            }
          }
        }
      }

      return null;
    }

    appLog('Parrot', '✓ Device Information Service trouvé');

    // Try 0x2A26 first (firmware revision)
    final fwChar =
        _findCharacteristic(deviceInfoService, firmwareRevisionUuid);
    if (fwChar != null) {
      try {
        final data = await fwChar.read();
        appLog('Parrot', 'Firmware raw: $data');
        if (data.isNotEmpty) {
          final version = String.fromCharCodes(data).trim();
          appLog('Parrot', '✓ Firmware: $version');
          return version;
        }
      } catch (e) {
        appLog('Parrot', '⚠ Erreur lecture 0x2A26: $e');
      }
    } else {
      appLog('Parrot', '⚠ Char 0x2A26 non trouvée');
    }

    // Fallback: try reading all chars in Device Info service
    appLog('Parrot', 'Tentative lecture de toutes les chars Device Info...');
    for (final c in deviceInfoService.characteristics) {
      try {
        final data = await c.read();
        final str = String.fromCharCodes(data).trim();
        appLog('Parrot', '  ${c.uuid}: $data → "$str"');
        // Firmware typically looks like "X.Y.Z"
        if (str.contains(RegExp(r'^\d+\.\d+'))) {
          return str;
        }
      } catch (e) {
        appLog('Parrot', '  ${c.uuid}: erreur $e');
      }
    }

    return null;
  }

  // ──────────────────────────────────────────────
  // Sensor reading — notification-based per Parrot spec
  // ──────────────────────────────────────────────

  static Future<SensorReading?> readSensor(
    BluetoothDevice device,
    int sensorId, {
    void Function(String?)? onFirmware,
  }) async {
    try {
      final services = await BleConnection.connectAndDiscover(device);

      BluetoothService? parrotService;
      BluetoothService? batteryService;

      for (final service in services) {
        final sShort = _shortUuid(service.uuid.toString());
        if (sShort == _shortUuid(serviceUuid)) {
          parrotService = service;
        }
        if (sShort == '180f') {
          batteryService = service;
        }
      }

      if (parrotService == null) {
        await BleConnection.safeDisconnect(device);
        throw Exception(
          'Service Parrot non trouvé — capteur hors de portée ?',
        );
      }

      // 0. Read firmware during this connection
      if (onFirmware != null) {
        final fw = await readFirmwareFromServices(services);
        onFirmware(fw);
      }

      // Log available characteristics
      appLog('Parrot', 'Caractéristiques du service Live:');
      for (final c in parrotService.characteristics) {
        appLog('Parrot', '  ${c.uuid} props=${c.properties}');
      }

      // 1. Enable notifications on sensor characteristics per Parrot spec
      final notifUuids = [
        lightRawUuid, // FA01
        soilEcRawUuid, // FA02
        soilTempRawUuid, // FA03
        airTempRawUuid, // FA04
        soilVwcRawUuid, // FA05
      ];

      // Also try calibrated if available
      final calNotifUuids = [
        moistureCalUuid, // FA09
        airTempCalUuid, // FA0A
        lightCalUuid, // FA0B
        ecbCalUuid, // FA0D
        ecPorousCalUuid, // FA0E
      ];

      // Store latest notification values
      final notifValues = <String, List<int>>{};
      final subscriptions = <StreamSubscription>[];

      // Subscribe to raw characteristics notifications
      for (final uuid in [...notifUuids, ...calNotifUuids]) {
        final c = _findCharacteristic(parrotService, uuid);
        if (c == null) continue;
        if (!c.properties.notify) continue;
        try {
          await c.setNotifyValue(true);
          final sub = c.onValueReceived.listen((data) {
            notifValues[uuid.toLowerCase()] = data;
          });
          subscriptions.add(sub);
          appLog('Parrot', '✓ Notifications activées pour $uuid');
        } catch (e) {
          appLog('Parrot', '⚠ Échec notif pour $uuid: $e');
        }
      }

      // 2. Enable live mode — write 1 to FA06
      final liveChar = _findCharacteristic(parrotService, liveModeUuid);
      if (liveChar != null) {
        await liveChar.write([0x01]);
        appLog('Parrot', 'Live mode activé, attente 3s...');
        // Wait for at least 2 notification cycles (1 per second)
        await Future.delayed(const Duration(seconds: 3));
      }

      // 3. Read values — prefer notifications, fallback to direct read
      appLog('Parrot', 'Valeurs reçues par notification: ${notifValues.keys.toList()}');

      // Helper: get data from notifications or direct read
      Future<List<int>?> getData(String uuid) async {
        final key = uuid.toLowerCase();
        if (notifValues.containsKey(key)) {
          return notifValues[key];
        }
        // Fallback to direct read
        return await _readCharSafe(parrotService!, uuid);
      }

      // Read all sensor data
      final airTempCalData = await getData(airTempCalUuid);
      final moistureCalData = await getData(moistureCalUuid);
      final moistureRawData = await getData(soilVwcRawUuid); // FA05
      final lightCalData = await getData(lightCalUuid);
      final lightRawData = await getData(lightRawUuid);
      final airTempRawData = await getData(airTempRawUuid);
      final soilTempRawData = await getData(soilTempRawUuid);

      // Conductivity — all sources
      final ecbCalData = await getData(ecbCalUuid);
      final ecPorousData = await getData(ecPorousCalUuid);
      final soilEcRawData = await getData(soilEcRawUuid);

      appLog('Parrot', 'ECB cal data: $ecbCalData');
      appLog('Parrot', 'EC Porous data: $ecPorousData');
      appLog('Parrot', 'Soil EC raw data: $soilEcRawData');

      // 4. Cancel all notification subscriptions
      for (final sub in subscriptions) {
        await sub.cancel();
      }
      // Disable notifications
      for (final uuid in [...notifUuids, ...calNotifUuids]) {
        final c = _findCharacteristic(parrotService, uuid);
        if (c == null) continue;
        try {
          await c.setNotifyValue(false);
        } catch (_) {}
      }

      // 5. Parse values
      final airTempCal =
          airTempCalData != null ? readFloat32LE(airTempCalData) : null;

      // Moisture: prefer polynomial conversion on raw FA05 (more accurate)
      // Firmware calibration FA09 overestimates on degraded sensors
      double? moistureFinal;
      if (moistureRawData != null && moistureRawData.length >= 2) {
        final rawMoisture = readUint16LE(moistureRawData);
        appLog('Parrot', 'Moisture FA05 raw=$rawMoisture');
        if (rawMoisture < 65535) {
          moistureFinal = rawToMoisture(rawMoisture);
          appLog('Parrot', 'Moisture from polynomial: ${moistureFinal.toStringAsFixed(1)}%');
          // Also log firmware calibration for comparison
          if (moistureCalData != null) {
            final fwMoisture = readFloat32LE(moistureCalData);
            appLog('Parrot', 'Moisture firmware FA09: ${fwMoisture.toStringAsFixed(1)}% (ignored)');
          }
        }
      }
      // Fallback to firmware calibration if raw not available
      if (moistureFinal == null && moistureCalData != null) {
        moistureFinal = readFloat32LE(moistureCalData);
        appLog('Parrot', 'Moisture from firmware FA09 (fallback): ${moistureFinal.toStringAsFixed(1)}%');
      }

      // Light: we use FA0B (calibrated DLI in mol/m²/d) as the source of truth
      // because firmware 2.x ("hawaii") often has FA01 unreliable (returns
      // 0xFFFF or values outside the 0-4095 range that has no documented
      // conversion). FA0B is well-specified by Parrot (page 25) and works
      // consistently across sensors. FA01 is logged for diagnostic only.
      if (lightRawData != null && lightRawData.length >= 2) {
        final rawLight = readUint16LE(lightRawData);
        appLog('Parrot',
            'Light FA01 raw=$rawLight (0x${rawLight.toRadixString(16)}) [diag only]');
      }

      double? dliMolPerM2PerDay;
      if (lightCalData != null && lightCalData.length >= 4) {
        final calValue = readFloat32LE(lightCalData);
        appLog('Parrot', 'Light FA0B (DLI) raw=$calValue');
        if (calValue.isFinite && calValue >= 0) {
          dliMolPerM2PerDay = calValue;
          appLog('Parrot', 'DLI: ${calValue.toStringAsFixed(2)} mol/m2/d');
        }
      }

      appLog('Parrot',
          'airTempCal=$airTempCal moisture=$moistureFinal dli=$dliMolPerM2PerDay mol/m2/d');

      // 6. Soil temperature from NTC thermistor
      double? soilTemp;
      if (airTempCal != null &&
          airTempRawData != null &&
          soilTempRawData != null) {
        final airRaw = readUint16LE(airTempRawData);
        final soilRaw = readUint16LE(soilTempRawData);
        if (airRaw > 0 && soilRaw > 0) {
          soilTemp = estimateSoilTemp(airTempCal, airRaw, soilRaw);
        }
      }

      // 7. Conductivity — cascade: calibrated ECB → EC Porous → raw
      //    Note: 0 is valid (sensor in air or dry soil) — only reject NaN/Inf
      double? conductivity;

      if (ecbCalData != null && ecbCalData.length >= 4) {
        final ecbDsm = readFloat32LE(ecbCalData);
        appLog('Parrot', 'ECB parsed: $ecbDsm dS/m');
        if (ecbDsm.isFinite && ecbDsm >= 0) {
          conductivity = ecbDsm * 1000.0; // dS/m → µS/cm
        }
      }

      if (conductivity == null &&
          ecPorousData != null &&
          ecPorousData.length >= 4) {
        final ecPorous = readFloat32LE(ecPorousData);
        appLog('Parrot', 'EC Porous parsed: $ecPorous dS/m');
        if (ecPorous.isFinite && ecPorous >= 0) {
          conductivity = ecPorous * 1000.0; // dS/m → µS/cm
        }
      }

      // Raw Soil EC: per Parrot spec, voltage = (value * 3.3) / (2^11 - 1)
      if (conductivity == null &&
          soilEcRawData != null &&
          soilEcRawData.length >= 2) {
        final rawEc = readUint16LE(soilEcRawData);
        appLog('Parrot', 'Raw Soil EC: $rawEc (0x${rawEc.toRadixString(16)})');
        if (rawEc < 65535 && rawEc > 0) {
          // Per spec: display value = (characteristic_value * 3.3) / 2047
          // This gives voltage; convert to approximate µS/cm
          final voltage = (rawEc * 3.3) / 2047.0;
          final rawCond = voltage * 3030.0; // ~0-10000 µS/cm range
          conductivity = rawCond > 10000 ? 10000 : rawCond;
          appLog('Parrot', 'Raw EC voltage=$voltage → $conductivity µS/cm');
        } else {
          appLog('Parrot', 'Raw EC invalide ($rawEc), ignoré');
        }
      }

      appLog('Parrot', 'Conductivité finale: $conductivity µS/cm');

      // 8. Battery
      int? batteryLevel;
      if (batteryService != null) {
        final batteryData = await _readCharSafe(batteryService, batteryUuid);
        if (batteryData != null && batteryData.isNotEmpty) {
          batteryLevel = batteryData[0];
        }
      }
      if (batteryLevel == null) {
        for (final service in services) {
          if (service == batteryService) continue;
          for (final c in service.characteristics) {
            if (c.uuid.toString().toLowerCase().contains('2a19')) {
              try {
                final data = await c.read();
                if (data.isNotEmpty) batteryLevel = data[0];
              } catch (_) {}
              break;
            }
          }
          if (batteryLevel != null) break;
        }
      }

      // 9. Disable live mode
      if (liveChar != null) {
        try {
          await liveChar.write([0x00]);
        } catch (_) {}
      }

      // 10. POC: read History service metadata (FC01-FC06) + clock (FD01)
      // Just logging for now — no rapatriation yet.
      try {
        BluetoothService? historyService;
        BluetoothService? clockService;
        for (final s in services) {
          final sid = _shortUuid(s.uuid.toString());
          if (sid == _shortUuid(historyServiceUuid)) historyService = s;
          if (sid == _shortUuid(clockServiceUuid)) clockService = s;
        }

        if (clockService != null) {
          final clockData =
              await _readCharSafe(clockService, clockTimeUuid);
          if (clockData != null && clockData.length >= 4) {
            final clockSeconds = readUint32LE(clockData);
            final uptimeHours = (clockSeconds / 3600).toStringAsFixed(1);
            final uptimeDays = (clockSeconds / 86400).toStringAsFixed(1);
            appLog('Parrot',
                'Clock FD01: $clockSeconds s = $uptimeHours h ($uptimeDays days uptime)');
          }
        }

        if (historyService != null) {
          final nbEntriesData =
              await _readCharSafe(historyService, historyNbEntriesUuid);
          final lastEntryData =
              await _readCharSafe(historyService, historyLastEntryUuid);
          final sessionIdData =
              await _readCharSafe(historyService, historySessionIdUuid);
          final sessionStartData =
              await _readCharSafe(historyService, historySessionStartUuid);
          final sessionPeriodData =
              await _readCharSafe(historyService, historySessionPeriodUuid);

          final nbEntries =
              nbEntriesData != null && nbEntriesData.length >= 2
                  ? readUint16LE(nbEntriesData)
                  : null;
          final lastEntry =
              lastEntryData != null && lastEntryData.length >= 4
                  ? readUint32LE(lastEntryData)
                  : null;
          final sessionId =
              sessionIdData != null && sessionIdData.length >= 2
                  ? readUint16LE(sessionIdData)
                  : null;
          final sessionStart =
              sessionStartData != null && sessionStartData.length >= 4
                  ? readUint32LE(sessionStartData)
                  : null;
          final sessionPeriod =
              sessionPeriodData != null && sessionPeriodData.length >= 2
                  ? readUint16LE(sessionPeriodData)
                  : null;

          appLog('Parrot',
              'History meta: nbEntries=$nbEntries lastEntry=$lastEntry sessionId=$sessionId sessionStart=$sessionStart period=${sessionPeriod}s');

          // Compute first-available index per spec section 4.3:
          // firstEntryIdx = lastEntry - nbEntries + 1
          if (nbEntries != null && lastEntry != null && nbEntries > 0) {
            final firstEntry = lastEntry - nbEntries + 1;
            final coverageSec =
                sessionPeriod != null ? nbEntries * sessionPeriod : null;
            final coverageHours = coverageSec != null
                ? (coverageSec / 3600).toStringAsFixed(1)
                : '?';
            final coverageDays = coverageSec != null
                ? (coverageSec / 86400).toStringAsFixed(1)
                : '?';
            appLog('Parrot',
                'History coverage: entries [$firstEntry..$lastEntry] = $nbEntries samples = $coverageHours h ($coverageDays days)');
          }
        } else {
          appLog('Parrot', '⚠ History service FC00 non trouvé');
        }
      } catch (e) {
        appLog('Parrot', '⚠ Erreur lecture history meta: $e');
      }

      await BleConnection.safeDisconnect(device);

      return SensorReading(
        sensorId: sensorId,
        temperature: airTempCal,
        soilTemperature: soilTemp,
        moisture: moistureFinal,
        light: dliMolPerM2PerDay,
        conductivity: conductivity,
        battery: batteryLevel,
      );
    } catch (e) {
      await BleConnection.safeDisconnect(device);
      rethrow;
    }
  }

  // ──────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────

  /// Extract the 4-hex short form from a BLE UUID.
  /// "00002a26-0000-1000-8000-00805f9b34fb" → "2a26"
  /// "2a26" → "2a26"
  static String _shortUuid(String uuid) {
    final u = uuid.toLowerCase();
    if (u.length >= 8 && u.contains('-')) {
      return u.substring(4, 8);
    }
    return u;
  }

  static BluetoothCharacteristic? _findCharacteristic(
    BluetoothService service,
    String uuid,
  ) {
    final targetShort = _shortUuid(uuid);
    final targetFull = uuid.toLowerCase();
    for (final c in service.characteristics) {
      final cUuid = c.uuid.toString().toLowerCase();
      if (cUuid == targetFull || _shortUuid(cUuid) == targetShort) {
        return c;
      }
    }
    return null;
  }

  static Future<List<int>?> _readCharSafe(
    BluetoothService service,
    String uuid,
  ) async {
    final c = _findCharacteristic(service, uuid);
    if (c == null) return null;
    try {
      return await c.read();
    } catch (e) {
      appLog('Parrot', 'Erreur lecture $uuid: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────
  // Reset sensor (clean name + clear GATT cache)
  // ──────────────────────────────────────────────

  /// Reset a Parrot Flower Power sensor:
  /// - Clean the BLE friendly name (FE03) to remove parasitic characters
  /// - Clear the Android GATT cache so the device is re-discovered fresh
  static Future<Map<String, String>> resetSensor(BluetoothDevice device) async {
    final results = <String, String>{};

    try {
      final services = await BleConnection.connectAndDiscover(device);

      // Find calibration service (FE00)
      BluetoothService? calService;
      for (final s in services) {
        final uuid = s.uuid.toString().toLowerCase();
        if (uuid.contains('fe00')) {
          calService = s;
          break;
        }
      }

      if (calService == null) {
        results['Erreur'] = 'Service calibration (FE00) non trouve';
        await BleConnection.safeDisconnect(device);
        return results;
      }

      // 1. Read and clean friendly name (FE03)
      final nameChar = _findCharacteristic(calService, _friendlyNameUuid);
      if (nameChar != null) {
        try {
          final oldData = await nameChar.read();
          final oldName = String.fromCharCodes(oldData.where((b) => b > 0));
          results['Ancien nom'] = oldName;

          // Extract clean name: "Flower power XXXX" (remove trailing garbage)
          final match = RegExp(r'Flower power [A-F0-9]{4}', caseSensitive: false)
              .firstMatch(oldName);
          final cleanName = match?.group(0) ??
              'Flower power ${device.remoteId.toString().substring(device.remoteId.toString().length - 5).replaceAll(':', '')}';

          // Write clean name (null-terminated)
          // Try write, then writeWithoutResponse as fallback
          final nameBytes = cleanName.codeUnits.toList();
          nameBytes.add(0); // null terminator
          if (nameChar.properties.write) {
            await nameChar.write(nameBytes);
            results['Nouveau nom'] = cleanName;
          } else if (nameChar.properties.writeWithoutResponse) {
            await nameChar.write(nameBytes, withoutResponse: true);
            results['Nouveau nom'] = cleanName;
          } else {
            // Force write attempt anyway — some Parrot firmware accepts it
            try {
              await nameChar.write(nameBytes, withoutResponse: true);
              results['Nouveau nom'] = '$cleanName (force)';
            } catch (_) {
              results['Nom'] = 'Lecture seule sur ce firmware (non modifiable)';
            }
          }
          appLog('Parrot', 'Nom reinitialise: "$oldName" -> "$cleanName"');
        } catch (e) {
          results['Nom'] = 'Erreur ecriture: $e';
          appLog('Parrot', 'Erreur ecriture nom: $e');
        }
      } else {
        results['Nom'] = 'Caracteristique FE03 non trouvee';
      }

      // 2. Disable live mode if active
      BluetoothService? liveService;
      for (final s in services) {
        final uuid = s.uuid.toString().toLowerCase();
        if (uuid.contains('fa00')) {
          liveService = s;
          break;
        }
      }
      if (liveService != null) {
        final liveChar = _findCharacteristic(liveService, liveModeUuid);
        if (liveChar != null) {
          try {
            await liveChar.write([0x00]);
            results['Live mode'] = 'Desactive';
          } catch (_) {}
        }
      }

      // 3. Clear GATT cache while still connected
      try {
        await device.clearGattCache();
        results['Cache GATT'] = 'Efface';
      } catch (e) {
        results['Cache GATT'] = 'Erreur: $e';
      }

      // 4. Disconnect
      await BleConnection.safeDisconnect(device);

      results['Statut'] = 'Reinitialisation terminee';
    } catch (e) {
      results['Erreur'] = '$e';
      try {
        await BleConnection.safeDisconnect(device);
      } catch (_) {}
    }

    return results;
  }

  // ──────────────────────────────────────────────
  // Calibration diagnostics
  // ──────────────────────────────────────────────

  static const String _calDataUuid =
      '39e1fe01-84a8-11e2-afba-0002a5d5c51b';
  static const String _friendlyNameUuid =
      '39e1fe03-84a8-11e2-afba-0002a5d5c51b';
  static const String _colorUuid =
      '39e1fe04-84a8-11e2-afba-0002a5d5c51b';

  /// Raw→calibrated moisture conversion (Parrot polynomial)
  static double rawToMoisture(int raw) {
    final r = raw.toDouble();
    final hygro1 = 11.4293 +
        (1.0698e-9 * pow(r, 4) -
            1.52538e-6 * pow(r, 3) +
            8.66976e-4 * pow(r, 2) -
            0.169422 * r);
    final hygro2 = 100.0 *
        (4.5e-6 * pow(hygro1, 3) -
            5.5e-4 * pow(hygro1, 2) +
            0.0292 * hygro1 -
            0.053);
    return hygro2.clamp(0.0, 100.0);
  }

  /// Raw→temperature conversion (Parrot polynomial)
  static double rawToTemperature(int raw) {
    final r = raw.toDouble();
    final t = 3.044e-8 * pow(r, 3) -
        8.038e-5 * pow(r, 2) +
        0.1149 * r -
        30.45;
    return t.clamp(-10.0, 55.0);
  }

  /// Run a full diagnostic on the sensor, returning a map of results.
  static Future<Map<String, String>> runDiagnostic(
    BluetoothDevice device,
  ) async {
    final results = <String, String>{};

    try {
      final services = await BleConnection.connectAndDiscover(device);

      // Find services
      BluetoothService? liveService;
      BluetoothService? calService;
      BluetoothService? batteryService;
      for (final s in services) {
        final uuid = s.uuid.toString().toLowerCase();
        if (uuid.contains('fa00')) liveService = s;
        if (uuid.contains('fe00')) calService = s;
        if (uuid.contains('180f')) batteryService = s;
      }

      // Battery
      if (batteryService != null) {
        final data = await _readCharSafe(batteryService, batteryUuid);
        if (data != null && data.isNotEmpty) {
          results['Batterie'] = '${data[0]}%';
        }
      }

      // Calibration service data
      if (calService != null) {
        final calData = await _readCharSafe(calService, _calDataUuid);
        results['Calibration brute'] = calData != null
            ? calData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')
            : 'Non disponible';

        final nameData = await _readCharSafe(calService, _friendlyNameUuid);
        if (nameData != null) {
          final name = String.fromCharCodes(
              nameData.where((b) => b > 0));
          results['Nom capteur'] = name.isEmpty ? '(vide)' : name;
        }

        final colorData = await _readCharSafe(calService, _colorUuid);
        if (colorData != null && colorData.length >= 2) {
          final code = readUint16LE(colorData);
          final colorName = {4: 'marron', 6: 'vert', 7: 'bleu'}[code] ?? 'inconnu ($code)';
          results['Couleur'] = colorName;
        }
      }

      // Live mode — read raw AND calibrated values
      if (liveService != null) {
        // Enable live mode
        final liveChar = _findCharacteristic(liveService, liveModeUuid);
        if (liveChar != null) {
          await liveChar.write([0x01]);
          await Future.delayed(const Duration(seconds: 3));
        }

        // Raw values
        final rawMoistureData = await _readCharSafe(liveService, soilVwcRawUuid);
        final rawTempData = await _readCharSafe(liveService, airTempRawUuid);
        final rawSoilTempData = await _readCharSafe(liveService, soilTempRawUuid);
        final rawLightData = await _readCharSafe(liveService, lightRawUuid);
        final rawEcData = await _readCharSafe(liveService, soilEcRawUuid);

        // Calibrated values
        final calMoistureData = await _readCharSafe(liveService, moistureCalUuid);
        final calTempData = await _readCharSafe(liveService, airTempCalUuid);
        final calLightData = await _readCharSafe(liveService, lightCalUuid);
        final calEcbData = await _readCharSafe(liveService, ecbCalUuid);
        final calEcPorousData = await _readCharSafe(liveService, ecPorousCalUuid);
        final calEaData = await _readCharSafe(liveService, eaCalUuid);

        // Parse and display
        if (rawMoistureData != null && rawMoistureData.length >= 2) {
          final raw = readUint16LE(rawMoistureData);
          final converted = rawToMoisture(raw);
          results['Humidite brute'] = '$raw (→ ${converted.toStringAsFixed(1)}%)';
        }
        if (calMoistureData != null && calMoistureData.length >= 4) {
          final cal = readFloat32LE(calMoistureData);
          results['Humidite calibree'] = '${cal.toStringAsFixed(1)}%';
        }

        if (rawTempData != null && rawTempData.length >= 2) {
          final raw = readUint16LE(rawTempData);
          final converted = rawToTemperature(raw);
          results['Temperature brute'] = '$raw (→ ${converted.toStringAsFixed(1)}°C)';
        }
        if (calTempData != null && calTempData.length >= 4) {
          final cal = readFloat32LE(calTempData);
          results['Temperature calibree'] = '${cal.toStringAsFixed(1)}°C';
        }

        if (rawSoilTempData != null && rawSoilTempData.length >= 2) {
          final raw = readUint16LE(rawSoilTempData);
          results['Temp sol brute'] = '$raw';
        }

        if (rawLightData != null && rawLightData.length >= 2) {
          final raw = readUint16LE(rawLightData);
          results['Lumiere brute'] = '$raw';
        }
        if (calLightData != null && calLightData.length >= 4) {
          final cal = readFloat32LE(calLightData);
          results['Lumiere calibree'] = '${cal.toStringAsFixed(2)} mol/m2/d';
        }

        if (rawEcData != null && rawEcData.length >= 2) {
          final raw = readUint16LE(rawEcData);
          results['EC brute'] = '$raw';
        }
        if (calEcbData != null && calEcbData.length >= 4) {
          final cal = readFloat32LE(calEcbData);
          results['ECB calibree'] = '${cal.toStringAsFixed(3)} dS/m';
        }
        if (calEcPorousData != null && calEcPorousData.length >= 4) {
          final cal = readFloat32LE(calEcPorousData);
          results['EC Porous'] = '${cal.toStringAsFixed(3)} dS/m';
        }
        if (calEaData != null && calEaData.length >= 4) {
          final cal = readFloat32LE(calEaData);
          results['EA'] = cal.toStringAsFixed(3);
        }

        // Disable live mode
        if (liveChar != null) {
          try {
            await liveChar.write([0x00]);
          } catch (_) {}
        }
      }

      await BleConnection.safeDisconnect(device);
    } catch (e) {
      results['Erreur'] = '$e';
      try {
        await BleConnection.safeDisconnect(device);
      } catch (_) {}
    }

    return results;
  }
}
