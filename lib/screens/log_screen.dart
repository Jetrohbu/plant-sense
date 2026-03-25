import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/log_service.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final _log = LogService();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _log.addListener(_onLog);
  }

  @override
  void dispose() {
    _log.removeListener(_onLog);
    _scrollController.dispose();
    super.dispose();
  }

  void _onLog() {
    if (mounted) setState(() {});
    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lines = _log.lines;
    return Scaffold(
      appBar: AppBar(
        title: Text('Logs BLE (${lines.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copier tout',
            onPressed: lines.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: lines.join('\n')));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Logs copiés')),
                    );
                  },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Effacer',
            onPressed: lines.isEmpty
                ? null
                : () {
                    _log.clear();
                    setState(() {});
                  },
          ),
        ],
      ),
      body: lines.isEmpty
          ? const Center(
              child: Text(
                'Aucun log.\nLance une lecture de capteur pour voir les logs ici.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final line = lines[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: line.contains('⚠') || line.contains('erreur') || line.contains('ERREUR')
                          ? Colors.orange
                          : line.contains('✓')
                              ? Colors.green
                              : null,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
