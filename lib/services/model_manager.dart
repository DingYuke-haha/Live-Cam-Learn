import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vlm_model.dart';

/// Download progress callback
typedef DownloadProgressCallback =
    void Function(String fileName, int received, int total, double progress);

/// Download status for a model
enum ModelDownloadStatus { notDownloaded, downloading, downloaded, error }

/// Model download state
class ModelDownloadState {
  final ModelDownloadStatus status;
  final double progress;
  final String? currentFile;
  final String? errorMessage;
  final int downloadedFiles;
  final int totalFiles;

  const ModelDownloadState({
    this.status = ModelDownloadStatus.notDownloaded,
    this.progress = 0.0,
    this.currentFile,
    this.errorMessage,
    this.downloadedFiles = 0,
    this.totalFiles = 0,
  });

  ModelDownloadState copyWith({
    ModelDownloadStatus? status,
    double? progress,
    String? currentFile,
    String? errorMessage,
    int? downloadedFiles,
    int? totalFiles,
  }) {
    return ModelDownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      currentFile: currentFile ?? this.currentFile,
      errorMessage: errorMessage,
      downloadedFiles: downloadedFiles ?? this.downloadedFiles,
      totalFiles: totalFiles ?? this.totalFiles,
    );
  }
}

/// Manages VLM model downloads and storage
class ModelManager {
  static const String _selectedModelKey = 'selected_vlm_model';
  static const String _modelsDir = 'models';

  final Dio _dio;
  CancelToken? _currentCancelToken;

  // Singleton
  static final ModelManager _instance = ModelManager._internal();
  static ModelManager get instance => _instance;

  ModelManager._internal() : _dio = Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(minutes: 30);
  }

  /// Get the models directory path
  /// Uses getApplicationSupportDirectory() which maps to files/ on Android
  Future<String> get modelsDirectoryPath async {
    final appDir = await getApplicationSupportDirectory();
    return '${appDir.path}/$_modelsDir';
  }

  /// Get the directory path for a specific model
  /// Uses the model's folder name (repo name) as the directory name
  /// e.g., "OmniNeural-4B-mobile", "SmolVLM-256M-Instruct-GGUF"
  Future<String> getModelDirectoryPath(VlmModel model) async {
    final baseDir = await modelsDirectoryPath;
    return '$baseDir/${model.folderName}';
  }

  /// Get the full path to the main model file
  /// For NPU models: returns path to files-1-1.nexa
  /// For GGUF models: returns path to the .gguf model file
  Future<String?> getMainModelPath(VlmModel model) async {
    final modelDir = await getModelDirectoryPath(model);
    if (model.mainModelFile != null) {
      return '$modelDir/${model.mainModelFile}';
    }
    // Fallback: return directory path for NPU models
    return modelDir;
  }

  /// Get the full path to the mmproj file
  Future<String?> getMmprojPath(VlmModel model) async {
    if (model.mmprojFile == null) return null;
    final modelDir = await getModelDirectoryPath(model);
    return '$modelDir/${model.mmprojFile}';
  }

  /// Check if a model is downloaded (all files exist)
  Future<bool> isModelDownloaded(VlmModel model) async {
    final modelDir = await getModelDirectoryPath(model);
    final dir = Directory(modelDir);

    if (!await dir.exists()) {
      debugPrint('Model ${model.folderName}: Directory does not exist');
      return false;
    }

    // Check if all required files exist
    for (final fileName in model.files) {
      final file = File('$modelDir/$fileName');
      if (!await file.exists()) {
        debugPrint('Model ${model.folderName}: Missing file $fileName');
        return false;
      }
    }

    debugPrint(
      'Model ${model.folderName}: All ${model.files.length} files present',
    );
    return true;
  }

  /// Get download state for a model
  Future<ModelDownloadState> getModelState(VlmModel model) async {
    final isDownloaded = await isModelDownloaded(model);
    return ModelDownloadState(
      status: isDownloaded
          ? ModelDownloadStatus.downloaded
          : ModelDownloadStatus.notDownloaded,
      totalFiles: model.files.length,
      downloadedFiles: isDownloaded ? model.files.length : 0,
    );
  }

  /// Download a model with progress callback
  Future<bool> downloadModel(
    VlmModel model, {
    DownloadProgressCallback? onProgress,
    VoidCallback? onComplete,
    Function(String)? onError,
  }) async {
    try {
      // Create model directory
      final modelDir = await getModelDirectoryPath(model);
      final dir = Directory(modelDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _currentCancelToken = CancelToken();
      final totalFiles = model.files.length;

      for (int i = 0; i < totalFiles; i++) {
        final fileName = model.files[i];
        final filePath = '$modelDir/$fileName';
        final file = File(filePath);

        // Skip if file already exists
        if (await file.exists()) {
          debugPrint('File $fileName already exists, skipping');
          onProgress?.call(fileName, 1, 1, (i + 1) / totalFiles);
          continue;
        }

        final url = model.getFileDownloadUrl(fileName);
        debugPrint('Downloading: $url');

        try {
          await _dio.download(
            url,
            filePath,
            cancelToken: _currentCancelToken,
            onReceiveProgress: (received, total) {
              if (total != -1) {
                final fileProgress = received / total;
                final overallProgress = (i + fileProgress) / totalFiles;
                onProgress?.call(fileName, received, total, overallProgress);
              }
            },
            options: Options(
              headers: {
                'User-Agent': 'Mozilla/5.0 (compatible; LiveCamLearn/1.0)',
              },
            ),
          );
        } catch (e) {
          // Clean up partial file
          if (await file.exists()) {
            await file.delete();
          }
          rethrow;
        }
      }

      _currentCancelToken = null;
      onComplete?.call();
      return true;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        debugPrint('Download cancelled');
        onError?.call('Download cancelled');
      } else {
        debugPrint('Download error: ${e.message}');
        onError?.call(e.message ?? 'Download failed');
      }
      return false;
    } catch (e) {
      debugPrint('Download error: $e');
      onError?.call(e.toString());
      return false;
    }
  }

  /// Cancel current download
  void cancelDownload() {
    _currentCancelToken?.cancel('User cancelled');
    _currentCancelToken = null;
  }

  /// Delete a downloaded model
  Future<bool> deleteModel(VlmModel model) async {
    try {
      final modelDir = await getModelDirectoryPath(model);
      final dir = Directory(modelDir);

      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }

      return true;
    } catch (e) {
      debugPrint('Error deleting model: $e');
      return false;
    }
  }

  /// Get the selected model ID from preferences
  Future<String> getSelectedModelId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedModelKey) ??
        AvailableModels.defaultModel.id;
  }

  /// Set the selected model ID in preferences
  Future<void> setSelectedModelId(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedModelKey, modelId);
  }

  /// Get the currently selected model
  Future<VlmModel> getSelectedModel() async {
    final modelId = await getSelectedModelId();
    return AvailableModels.getById(modelId) ?? AvailableModels.defaultModel;
  }

  /// Get disk space used by all models
  Future<int> getTotalModelSize() async {
    int totalSize = 0;
    final baseDir = await modelsDirectoryPath;
    final dir = Directory(baseDir);

    if (!await dir.exists()) return 0;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }

    return totalSize;
  }

  /// Format bytes to human readable string
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
