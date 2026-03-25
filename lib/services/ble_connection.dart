import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'log_service.dart';

/// Shared BLE connection helper with robust error 133 handling for Android.
///
/// Key insight: Android needs the device to be in its BLE cache (recently
/// scanned) before it can connect by MAC address. Without a recent scan,
/// connection fails with error 133 (GATT_ERROR).
///
/// Strategy:
/// 1. Quick scan to put device in Android's BLE cache
/// 2. Disconnect any stale connection
/// 3. Connect with retries and exponential backoff
/// 4. Clear GATT cache between retries
class BleConnection {
  static const int _maxRetries = 3;

  /// Connect to a BLE device with automatic retry on error 133.
  /// Does a quick scan first to warm up Android's BLE cache.
  static Future<List<BluetoothService>> connectAndDiscover(
    BluetoothDevice device,
  ) async {
    // Step 1: Quick scan to get device into Android BLE cache
    appLog('BLE', 'Warm-up scan pour ${device.remoteId}...');
    await _warmUpScan(device.remoteId.toString());

    // Step 2: Try connecting with retries
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        appLog('BLE', 'Connexion tentative $attempt/$_maxRetries...');
        return await _tryConnect(device, attempt);
      } catch (e) {
        appLog('BLE', '⚠ Tentative $attempt échouée: $e');
        await _safeDisconnect(device);

        final msg = e.toString();
        final isRetryable = msg.contains('133') ||
            msg.toLowerCase().contains('gatt') ||
            msg.contains('timed out') ||
            msg.contains('timeout');

        if (!isRetryable || attempt == _maxRetries) {
          throw Exception(
            'Connexion échouée après $attempt essai(s). '
            'Essayez de désactiver/réactiver le Bluetooth. '
            'Détail: $e',
          );
        }

        // Wait longer each retry: 3s, 5s
        await Future.delayed(Duration(seconds: 1 + attempt * 2));

        // Clear GATT cache before retrying
        try {
          await device.clearGattCache();
        } catch (_) {}
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    throw Exception('Connexion impossible');
  }

  /// Quick 5s scan to ensure the device is in Android's BLE cache.
  static Future<void> _warmUpScan(String targetMac) async {
    final mac = targetMac.toUpperCase();
    final completer = Completer<void>();

    // Stop any ongoing scan
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 500));

    StreamSubscription? sub;
    Timer? timer;

    sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.device.remoteId.toString().toUpperCase() == mac) {
          // Found it — device is now in Android's BLE cache
          if (!completer.isCompleted) completer.complete();
          return;
        }
      }
    });

    // Timeout after 10s — continue anyway even if not found
    timer = Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) completer.complete();
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } catch (_) {}

    await completer.future;
    timer.cancel();
    await sub.cancel();

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    // Small delay after scan before connecting
    await Future.delayed(const Duration(milliseconds: 500));
  }

  static Future<List<BluetoothService>> _tryConnect(
    BluetoothDevice device,
    int attempt,
  ) async {
    // Ensure clean state
    await _safeDisconnect(device);
    await Future.delayed(const Duration(seconds: 1));

    // Clear GATT cache BEFORE connecting — ensures Android re-discovers
    // all services (including Device Information 0x180A) from scratch.
    try {
      await device.clearGattCache();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 500));

    // Connect (30s timeout — Parrot Flower Power is slow)
    await device.connect(
      timeout: const Duration(seconds: 30),
      autoConnect: false,
      mtu: null,
    );

    // Wait for connection to stabilize
    await Future.delayed(const Duration(seconds: 2));

    // Request MTU (Mi Flora works fine with small MTU, but request anyway)
    try {
      await device.requestMtu(64);
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 300));

    // Discover services
    final services = await device.discoverServices();
    await Future.delayed(const Duration(milliseconds: 500));

    final uuids = services.map((s) {
      final u = s.uuid.toString().toLowerCase();
      // Show short form if standard 128-bit, otherwise full
      return u.length >= 8 ? u.substring(4, 8) : u;
    }).toList();
    appLog('BLE', '✓ ${services.length} services découverts: $uuids');

    if (services.isEmpty) {
      throw Exception('Aucun service BLE découvert');
    }

    return services;
  }

  /// Safely disconnect from a device, ignoring errors.
  static Future<void> safeDisconnect(BluetoothDevice device) async {
    await _safeDisconnect(device);
  }

  static Future<void> _safeDisconnect(BluetoothDevice device) async {
    try {
      await device.disconnect();
    } catch (_) {}
  }
}
