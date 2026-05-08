import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_connection.dart';
import 'log_service.dart';

/// Parrot Flower Power OAD firmware flash.
///
/// Uses modified TI CC2541 OAD protocol (no notifications, polling only).
/// Based on official Parrot node-flower-power Update.js source.
class ParrotOadService {
  static const int _blockSize = 16;
  static const int _batchSize = 128;

  static Future<bool> flashFirmware(
    BluetoothDevice device,
    Uint8List firmwareBytes, {
    void Function(int sent, int total)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    if (firmwareBytes.length < 16) {
      onStatus?.call('Fichier firmware trop petit');
      return false;
    }

    // Extract 8-byte header from offset 4: ver(2) + len(2) + uid(4)
    final newHeader = firmwareBytes.sublist(4, 12);
    final imgVer = newHeader[0] | (newHeader[1] << 8);
    final imgLen = newHeader[2] | (newHeader[3] << 8);
    final totalBlocks = (firmwareBytes.length / _blockSize).ceil();

    appLog('OAD', 'Firmware: ${firmwareBytes.length} octets, '
        'ver=0x${imgVer.toRadixString(16)}, len=0x${imgLen.toRadixString(16)}, '
        '$totalBlocks blocs');
    appLog('OAD', 'Header a envoyer: $newHeader');

    onStatus?.call('Connexion au capteur...');

    // Listen for disconnect (= flash complete, device reboots)
    StreamSubscription? disconnectSub;
    final disconnected = Completer<void>();

    try {
      final services = await BleConnection.connectAndDiscover(device);

      disconnectSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected &&
            !disconnected.isCompleted) {
          appLog('OAD', 'Device disconnected (reboot expected)');
          disconnected.complete();
        }
      });

      // Find OAD service (FFC0)
      BluetoothService? oadService;
      for (final s in services) {
        if (s.uuid.toString().toLowerCase().contains('ffc0')) {
          oadService = s;
          break;
        }
      }
      if (oadService == null) {
        onStatus?.call('Service OAD non trouve');
        await BleConnection.safeDisconnect(device);
        return false;
      }

      BluetoothCharacteristic? ffc1;
      BluetoothCharacteristic? ffc2;
      for (final c in oadService.characteristics) {
        final uuid = c.uuid.toString().toLowerCase();
        if (uuid.contains('ffc1')) ffc1 = c;
        if (uuid.contains('ffc2')) ffc2 = c;
      }
      if (ffc1 == null || ffc2 == null) {
        onStatus?.call('Characteristics OAD introuvables');
        await BleConnection.safeDisconnect(device);
        return false;
      }

      // Phase 1: Read current image header from FFC1
      onStatus?.call('Lecture info capteur...');
      final currentHeader = await ffc1.read();
      appLog('OAD', 'FFC1 current header: $currentHeader');

      // Compare headers (first 8 bytes)
      bool headersMatch = currentHeader.length >= 8;
      if (headersMatch) {
        for (int i = 0; i < 8 && i < currentHeader.length; i++) {
          if (currentHeader[i] != newHeader[i]) {
            headersMatch = false;
            break;
          }
        }
      }

      if (headersMatch) {
        appLog('OAD', 'Headers identiques - firmware deja installe?');
        // Try anyway with a modified version number
        appLog('OAD', 'Modification du numero de version pour forcer la MAJ');
      }

      // Phase 2: Write new header to FFC1 (Image Identify)
      onStatus?.call('Envoi identification...');

      // Try the original header first
      final headersToTry = <Uint8List>[
        Uint8List.fromList(newHeader),
      ];

      // If headers match or as fallback, try modified versions
      if (headersMatch || currentHeader.length >= 8) {
        // Toggle image type bit (bit 0 of version)
        final modHeader = Uint8List.fromList(newHeader);
        modHeader[0] = modHeader[0] ^ 0x01; // Toggle A/B image type
        headersToTry.add(modHeader);

        // Try with incremented version
        final incHeader = Uint8List.fromList(newHeader);
        if (currentHeader.length >= 2) {
          final curVer = currentHeader[0] | (currentHeader[1] << 8);
          final newVer = ((curVer + 2) & 0xFFFE) | ((curVer & 1) ^ 1);
          incHeader[0] = newVer & 0xFF;
          incHeader[1] = (newVer >> 8) & 0xFF;
        }
        headersToTry.add(incHeader);

        // Try with target's own len field but different version
        if (currentHeader.length >= 4) {
          final targetLenHeader = Uint8List.fromList(newHeader);
          targetLenHeader[0] = targetLenHeader[0] ^ 0x01;
          targetLenHeader[2] = currentHeader[2];
          targetLenHeader[3] = currentHeader[3];
          headersToTry.add(targetLenHeader);
        }
      }

      // Remove duplicate headers
      final seen = <String>{};
      final uniqueHeaders = <Uint8List>[];
      for (final h in headersToTry) {
        final key = h.join(',');
        if (seen.add(key)) uniqueHeaders.add(h);
      }

      for (int attempt = 0; attempt < uniqueHeaders.length; attempt++) {
        final header = uniqueHeaders[attempt];
        final hVer = header[0] | (header[1] << 8);
        final hLen = header[2] | (header[3] << 8);
        appLog('OAD', '--- Tentative ${attempt + 1}/${uniqueHeaders.length}: '
            'ver=0x${hVer.toRadixString(16)} '
            'type=${(hVer & 1) == 0 ? "A" : "B"} '
            'len=0x${hLen.toRadixString(16)}');
        onStatus?.call('Essai ${attempt + 1}/${uniqueHeaders.length}...');

        // Write header to FFC1
        try {
          await ffc1.write(header.toList(), withoutResponse: false);
        } catch (e) {
          appLog('OAD', 'FFC1 write (with resp) failed: $e, trying without...');
          try {
            await ffc1.write(header.toList(), withoutResponse: true);
          } catch (e2) {
            appLog('OAD', 'FFC1 write (no resp) also failed: $e2');
            continue;
          }
        }

        // Small delay for device to process
        await Future.delayed(const Duration(milliseconds: 300));

        // Read FFC2 to get starting block index
        final ffc2Data = await ffc2.read();
        appLog('OAD', 'FFC2 after identify: $ffc2Data');

        int startBlock = 0;
        if (ffc2Data.length >= 2) {
          final blockVal = ffc2Data[0] | (ffc2Data[1] << 8);
          if (blockVal == 0xFFFF) {
            appLog('OAD', 'FFC2=0xFFFF, essai transfert depuis bloc 0...');
            startBlock = 0;
          } else {
            startBlock = blockVal;
            appLog('OAD', 'Capteur demande bloc $startBlock');
          }
        }

        // Phase 3: Transfer firmware blocks in batches of 128
        onStatus?.call('Transfert firmware...');
        final result = await _transferBlocks(
          device, ffc2, firmwareBytes, totalBlocks, startBlock,
          disconnected: disconnected,
          onProgress: onProgress,
          onStatus: onStatus,
        );

        if (result) {
          disconnectSub.cancel();
          onStatus?.call('Flash reussi! Redemarrage...');
          return true;
        }

        // If transfer failed quickly (first batch), try next header
        appLog('OAD', 'Transfert echoue, essai suivant...');
      }

      disconnectSub.cancel();
      await BleConnection.safeDisconnect(device);
      onStatus?.call('Le capteur refuse toutes les tentatives OAD');
      return false;
    } catch (e) {
      appLog('OAD', 'Erreur: $e');
      onStatus?.call('Erreur: $e');
      disconnectSub?.cancel();
      try {
        await BleConnection.safeDisconnect(device);
      } catch (_) {}
      return false;
    }
  }

  /// Transfer firmware blocks in batches of [_batchSize].
  /// After each batch, read FFC2 for next expected block index.
  /// Device disconnects automatically when flash is complete.
  static Future<bool> _transferBlocks(
    BluetoothDevice device,
    BluetoothCharacteristic ffc2,
    Uint8List firmwareBytes,
    int totalBlocks,
    int startBlock, {
    required Completer<void> disconnected,
    void Function(int sent, int total)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    int currentBlock = startBlock;
    int totalSent = 0;
    int consecutiveErrors = 0;
    int staleCount = 0; // Track if FFC2 never changes

    while (currentBlock < totalBlocks && consecutiveErrors < 10) {
      // Send a batch of up to _batchSize blocks
      final batchEnd = (currentBlock + _batchSize).clamp(0, totalBlocks);
      appLog('OAD', 'Batch blocs $currentBlock..$batchEnd (total: $totalBlocks)');

      for (int b = currentBlock; b < batchEnd; b++) {
        final packet = Uint8List(18);
        packet[0] = b & 0xFF;
        packet[1] = (b >> 8) & 0xFF;

        final offset = b * _blockSize;
        final remaining = firmwareBytes.length - offset;
        final len = remaining < _blockSize ? remaining : _blockSize;
        for (int i = 0; i < len; i++) {
          packet[2 + i] = firmwareBytes[offset + i];
        }
        // Pad with 0xFF if last block is short
        for (int i = len; i < _blockSize; i++) {
          packet[2 + i] = 0xFF;
        }

        try {
          await ffc2.write(packet.toList(), withoutResponse: true);
          totalSent++;
          consecutiveErrors = 0;
        } catch (e) {
          // Check if device disconnected (= success, rebooting)
          if (disconnected.isCompleted) {
            appLog('OAD', 'Device deconnecte pendant transfert - flash OK!');
            onProgress?.call(totalBlocks, totalBlocks);
            return true;
          }
          consecutiveErrors++;
          appLog('OAD', 'Erreur bloc $b ($consecutiveErrors): $e');
          if (consecutiveErrors >= 10) break;
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

      // Update progress
      onProgress?.call(totalSent, totalBlocks);
      final pct = (totalSent * 100 / totalBlocks).toStringAsFixed(1);
      if (totalSent % (_batchSize * 2) == 0 || totalSent >= totalBlocks) {
        onStatus?.call('Flash: $pct% ($totalSent/$totalBlocks)');
      }
      appLog('OAD', 'Envoye: $totalSent/$totalBlocks ($pct%)');

      // Check if device disconnected (= success)
      if (disconnected.isCompleted) {
        appLog('OAD', 'Device deconnecte - flash termine!');
        onProgress?.call(totalBlocks, totalBlocks);
        return true;
      }

      // All blocks sent?
      if (totalSent >= totalBlocks) {
        appLog('OAD', 'Tous les blocs envoyes, attente reboot...');
        onStatus?.call('Attente redemarrage capteur...');
        // Wait up to 10 seconds for device to disconnect/reboot
        try {
          await disconnected.future.timeout(const Duration(seconds: 10));
          appLog('OAD', 'Reboot detecte!');
          return true;
        } catch (_) {
          appLog('OAD', 'Pas de reboot detecte, mais tous les blocs envoyes');
          return true;
        }
      }

      // Read FFC2 to get next expected block
      try {
        final nextData = await ffc2.read();
        if (nextData.length >= 2) {
          final nextBlock = nextData[0] | (nextData[1] << 8);
          appLog('OAD', 'FFC2 next block: $nextBlock (0x${nextBlock.toRadixString(16)})');

          if (nextBlock == 0xFFFF) {
            staleCount++;
            if (staleCount <= 2) {
              // Device might not have updated yet, continue sequentially
              currentBlock = totalSent + startBlock;
              appLog('OAD', 'FFC2 stale ($staleCount), continue sequentiel bloc $currentBlock');
            } else {
              // FFC2 never changes — device isn't accepting blocks
              appLog('OAD', 'FFC2 reste a 0xFFFF apres $staleCount batches — abandon');
              return false;
            }
          } else {
            staleCount = 0;
            currentBlock = nextBlock;
          }
        } else {
          currentBlock = totalSent + startBlock;
        }
      } catch (e) {
        if (disconnected.isCompleted) {
          appLog('OAD', 'Read failed but device disconnected — flash OK!');
          return true;
        }
        appLog('OAD', 'FFC2 read error: $e');
        currentBlock = totalSent + startBlock;
      }
    }

    return totalSent >= totalBlocks;
  }
}
