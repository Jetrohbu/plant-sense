import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/plant_profile.dart';
import '../services/database_service.dart';

class PlantProfileDetailScreen extends StatefulWidget {
  final PlantProfile profile;

  const PlantProfileDetailScreen({super.key, required this.profile});

  @override
  State<PlantProfileDetailScreen> createState() =>
      _PlantProfileDetailScreenState();
}

class _PlantProfileDetailScreenState extends State<PlantProfileDetailScreen> {
  late PlantProfile _profile;
  bool _editing = false;

  late TextEditingController _tempMinCtrl;
  late TextEditingController _tempMaxCtrl;
  late TextEditingController _moistMinCtrl;
  late TextEditingController _moistMaxCtrl;
  late TextEditingController _lightMinCtrl;
  late TextEditingController _lightMaxCtrl;
  late TextEditingController _condMinCtrl;
  late TextEditingController _condMaxCtrl;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _initControllers();
  }

  void _initControllers() {
    _tempMinCtrl =
        TextEditingController(text: _profile.temperatureMin.toStringAsFixed(0));
    _tempMaxCtrl =
        TextEditingController(text: _profile.temperatureMax.toStringAsFixed(0));
    _moistMinCtrl =
        TextEditingController(text: _profile.moistureMin.toStringAsFixed(0));
    _moistMaxCtrl =
        TextEditingController(text: _profile.moistureMax.toStringAsFixed(0));
    _lightMinCtrl =
        TextEditingController(text: _profile.lightMin.toStringAsFixed(0));
    _lightMaxCtrl =
        TextEditingController(text: _profile.lightMax.toStringAsFixed(0));
    _condMinCtrl = TextEditingController(
        text: _profile.conductivityMin.toStringAsFixed(0));
    _condMaxCtrl = TextEditingController(
        text: _profile.conductivityMax.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _tempMinCtrl.dispose();
    _tempMaxCtrl.dispose();
    _moistMinCtrl.dispose();
    _moistMaxCtrl.dispose();
    _lightMinCtrl.dispose();
    _lightMaxCtrl.dispose();
    _condMinCtrl.dispose();
    _condMaxCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveEdits() async {
    final updated = _profile.copyWith(
      temperatureMin: double.tryParse(_tempMinCtrl.text) ?? _profile.temperatureMin,
      temperatureMax: double.tryParse(_tempMaxCtrl.text) ?? _profile.temperatureMax,
      moistureMin: double.tryParse(_moistMinCtrl.text) ?? _profile.moistureMin,
      moistureMax: double.tryParse(_moistMaxCtrl.text) ?? _profile.moistureMax,
      lightMin: double.tryParse(_lightMinCtrl.text) ?? _profile.lightMin,
      lightMax: double.tryParse(_lightMaxCtrl.text) ?? _profile.lightMax,
      conductivityMin: double.tryParse(_condMinCtrl.text) ?? _profile.conductivityMin,
      conductivityMax: double.tryParse(_condMaxCtrl.text) ?? _profile.conductivityMax,
    );

    if (_profile.id != null) {
      await DatabaseService().updatePlantProfile(updated);
    }

    setState(() {
      _profile = updated;
      _editing = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seuils mis à jour'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  String _categoryLabel(PlantCategory cat) {
    switch (cat) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_profile.name),
        actions: [
          if (_profile.id != null)
            IconButton(
              icon: Icon(_editing ? Icons.close : Icons.edit),
              onPressed: () {
                if (_editing) {
                  _initControllers();
                }
                setState(() => _editing = !_editing);
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Photo
            SizedBox(
              height: 250,
              child: _profile.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: _profile.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: Colors.green.shade50,
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.green.shade50,
                        child: const Icon(Icons.eco,
                            size: 64, color: Colors.green),
                      ),
                    )
                  : Container(
                      color: Colors.green.shade50,
                      child:
                          const Icon(Icons.eco, size: 64, color: Colors.green),
                    ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name & info
                  Text(
                    _profile.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (_profile.scientificName != null)
                    Text(
                      _profile.scientificName!,
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Chip(
                    label: Text(_categoryLabel(_profile.category)),
                    avatar: const Icon(Icons.category, size: 16),
                  ),
                  const SizedBox(height: 24),

                  // Thresholds
                  Text(
                    'Seuils idéaux',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),

                  _ThresholdRow(
                    icon: Icons.thermostat,
                    label: 'Température',
                    unit: '°C',
                    color: Colors.deepOrange,
                    minCtrl: _tempMinCtrl,
                    maxCtrl: _tempMaxCtrl,
                    editing: _editing,
                  ),
                  _ThresholdRow(
                    icon: Icons.water_drop,
                    label: 'Humidité sol',
                    unit: '%',
                    color: Colors.blue,
                    minCtrl: _moistMinCtrl,
                    maxCtrl: _moistMaxCtrl,
                    editing: _editing,
                  ),
                  _ThresholdRow(
                    icon: Icons.light_mode,
                    label: 'Lumière',
                    unit: 'lux',
                    color: Colors.amber.shade700,
                    minCtrl: _lightMinCtrl,
                    maxCtrl: _lightMaxCtrl,
                    editing: _editing,
                  ),
                  _ThresholdRow(
                    icon: Icons.electric_bolt,
                    label: 'Conductivité',
                    unit: 'µS/cm',
                    color: Colors.purple,
                    minCtrl: _condMinCtrl,
                    maxCtrl: _condMaxCtrl,
                    editing: _editing,
                  ),

                  if (_editing) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saveEdits,
                        icon: const Icon(Icons.save),
                        label: const Text('Enregistrer'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThresholdRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String unit;
  final Color color;
  final TextEditingController minCtrl;
  final TextEditingController maxCtrl;
  final bool editing;

  const _ThresholdRow({
    required this.icon,
    required this.label,
    required this.unit,
    required this.color,
    required this.minCtrl,
    required this.maxCtrl,
    required this.editing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          if (editing) ...[
            SizedBox(
              width: 60,
              child: TextField(
                controller: minCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('—'),
            ),
            SizedBox(
              width: 60,
              child: TextField(
                controller: maxCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 4),
            Text(unit,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ] else ...[
            Text(
              '${minCtrl.text} — ${maxCtrl.text} $unit',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
