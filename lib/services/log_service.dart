import 'package:flutter/foundation.dart';

/// In-memory log buffer accessible from the settings screen.
class LogService {
  static final LogService _instance = LogService._();
  factory LogService() => _instance;
  LogService._();

  static const int _maxLines = 500;
  final List<String> _lines = [];
  final List<VoidCallback> _listeners = [];

  List<String> get lines => List.unmodifiable(_lines);
  int get length => _lines.length;

  void log(String tag, String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    final line = '$ts [$tag] $message';
    _lines.add(line);
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
    debugPrint(line);
    for (final cb in _listeners) {
      cb();
    }
  }

  void addListener(VoidCallback cb) => _listeners.add(cb);
  void removeListener(VoidCallback cb) => _listeners.remove(cb);

  void clear() {
    _lines.clear();
    for (final cb in _listeners) {
      cb();
    }
  }
}

/// Shorthand for logging from anywhere.
void appLog(String tag, String message) => LogService().log(tag, message);
