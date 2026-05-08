import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/api_provider.dart';
import '../providers/sensor_provider.dart';
import '../providers/theme_provider.dart';
import '../services/log_service.dart';
import 'log_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _keepDays = 30;

  Future<void> _showEditProviderDialog(
      BuildContext context, ApiProvider? existing) async {
    final provider = context.read<SensorProvider>();
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final urlCtrl = TextEditingController(text: existing?.baseUrl ?? '');
    final keyCtrl = TextEditingController(text: existing?.apiKey ?? '');
    String selectedType = existing?.type ?? 'perenual';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing != null
              ? 'Modifier le fournisseur'
              : 'Ajouter un fournisseur'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(
                        value: 'perenual', child: Text('Perenual')),
                    DropdownMenuItem(
                        value: 'trefle', child: Text('Trefle.io')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() => selectedType = v);
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(labelText: 'URL de base'),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: keyCtrl,
                  decoration: const InputDecoration(labelText: 'Clé API'),
                  obscureText: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      if (existing != null) {
        await provider.updateApiProvider(existing.copyWith(
          name: nameCtrl.text.trim(),
          baseUrl: urlCtrl.text.trim(),
          apiKey: keyCtrl.text.trim(),
          type: selectedType,
        ));
      } else {
        await provider.addApiProvider(ApiProvider(
          name: nameCtrl.text.trim(),
          baseUrl: urlCtrl.text.trim(),
          apiKey: keyCtrl.text.trim(),
          type: selectedType,
        ));
      }
    }
  }

  Future<void> _confirmDeleteProvider(
      BuildContext context, ApiProvider ap) async {
    final provider = context.read<SensorProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce fournisseur ?'),
        content: Text('Le fournisseur "${ap.name}" sera supprimé.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await provider.deleteApiProvider(ap.id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
      ),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Apparence'),
          const _ThemeColorPicker(),
          const _SectionHeader(title: 'Données'),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('Conserver l\'historique'),
            subtitle: Text('$_keepDays jours'),
            trailing: DropdownButton<int>(
              value: _keepDays,
              onChanged: (v) {
                if (v != null) setState(() => _keepDays = v);
              },
              items: const [
                DropdownMenuItem(value: 7, child: Text('7 jours')),
                DropdownMenuItem(value: 14, child: Text('14 jours')),
                DropdownMenuItem(value: 30, child: Text('30 jours')),
                DropdownMenuItem(value: 60, child: Text('60 jours')),
                DropdownMenuItem(value: 90, child: Text('90 jours')),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep, color: Colors.orange),
            title: const Text('Purger les anciennes données'),
            subtitle: Text('Supprimer les données de plus de $_keepDays jours'),
            onTap: () async {
              final provider = context.read<SensorProvider>();
              final messenger = ScaffoldMessenger.of(context);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Purger les données ?'),
                  content: Text(
                    'Toutes les mesures de plus de $_keepDays jours seront supprimées définitivement.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Annuler'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.red),
                      child: const Text('Purger'),
                    ),
                  ],
                ),
              );
              if (confirm == true && mounted) {
                await provider.purgeOldData(_keepDays);
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Données purgées'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
          ),
          const Divider(),
          const _SectionHeader(title: 'API'),
          Consumer<SensorProvider>(
            builder: (context, provider, _) {
              final providers = provider.apiProviders;
              return Column(
                children: [
                  for (final ap in providers)
                    ListTile(
                      leading: Icon(
                        ap.type == 'trefle' ? Icons.eco : Icons.cloud,
                      ),
                      title: Text(ap.name),
                      subtitle: Text(ap.baseUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Switch(
                        value: ap.enabled,
                        onChanged: (val) =>
                            provider.toggleApiProvider(ap.id!, val),
                      ),
                      onTap: () => _showEditProviderDialog(context, ap),
                      onLongPress: () => _confirmDeleteProvider(context, ap),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline,
                        color: Colors.green),
                    title: const Text('Ajouter un fournisseur'),
                    onTap: () => _showEditProviderDialog(context, null),
                  ),
                ],
              );
            },
          ),
          const Divider(),
          const _SectionHeader(title: 'Diagnostic'),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('Logs BLE'),
            subtitle: Text('${LogService().length} lignes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LogScreen()),
              );
            },
          ),
          const Divider(),
          const _SectionHeader(title: 'Informations'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('PlantSense'),
            subtitle: Text('Version 1.0.0'),
          ),
          const ListTile(
            leading: Icon(Icons.bluetooth),
            title: Text('Capteurs supportés'),
            subtitle: Text('Parrot Flower Power, Xiaomi Mi Flora (HHCCJCY01)'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _ThemeColorPicker extends StatelessWidget {
  const _ThemeColorPicker();

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, theme, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.palette_outlined, size: 20),
                    SizedBox(width: 12),
                    Text(
                      'Couleur du theme',
                      style: TextStyle(fontSize: 15),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: ThemeProvider.presets.map((p) {
                  final selected =
                      p.color.toARGB32() == theme.seed.toARGB32();
                  return InkWell(
                    onTap: () => theme.setSeed(p.color),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: p.color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: p.color.withValues(alpha: 0.35),
                            blurRadius: selected ? 10 : 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: selected
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 20)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}
