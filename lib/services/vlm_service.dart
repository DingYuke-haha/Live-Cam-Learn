import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// VLM (Vision Language Model) Service
/// Provides interface to communicate with Nexa SDK VLM on Android
class VlmService {
  static const MethodChannel _methodChannel = MethodChannel(
    'com.nexa.live_cam_learn/vlm',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.nexa.live_cam_learn/vlm_stream',
  );

  static VlmService? _instance;
  StreamSubscription? _streamSubscription;

  // Callbacks for streaming responses
  Function(String token)? onToken;
  Function(String fullResponse, PerformanceProfile? profile)? onComplete;
  Function(String error)? onError;
  Function(bool success, String? reason)? onSdkInit;

  // Callbacks for model auto-reload (after camera)
  Function(String message)? onModelReloading;
  Function(bool success)? onModelReloaded;

  // Callbacks for TTS events
  Function(String utteranceId)? onTtsStart;
  Function(String utteranceId)? onTtsDone;
  Function(String utteranceId, String error)? onTtsError;

  // Track model loading state to prevent duplicate loads
  Future<VlmResult>? _loadingFuture;
  bool get isLoading => _loadingFuture != null;

  VlmService._();

  /// Get singleton instance
  static VlmService get instance {
    _instance ??= VlmService._();
    return _instance!;
  }

  /// Initialize stream listener
  void initStreamListener() {
    _streamSubscription?.cancel();
    _streamSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final type = event['type'] as String?;
          final data = event['data'];

          switch (type) {
            case 'sdk_init':
              final dataStr = data as String?;
              if (dataStr == 'success') {
                onSdkInit?.call(true, null);
              } else {
                onSdkInit?.call(false, dataStr);
              }
              break;
            case 'token':
              onToken?.call(data as String? ?? '');
              break;
            case 'complete':
              final profileMap = event['profile'] as Map?;
              PerformanceProfile? profile;
              if (profileMap != null) {
                profile = PerformanceProfile(
                  ttftMs: (profileMap['ttftMs'] as num?)?.toDouble() ?? 0,
                  promptTokens:
                      (profileMap['promptTokens'] as num?)?.toInt() ?? 0,
                  prefillSpeed:
                      (profileMap['prefillSpeed'] as num?)?.toDouble() ?? 0,
                  generatedTokens:
                      (profileMap['generatedTokens'] as num?)?.toInt() ?? 0,
                  decodingSpeed:
                      (profileMap['decodingSpeed'] as num?)?.toDouble() ?? 0,
                );
              }
              onComplete?.call(data as String? ?? '', profile);
              break;
            case 'error':
              onError?.call(data as String? ?? 'Unknown error');
              break;
            case 'model_reloading':
              onModelReloading?.call(data as String? ?? 'Reloading model...');
              break;
            case 'model_reloaded':
              final success = (data as String?) == 'success';
              onModelReloaded?.call(success);
              break;
            case 'tts_start':
              final utteranceId = event['utteranceId'] as String? ?? '';
              debugPrint(
                'VlmService: Received tts_start event, utteranceId=$utteranceId',
              );
              onTtsStart?.call(utteranceId);
              break;
            case 'tts_done':
              final utteranceId = event['utteranceId'] as String? ?? '';
              debugPrint(
                'VlmService: Received tts_done event, utteranceId=$utteranceId, onTtsDone=${onTtsDone != null ? "set" : "null"}',
              );
              onTtsDone?.call(utteranceId);
              break;
            case 'tts_error':
              final utteranceId = event['utteranceId'] as String? ?? '';
              final error = event['error'] as String? ?? 'Unknown error';
              debugPrint(
                'VlmService: Received tts_error event, utteranceId=$utteranceId, error=$error',
              );
              onTtsError?.call(utteranceId, error);
              break;
          }
        }
      },
      onError: (error) {
        onError?.call(error.toString());
      },
    );
  }

  /// Check if Nexa SDK is initialized and ready
  Future<bool> isSdkReady() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isSdkReady');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Load VLM model
  /// [modelPath] - Path to the .nexa or .gguf model file (optional, uses default if not provided)
  /// [mmprojPath] - Optional path to multimodal projection file
  /// [pluginId] - "npu" for NPU inference, "cpu_gpu" for CPU/GPU (default: "npu")
  /// [nGpuLayers] - Number of GPU layers for CPU/GPU mode (0 = auto)
  /// [deviceId] - Device ID for CPU/GPU: "HTP0" (Qualcomm NPU) or "GPUOpenCL" (GPU)
  /// 
  /// Note: If loading is already in progress, returns the existing Future
  /// to prevent duplicate loads and crashes.
  Future<VlmResult> loadModel({
    String? modelPath,
    String? mmprojPath,
    String pluginId = 'npu',
    int nGpuLayers = 0,
    String deviceId = 'HTP0',
  }) async {
    // If already loading, return the existing future to prevent duplicate loads
    if (_loadingFuture != null) {
      debugPrint('VlmService: Model loading already in progress, waiting...');
      return _loadingFuture!;
    }

    // Start new load operation
    _loadingFuture = _doLoadModel(
      modelPath: modelPath,
      mmprojPath: mmprojPath,
      pluginId: pluginId,
      nGpuLayers: nGpuLayers,
      deviceId: deviceId,
    );

    try {
      final result = await _loadingFuture!;
      return result;
    } finally {
      _loadingFuture = null; // Clear loading state when done
    }
  }

  /// Internal method to actually load the model
  Future<VlmResult> _doLoadModel({
    String? modelPath,
    String? mmprojPath,
    String pluginId = 'npu',
    int nGpuLayers = 0,
    String deviceId = 'HTP0',
  }) async {
    try {
      debugPrint('VlmService: Starting model load...');
      final result = await _methodChannel.invokeMethod<Map>('loadModel', {
        'modelPath': modelPath,
        'mmprojPath': mmprojPath,
        'pluginId': pluginId,
        'nGpuLayers': nGpuLayers,
        'deviceId': deviceId,
      });

      final vlmResult = VlmResult(
        success: result?['success'] ?? false,
        message: result?['message'] ?? 'Unknown result',
      );
      debugPrint('VlmService: Model load complete - ${vlmResult.success}');
      return vlmResult;
    } on PlatformException catch (e) {
      debugPrint('VlmService: Model load platform error - ${e.message}');
      return VlmResult(success: false, message: 'Platform error: ${e.message}');
    } catch (e) {
      debugPrint('VlmService: Model load error - $e');
      return VlmResult(success: false, message: 'Error: $e');
    }
  }

  /// Check if model is loaded
  Future<bool> isModelLoaded() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isModelLoaded');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Get the default model path
  Future<String> getDefaultModelPath() async {
    try {
      final result = await _methodChannel.invokeMethod<String>(
        'getDefaultModelPath',
      );
      return result ?? '';
    } catch (e) {
      return '';
    }
  }

  /// Get the default test image path
  Future<String> getDefaultImagePath() async {
    try {
      final result = await _methodChannel.invokeMethod<String>(
        'getDefaultImagePath',
      );
      return result ?? '';
    } catch (e) {
      return '';
    }
  }

  /// Get the native library path (for NPU mode)
  Future<String> getNativeLibPath() async {
    try {
      final result = await _methodChannel.invokeMethod<String>(
        'getNativeLibPath',
      );
      return result ?? '';
    } catch (e) {
      return '';
    }
  }

  /// List available models in the models directory
  Future<List<String>> listAvailableModels() async {
    try {
      final result = await _methodChannel.invokeMethod<List>(
        'listAvailableModels',
      );
      return result?.cast<String>() ?? [];
    } catch (e) {
      return [];
    }
  }

  /// Verify model path and directory structure
  Future<Map<String, dynamic>> verifyModelPath(String modelPath) async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('verifyModelPath', {
        'modelPath': modelPath,
      });
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Process an image with a text prompt
  /// Results will be delivered via callbacks (onToken, onComplete, onError)
  /// [enableThinking] - Enable thinking mode for supported models
  /// [preprocessMode] - Image preprocessing: "npu" (448x448 crop), "resize" (downscale), "none"
  /// [maxImageSize] - Max size for resize mode (longest edge)
  Future<VlmResult> processImage({
    required String imagePath,
    required String prompt,
    bool enableThinking = false,
    String preprocessMode = 'none',
    int? maxImageSize,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('processImage', {
        'imagePath': imagePath,
        'prompt': prompt,
        'enableThinking': enableThinking,
        'preprocessMode': preprocessMode,
        if (maxImageSize != null) 'maxImageSize': maxImageSize,
      });

      return VlmResult(
        success: result?['status'] == 'processing',
        message: result?['status'] ?? 'Unknown status',
      );
    } on PlatformException catch (e) {
      return VlmResult(success: false, message: 'Platform error: ${e.message}');
    } catch (e) {
      return VlmResult(success: false, message: 'Error: $e');
    }
  }

  /// Stop ongoing stream generation
  Future<void> stopStream() async {
    try {
      await _methodChannel.invokeMethod('stopStream');
    } catch (e) {
      // Ignore stop errors
    }
  }

  /// Reset the model context
  Future<void> resetContext() async {
    try {
      await _methodChannel.invokeMethod('resetContext');
    } catch (e) {
      // Ignore reset errors
    }
  }

  /// Release VLM resources
  Future<void> release() async {
    try {
      _streamSubscription?.cancel();
      await _methodChannel.invokeMethod('release');
    } catch (e) {
      // Ignore release errors
    }
  }

  // ==================== Translation Methods ====================

  /// Initialize translator with source and target languages
  /// Default: English -> Spanish
  /// [requireWifi] - Only download models over WiFi (default: true)
  Future<VlmResult> initTranslator({
    String sourceLang = 'en',
    String targetLang = 'es',
    bool requireWifi = true,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('initTranslator', {
        'sourceLang': sourceLang,
        'targetLang': targetLang,
        'requireWifi': requireWifi,
      });

      return VlmResult(
        success: result?['success'] ?? false,
        message: result?['message'] ?? 'Unknown result',
      );
    } on PlatformException catch (e) {
      return VlmResult(success: false, message: 'Platform error: ${e.message}');
    } catch (e) {
      return VlmResult(success: false, message: 'Error: $e');
    }
  }

  /// Translate text using the initialized translator
  Future<TranslationResult> translate(String text) async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('translate', {
        'text': text,
      });

      if (result?['success'] == true) {
        return TranslationResult(
          success: true,
          translatedText: result?['translatedText'] ?? '',
        );
      } else {
        return TranslationResult(
          success: false,
          error: result?['error'] ?? 'Translation failed',
        );
      }
    } on PlatformException catch (e) {
      return TranslationResult(
        success: false,
        error: 'Platform error: ${e.message}',
      );
    } catch (e) {
      return TranslationResult(success: false, error: 'Error: $e');
    }
  }

  /// Check if translator is ready
  Future<bool> isTranslatorReady() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'isTranslatorReady',
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Get list of downloaded translation models
  Future<List<String>> getDownloadedTranslationModels() async {
    try {
      final result = await _methodChannel.invokeMethod<List>(
        'getDownloadedTranslationModels',
      );
      return result?.cast<String>() ?? [];
    } catch (e) {
      return [];
    }
  }

  /// Download a specific language model
  Future<VlmResult> downloadTranslationModel(
    String languageCode, {
    bool requireWifi = true,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<Map>(
        'downloadTranslationModel',
        {'languageCode': languageCode, 'requireWifi': requireWifi},
      );

      return VlmResult(
        success: result?['success'] ?? false,
        message: result?['message'] ?? 'Unknown result',
      );
    } on PlatformException catch (e) {
      return VlmResult(success: false, message: 'Platform error: ${e.message}');
    } catch (e) {
      return VlmResult(success: false, message: 'Error: $e');
    }
  }

  /// Delete a specific language model
  Future<VlmResult> deleteTranslationModel(String languageCode) async {
    try {
      final result = await _methodChannel.invokeMethod<Map>(
        'deleteTranslationModel',
        {'languageCode': languageCode},
      );

      return VlmResult(
        success: result?['success'] ?? false,
        message: result?['message'] ?? 'Unknown result',
      );
    } on PlatformException catch (e) {
      return VlmResult(success: false, message: 'Platform error: ${e.message}');
    } catch (e) {
      return VlmResult(success: false, message: 'Error: $e');
    }
  }

  /// Get list of supported languages with their codes
  Future<Map<String, String>> getSupportedLanguages() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>(
        'getSupportedLanguages',
      );
      return Map<String, String>.from(result ?? {});
    } catch (e) {
      return {};
    }
  }

  /// Release translator resources
  Future<void> releaseTranslator() async {
    try {
      await _methodChannel.invokeMethod('releaseTranslator');
    } catch (e) {
      // Ignore release errors
    }
  }

  /// Dispose the service
  void dispose() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    onToken = null;
    onComplete = null;
    onError = null;
    onSdkInit = null;
    onModelReloading = null;
    onModelReloaded = null;
    onTtsStart = null;
    onTtsDone = null;
    onTtsError = null;
  }
}

/// Translation result class
class TranslationResult {
  final bool success;
  final String? translatedText;
  final String? error;

  TranslationResult({required this.success, this.translatedText, this.error});

  @override
  String toString() =>
      'TranslationResult(success: $success, text: ${translatedText?.substring(0, translatedText!.length.clamp(0, 50))}...)';
}

/// Result class for VLM operations
class VlmResult {
  final bool success;
  final String message;
  final String? data;

  VlmResult({required this.success, required this.message, this.data});

  @override
  String toString() => 'VlmResult(success: $success, message: $message)';
}

/// Performance profile from VLM inference
class PerformanceProfile {
  final double ttftMs; // Time to first token (ms)
  final int promptTokens; // Number of prompt tokens
  final double prefillSpeed; // Prefill speed (tok/s)
  final int generatedTokens; // Number of generated tokens
  final double decodingSpeed; // Decoding speed (tok/s)

  PerformanceProfile({
    required this.ttftMs,
    required this.promptTokens,
    required this.prefillSpeed,
    required this.generatedTokens,
    required this.decodingSpeed,
  });

  @override
  String toString() =>
      'PerformanceProfile('
      'TTFT: ${ttftMs.toStringAsFixed(1)}ms, '
      'Prefill: ${prefillSpeed.toStringAsFixed(1)} tok/s, '
      'Decode: ${decodingSpeed.toStringAsFixed(1)} tok/s, '
      'Tokens: $generatedTokens)';
}
