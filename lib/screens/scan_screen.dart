import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../models/plant_sensor.dart';
import '../models/plant_profile.dart';
import '../providers/sensor_provider.dart';
import '../services/ble_service.dart';
import '../widgets/ui_helpers.dart';
import 'plant_search_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final BleService _ble = BleService();
  List<ScanResult> _results = [];
  bool _scanning = false;
  String? _error;
  StreamSubscription? _scanSub;

  @override
  void initState() {
    super.initState();
    _scanSub = _ble.scanResults.listen((results) {
      if (mounted) {
        // Filter out sensors already registered
        final existingMacs = context
            .read<SensorProvider>()
            .sensors
            .map((s) => s.macAddress.toUpperCase())
            .toSet();
        final filtered = results
            .where((r) =>
                !existingMacs.contains(r.device.remoteId.toString().toUpperCase()))
            .toList();
        setState(() => _results = filtered);
      }
    });
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _error = null;
      _results = [];
    });

    // Request permissions
    final btScan = await Permission.bluetoothScan.request();
    final btConnect = await Permission.bluetoothConnect.request();
    final location = await Permission.locationWhenInUse.request();

    if (!btScan.isGranted || !btConnect.isGranted || !location.isGranted) {
      setState(() {
        _error =
            'Permissions Bluetooth et localisation requises pour scanner';
        _scanning = false;
      });
      return;
    }

    final btOn = await _ble.isBluetoothOn();
    if (!btOn) {
      setState(() {
        _error = 'Activez le Bluetooth pour scanner';
        _scanning = false;
      });
      return;
    }

    try {
      await _ble.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Erreur scan: $e');
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _addSensor(ScanResult result) async {
    final type = _ble.detectSensorType(result);
    if (type == null) return;

    final rawName = result.device.platformName;
    final cleanedName = rawName.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    final nameController = TextEditingController(
      text: cleanedName.isNotEmpty ? cleanedName : 'Capteur',
    );
    final plantController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajouter ce capteur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'MAC: ${result.device.remoteId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              type == SensorType.parrotFlowerPower
                  ? 'Parrot Flower Power'
                  : 'Xiaomi Mi Flora',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nom du capteur',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: plantController,
              decoration: const InputDecoration(
                labelText: 'Nom de la plante (optionnel)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final sensor = PlantSensor(
        name: nameController.text.trim().isEmpty
            ? 'Capteur'
            : nameController.text.trim(),
        macAddress: result.device.remoteId.toString().toUpperCase(),
        sensorType: type,
        plantName: plantController.text.trim().isEmpty
            ? null
            : plantController.text.trim(),
      );

      final saved = await context.read<SensorProvider>().addSensor(sensor);

      if (mounted) {
        // Remove from scan list immediately
        setState(() {
          _results.removeWhere((r) =>
              r.device.remoteId.toString().toUpperCase() ==
              sensor.macAddress.toUpperCase());
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${sensor.name} ajouté !'),
            backgroundColor: Colors.green,
          ),
        );

        // Propose to choose a plant profile
        _proposeChoosePlant(saved);
      }
    }
  }

  Future<void> _proposeChoosePlant(PlantSensor sensor) async {
    final choose = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Associer une plante ?'),
        content: const Text(
          'Voulez-vous associer un profil de plante à ce capteur pour surveiller les seuils idéaux ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Choisir'),
          ),
        ],
      ),
    );

    if (choose == true && mounted) {
      final profile = await Navigator.push<PlantProfile>(
        context,
        MaterialPageRoute(builder: (_) => const PlantSearchScreen()),
      );
      if (profile != null && mounted && sensor.id != null) {
        final provider = context.read<SensorProvider>();
        await provider.assignProfile(sensor.id!, profile.id);
        await provider.loadProfiles();
      }
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _ble.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Scanner BLE',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: appBackgroundGradient(context),
        child: SafeArea(
          child: Column(
            children: [
              if (_scanning)
                const LinearProgressIndicator(
                  color: Colors.white,
                  backgroundColor: Colors.white24,
                )
              else
                const SizedBox(height: 4),
              if (_error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade400.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.bluetooth_searching,
                        color: _scanning ? Colors.white : Colors.white70),
                    const SizedBox(width: 8),
                    Text(
                      _scanning
                          ? 'Recherche en cours...'
                          : '${_results.length} capteur(s) trouve(s)',
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, color: Colors.white),
                    ),
                    const Spacer(),
                    if (!_scanning)
                      TextButton.icon(
                        onPressed: _startScan,
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        label: const Text('Re-scanner',
                            style: TextStyle(color: Colors.white)),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _results.isEmpty && !_scanning
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bluetooth_disabled,
                                size: 48,
                                color: Colors.white.withValues(alpha: 0.5)),
                            const SizedBox(height: 8),
                            const Text('Aucun capteur detecte',
                                style: TextStyle(color: Colors.white)),
                            Text(
                              'Assurez-vous que vos capteurs sont a proximite',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final result = _results[index];
                          final type = _ble.detectSensorType(result);
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 3),
                            child: Material(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              child: ListTile(
                                leading: Icon(
                                  type == SensorType.parrotFlowerPower
                                      ? Icons.local_florist
                                      : Icons.grass,
                                  color: Colors.white,
                                ),
                                title: Text(
                                  result.device.platformName.isNotEmpty
                                      ? result.device.platformName
                                      : 'Inconnu',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  '${result.device.remoteId} - RSSI: ${result.rssi} dBm',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                trailing: FilledButton(
                                  onPressed: () => _addSensor(result),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF0288D1),
                                  ),
                                  child: const Text('Ajouter'),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
