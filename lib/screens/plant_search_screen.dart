import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/plant_profile.dart';
import '../providers/sensor_provider.dart';
import '../services/database_service.dart';
import '../services/plant_api_service.dart';
import '../widgets/ui_helpers.dart';
import 'plant_profile_detail_screen.dart';

class PlantSearchScreen extends StatefulWidget {
  const PlantSearchScreen({super.key});

  @override
  State<PlantSearchScreen> createState() => _PlantSearchScreenState();
}

class _PlantSearchScreenState extends State<PlantSearchScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  final _db = DatabaseService();

  List<PlantProfile> _localResults = [];
  List<PlantProfile> _apiResults = [];
  bool _loadingLocal = true;
  bool _loadingApi = false;
  Timer? _debounce;

  // Filter mode: 0=Popularite, 1=Noms communs, 2=Nom scientifique
  int _filterMode = 0;

  PlantApiService? get _api {
    final providers = context.read<SensorProvider>().apiProviders;
    final active = providers.where((p) => p.enabled && p.apiKey.isNotEmpty).toList();
    if (active.isEmpty) return null;
    return PlantApiService.fromProvider(active.first);
  }

  bool get _hasActiveApi {
    final providers = context.read<SensorProvider>().apiProviders;
    return providers.any((p) => p.enabled && p.apiKey.isNotEmpty);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadLocalProfiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadLocalProfiles() async {
    setState(() => _loadingLocal = true);
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _localResults = await _db.getAllPlantProfiles();
    } else {
      _localResults = await _db.searchPlantProfiles(query);
    }
    // Sort based on filter mode
    if (_filterMode == 1) {
      _localResults.sort((a, b) => a.name.compareTo(b.name));
    } else if (_filterMode == 2) {
      _localResults.sort((a, b) =>
          (a.scientificName ?? '').compareTo(b.scientificName ?? ''));
    }
    if (!mounted) return;
    setState(() => _loadingLocal = false);
  }

  Future<void> _searchOnline(String query) async {
    if (query.trim().length < 2) {
      setState(() => _apiResults = []);
      return;
    }
    final providers = context.read<SensorProvider>().apiProviders;
    final active = providers.where((p) => p.enabled && p.apiKey.isNotEmpty).toList();
    if (active.isEmpty) {
      setState(() => _apiResults = []);
      return;
    }
    setState(() => _loadingApi = true);

    final allResults = <PlantProfile>[];
    for (final p in active) {
      try {
        final api = PlantApiService.fromProvider(p);
        final results = await api.searchPlants(query.trim());
        allResults.addAll(results);
      } catch (_) {}
    }

    _apiResults = allResults;
    if (!mounted) return;
    setState(() => _loadingApi = false);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _loadLocalProfiles();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _searchOnline(value);
    });
  }

  Future<void> _addApiPlantToLocal(PlantProfile profile) async {
    PlantProfile toSave = profile;
    final api = _api;
    if (profile.apiId != null && api != null) {
      final details = await api.getPlantDetails(profile.apiId!);
      if (details != null) {
        toSave = details;
      }
    }

    await _db.insertPlantProfile(toSave);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${toSave.name} ajoute a la base locale'),
          backgroundColor: const Color(0xFF0288D1),
        ),
      );
      _loadLocalProfiles();
    }
  }

  Future<void> _selectProfile(PlantProfile profile) async {
    if (profile.id == null) {
      PlantProfile toSave = profile;
      final api = _api;
      if (profile.apiId != null && api != null) {
        final details = await api.getPlantDetails(profile.apiId!);
        if (details != null) toSave = details;
      }
      final id = await _db.insertPlantProfile(toSave);
      final saved = toSave.copyWith(id: id);
      if (mounted) Navigator.pop(context, saved);
    } else {
      if (mounted) Navigator.pop(context, profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'PlantDB',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Mes profils'),
            Tab(text: 'Recherche en ligne'),
          ],
        ),
      ),
      body: Container(
        decoration: appBackgroundGradient(context),
        child: SafeArea(
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Recherche',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                    prefixIcon: Icon(Icons.search,
                        color: Colors.white.withValues(alpha: 0.7)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.15),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white70),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                  ),
                ),
              ),
              // Filter chips
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'Popularite',
                      selected: _filterMode == 0,
                      onTap: () {
                        setState(() => _filterMode = 0);
                        _loadLocalProfiles();
                      },
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Noms communs',
                      selected: _filterMode == 1,
                      onTap: () {
                        setState(() => _filterMode = 1);
                        _loadLocalProfiles();
                      },
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Nom scientifique',
                      selected: _filterMode == 2,
                      onTap: () {
                        setState(() => _filterMode = 2);
                        _loadLocalProfiles();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLocalTab(),
                    _buildOnlineTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocalTab() {
    if (_loadingLocal) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    if (_localResults.isEmpty) {
      return const Center(
        child: Text('Aucun profil trouve',
            style: TextStyle(color: Colors.white70)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _localResults.length,
      itemBuilder: (context, index) {
        final profile = _localResults[index];
        return _PlantListTile(
          profile: profile,
          onTap: () => _selectProfile(profile),
          onLongPress: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlantProfileDetailScreen(profile: profile),
              ),
            ).then((_) => _loadLocalProfiles());
          },
        );
      },
    );
  }

  Widget _buildOnlineTab() {
    if (!_hasActiveApi) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48,
                color: Colors.white.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            const Text('Aucun fournisseur API actif',
                style: TextStyle(color: Colors.white70)),
            const Text('Activez un fournisseur dans les parametres',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      );
    }
    if (_loadingApi) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    if (_searchController.text.trim().length < 2) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.travel_explore, size: 48,
                color: Colors.white.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            const Text('Tapez au moins 2 caracteres',
                style: TextStyle(color: Colors.white70)),
            const Text('pour rechercher en ligne',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      );
    }
    if (_apiResults.isEmpty) {
      return const Center(
        child: Text('Aucun resultat en ligne',
            style: TextStyle(color: Colors.white70)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _apiResults.length,
      itemBuilder: (context, index) {
        final profile = _apiResults[index];
        return _PlantListTile(
          profile: profile,
          onTap: () => _selectProfile(profile),
          trailing: IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.white),
            tooltip: 'Ajouter a ma base',
            onPressed: () => _addApiPlantToLocal(profile),
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _PlantListTile extends StatelessWidget {
  final PlantProfile profile;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  const _PlantListTile({
    required this.profile,
    required this.onTap,
    this.onLongPress,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                // Plant photo
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: profile.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: profile.imageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: Colors.white.withValues(alpha: 0.1),
                              child: const Center(
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white54),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.white.withValues(alpha: 0.1),
                              child: const Icon(Icons.eco,
                                  size: 24, color: Colors.white54),
                            ),
                          )
                        : Container(
                            color: Colors.white.withValues(alpha: 0.1),
                            child: const Icon(Icons.eco,
                                size: 24, color: Colors.white54),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                // Name + scientific name
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (profile.scientificName != null)
                        Text(
                          profile.scientificName!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing!
                else
                  // Blue circle indicator like Parrot app
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.2),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4)),
                    ),
                    child: const Icon(Icons.chevron_right,
                        size: 16, color: Colors.white70),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
