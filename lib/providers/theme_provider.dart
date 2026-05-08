import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user-chosen seed color for the app's color scheme. Persisted
/// across launches via [SharedPreferences]. The value is read once on
/// startup; downstream widgets observe changes through [ChangeNotifier].
class ThemeProvider extends ChangeNotifier {
  static const String _prefKey = 'theme_seed_color';
  static const Color _defaultSeed = Color(0xFF2196F3);

  Color _seed = _defaultSeed;
  bool _loaded = false;

  Color get seed => _seed;
  bool get isLoaded => _loaded;

  /// Available preset colors offered in the settings picker.
  static const List<({String name, Color color})> presets = [
    (name: 'Bleu',     color: Color(0xFF2196F3)),
    (name: 'Vert',     color: Color(0xFF43A047)),
    (name: 'Teal',     color: Color(0xFF00897B)),
    (name: 'Indigo',   color: Color(0xFF3F51B5)),
    (name: 'Violet',   color: Color(0xFF7E57C2)),
    (name: 'Rose',     color: Color(0xFFE91E63)),
    (name: 'Rouge',    color: Color(0xFFE53935)),
    (name: 'Orange',   color: Color(0xFFFB8C00)),
    (name: 'Ambre',    color: Color(0xFFFFB300)),
    (name: 'Marron',   color: Color(0xFF6D4C41)),
    (name: 'Gris',     color: Color(0xFF607D8B)),
  ];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_prefKey);
    if (v != null) _seed = Color(v);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setSeed(Color c) async {
    if (c.toARGB32() == _seed.toARGB32()) return;
    _seed = c;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, c.toARGB32());
  }
}
