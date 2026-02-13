import 'package:flutter/material.dart';
import '../services/app_config.dart';
import 'model_settings_page.dart';

/// Debug settings page - only accessible in debug mode
/// This page allows developers to configure VLM prompts and other debug options
class DebugSettingsPage extends StatefulWidget {
  const DebugSettingsPage({super.key});

  @override
  State<DebugSettingsPage> createState() => _DebugSettingsPageState();
}

class _DebugSettingsPageState extends State<DebugSettingsPage> {
  final AppConfig _config = AppConfig.instance;
  late TextEditingController _scenePromptController;
  late TextEditingController _objectPromptController;

  @override
  void initState() {
    super.initState();
    _scenePromptController = TextEditingController(text: _config.scenePrompt);
    _objectPromptController = TextEditingController(text: _config.objectPrompt);
  }

  @override
  void dispose() {
    _scenePromptController.dispose();
    _objectPromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This page should never be shown in release mode
    if (!AppConfig.isDebugMode) {
      return const Scaffold(
        body: Center(child: Text('Debug settings not available')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.red[400],
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.bug_report, size: 24),
            SizedBox(width: 8),
            Text('Debug Settings'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            onPressed: _resetAll,
            tooltip: 'Reset all to defaults',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Warning banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[300]!),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Debug mode only. These settings are not visible in release builds.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Model Settings Section
          _buildSectionHeader('Model Management'),
          const SizedBox(height: 12),
          _buildCard(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.model_training,
                  color: Color(0xFFFF8C00),
                ),
                title: const Text('VLM Model Settings'),
                subtitle: const Text('Download and select VLM models'),
                trailing: const Icon(Icons.chevron_right),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ModelSettingsPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Scene Mode Prompt Section
          _buildSectionHeader('Scene Mode Prompt'),
          const SizedBox(height: 12),
          _buildCard(
            children: [
              const Text(
                'Scene Description Prompt',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Prompt for describing whole scenes (outputs a sentence).',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _scenePromptController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter scene mode prompt...',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.restore),
                    onPressed: () {
                      _scenePromptController.text =
                          AppConfig.defaultScenePrompt;
                      _config.resetScenePrompt();
                      setState(() {});
                    },
                    tooltip: 'Reset to default',
                  ),
                ),
                onChanged: (value) {
                  _config.scenePrompt = value;
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Object Mode Prompt Section
          _buildSectionHeader('Object Mode Prompt'),
          const SizedBox(height: 12),
          _buildCard(
            children: [
              const Text(
                'Object Identification Prompt',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Prompt for identifying segmented objects (outputs a single word).',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _objectPromptController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter object mode prompt...',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.restore),
                    onPressed: () {
                      _objectPromptController.text =
                          AppConfig.defaultObjectPrompt;
                      _config.resetObjectPrompt();
                      setState(() {});
                    },
                    tooltip: 'Reset to default',
                  ),
                ),
                onChanged: (value) {
                  _config.objectPrompt = value;
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Debug Options Section
          _buildSectionHeader('Debug Options'),
          const SizedBox(height: 12),
          _buildCard(
            children: [
              SwitchListTile(
                title: const Text('Show Performance Metrics'),
                subtitle: const Text('Display TTFT, tokens/s in result card'),
                value: _config.showPerformanceMetrics,
                onChanged: (value) {
                  setState(() {
                    _config.showPerformanceMetrics = value;
                  });
                },
                contentPadding: EdgeInsets.zero,
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('Verbose Logging'),
                subtitle: const Text('Enable detailed console logging'),
                value: _config.verboseLogging,
                onChanged: (value) {
                  setState(() {
                    _config.verboseLogging = value;
                  });
                },
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Current Config Display
          _buildSectionHeader('Current Configuration'),
          const SizedBox(height: 12),
          _buildCard(
            children: [
              _buildConfigRow(
                'Current Mode',
                _config.captureMode.name.toUpperCase(),
              ),
              _buildConfigRow(
                'Scene Prompt Length',
                '${_config.scenePrompt.length} chars',
              ),
              _buildConfigRow(
                'Object Prompt Length',
                '${_config.objectPrompt.length} chars',
              ),
              _buildConfigRow(
                'Show Perf Metrics',
                _config.showPerformanceMetrics.toString(),
              ),
              _buildConfigRow(
                'Verbose Logging',
                _config.verboseLogging.toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildConfigRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  void _resetAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset All Settings'),
        content: const Text(
          'Reset all debug settings to their default values?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _config.resetAllPrompts();
              _config.showPerformanceMetrics = false;
              _config.verboseLogging = false;
              _scenePromptController.text = _config.scenePrompt;
              _objectPromptController.text = _config.objectPrompt;
              setState(() {});
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}
