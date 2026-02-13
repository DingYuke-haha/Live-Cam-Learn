import 'package:flutter/material.dart';
import '../models/vlm_model.dart';
import '../services/model_manager.dart';
import '../services/app_config.dart';
import '../services/vlm_service.dart';

/// Model settings page for selecting and downloading VLM models
class ModelSettingsPage extends StatefulWidget {
  const ModelSettingsPage({super.key});

  @override
  State<ModelSettingsPage> createState() => _ModelSettingsPageState();
}

class _ModelSettingsPageState extends State<ModelSettingsPage> {
  final ModelManager _modelManager = ModelManager.instance;

  String? _selectedModelId;
  Map<String, ModelDownloadState> _modelStates = {};
  String? _downloadingModelId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadModelStates();
  }

  Future<void> _loadModelStates() async {
    setState(() => _isLoading = true);

    final selectedId = await _modelManager.getSelectedModelId();
    final states = <String, ModelDownloadState>{};

    for (final model in AvailableModels.all) {
      states[model.id] = await _modelManager.getModelState(model);
    }

    setState(() {
      _selectedModelId = selectedId;
      _modelStates = states;
      _isLoading = false;
    });
  }

  Future<void> _downloadModel(VlmModel model) async {
    setState(() {
      _downloadingModelId = model.id;
      _modelStates[model.id] = ModelDownloadState(
        status: ModelDownloadStatus.downloading,
        totalFiles: model.files.length,
      );
    });

    await _modelManager.downloadModel(
      model,
      onProgress: (fileName, received, total, progress) {
        setState(() {
          _modelStates[model.id] = ModelDownloadState(
            status: ModelDownloadStatus.downloading,
            progress: progress,
            currentFile: fileName,
            totalFiles: model.files.length,
            downloadedFiles: (progress * model.files.length).floor(),
          );
        });
      },
      onComplete: () {
        setState(() {
          _modelStates[model.id] = ModelDownloadState(
            status: ModelDownloadStatus.downloaded,
            progress: 1.0,
            totalFiles: model.files.length,
            downloadedFiles: model.files.length,
          );
          _downloadingModelId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${model.displayName} downloaded successfully!'),
          ),
        );
      },
      onError: (error) {
        setState(() {
          _modelStates[model.id] = ModelDownloadState(
            status: ModelDownloadStatus.error,
            errorMessage: error,
            totalFiles: model.files.length,
          );
          _downloadingModelId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $error'),
            backgroundColor: Colors.red,
          ),
        );
      },
    );
  }

  Future<void> _deleteModel(VlmModel model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Model'),
        content: Text(
          'Delete ${model.displayName}? You will need to download it again to use it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _modelManager.deleteModel(model);
      if (success) {
        setState(() {
          _modelStates[model.id] = const ModelDownloadState(
            status: ModelDownloadStatus.notDownloaded,
          );
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${model.displayName} deleted')),
          );
        }
      }
    }
  }

  Future<void> _selectModel(VlmModel model) async {
    final state = _modelStates[model.id];
    if (state?.status != ModelDownloadStatus.downloaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please download the model first')),
      );
      return;
    }

    // If already selected, do nothing
    if (_selectedModelId == model.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${model.displayName} is already selected')),
      );
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text('Switching to ${model.displayName}...')),
          ],
        ),
      ),
    );

    try {
      // Release current model
      await VlmService.instance.release();

      // Update selected model ID
      await _modelManager.setSelectedModelId(model.id);
      AppConfig.instance.clearCachedModel();

      // Get model paths
      final modelPath = await _modelManager.getMainModelPath(model);
      final mmprojPath = await _modelManager.getMmprojPath(model);

      // Load the new model
      final result = await VlmService.instance.loadModel(
        modelPath: modelPath,
        mmprojPath: mmprojPath,
        pluginId: model.pluginId,
        deviceId: model.deviceId,
      );

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      if (result.success) {
        setState(() {
          _selectedModelId = model.id;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${model.displayName} loaded successfully!'),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load model: ${result.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error switching model: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _cancelDownload() {
    _modelManager.cancelDownload();
    setState(() {
      if (_downloadingModelId != null) {
        _modelStates[_downloadingModelId!] = const ModelDownloadState(
          status: ModelDownloadStatus.notDownloaded,
        );
        _downloadingModelId = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFD54F),
        foregroundColor: Colors.black87,
        title: const Text('Model Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Info banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Select and download VLM models. NPU models require Snapdragon processor.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Model cards
                ...AvailableModels.all.map((model) => _buildModelCard(model)),
              ],
            ),
    );
  }

  Widget _buildModelCard(VlmModel model) {
    final state = _modelStates[model.id] ?? const ModelDownloadState();
    final isSelected = _selectedModelId == model.id;
    final isDownloading = _downloadingModelId == model.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isSelected
            ? Border.all(color: const Color(0xFFFF8C00), width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          ListTile(
            leading: _buildModelIcon(model, state),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    model.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD54F),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Selected',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  model.description,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildTag(
                      model.isNpuModel ? 'NPU' : 'CPU/GPU',
                      model.isNpuModel ? Colors.purple : Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    _buildTag(model.fileSize, Colors.grey),
                    const SizedBox(width: 8),
                    _buildTag('${model.files.length} files', Colors.grey),
                  ],
                ),
              ],
            ),
            trailing: _buildActionButton(model, state, isDownloading),
            onTap: state.status == ModelDownloadStatus.downloaded
                ? () => _selectModel(model)
                : null,
          ),

          // Progress bar (when downloading)
          if (isDownloading) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: state.progress,
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation(Color(0xFFFF8C00)),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        state.currentFile ?? 'Starting...',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      Text(
                        '${(state.progress * 100).toStringAsFixed(1)}%',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton(
                onPressed: _cancelDownload,
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ),
          ],

          // Error message
          if (state.status == ModelDownloadStatus.error)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.errorMessage ?? 'Download failed',
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModelIcon(VlmModel model, ModelDownloadState state) {
    IconData icon;
    Color color;

    switch (state.status) {
      case ModelDownloadStatus.downloaded:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case ModelDownloadStatus.downloading:
        icon = Icons.downloading;
        color = Colors.orange;
        break;
      case ModelDownloadStatus.error:
        icon = Icons.error;
        color = Colors.red;
        break;
      case ModelDownloadStatus.notDownloaded:
        icon = model.isNpuModel ? Icons.memory : Icons.computer;
        color = Colors.grey;
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget? _buildActionButton(
    VlmModel model,
    ModelDownloadState state,
    bool isDownloading,
  ) {
    if (isDownloading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    switch (state.status) {
      case ModelDownloadStatus.downloaded:
        return PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'delete') {
              _deleteModel(model);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        );
      case ModelDownloadStatus.notDownloaded:
      case ModelDownloadStatus.error:
        return ElevatedButton(
          onPressed: _downloadingModelId == null
              ? () => _downloadModel(model)
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFD54F),
            foregroundColor: Colors.black87,
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: const Text('Download'),
        );
      default:
        return null;
    }
  }
}
