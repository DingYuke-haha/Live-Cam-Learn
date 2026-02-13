import 'package:flutter/services.dart';

/// Service for ML Kit Subject Segmentation
/// Used in Object Mode to segment the main subject from an image
class SegmentationService {
  static const MethodChannel _channel = MethodChannel(
    'com.nexa.live_cam_learn/vlm',
  );

  // Singleton instance
  static SegmentationService? _instance;

  SegmentationService._();

  static SegmentationService get instance {
    _instance ??= SegmentationService._();
    return _instance!;
  }

  bool _isInitialized = false;
  bool _isWarmedUp = false;

  /// Initialize the segmentation service
  Future<SegmentationResult> initialize() async {
    try {
      final result = await _channel.invokeMethod('initSegmenter');
      final success = result['success'] as bool? ?? false;
      _isInitialized = success;
      return SegmentationResult(
        success: success,
        message: result['message'] as String? ?? 'Unknown',
      );
    } catch (e) {
      return SegmentationResult(
        success: false,
        message: 'Failed to initialize: $e',
      );
    }
  }

  /// Check if segmenter is ready
  Future<bool> isReady() async {
    try {
      final result = await _channel.invokeMethod('isSegmenterReady');
      return result as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Check if segmenter has been warmed up (model downloaded)
  bool get isWarmedUp => _isWarmedUp;

  /// Warm up the segmenter - triggers ML Kit model download
  /// Call this at app startup to ensure the model is ready when needed
  Future<SegmentationResult> warmup() async {
    if (_isWarmedUp) {
      return SegmentationResult(success: true, message: 'Already warmed up');
    }

    try {
      final result = await _channel.invokeMethod('warmupSegmenter');
      final success = result['success'] as bool? ?? false;
      _isWarmedUp = success;
      _isInitialized = success;
      return SegmentationResult(
        success: success,
        message: result['message'] as String? ?? 'Unknown',
      );
    } catch (e) {
      return SegmentationResult(success: false, message: 'Warmup failed: $e');
    }
  }

  /// Segment the main subject from an image
  /// Returns the path to the segmented image (PNG with transparency)
  Future<SegmentationResult> segmentImage({
    required String imagePath,
    required String outputPath,
  }) async {
    try {
      // Auto-initialize if needed
      if (!_isInitialized) {
        final initResult = await initialize();
        if (!initResult.success) {
          return initResult;
        }
      }

      final result = await _channel.invokeMethod('segmentImage', {
        'imagePath': imagePath,
        'outputPath': outputPath,
      });

      final success = result['success'] as bool? ?? false;
      return SegmentationResult(
        success: success,
        outputPath: result['outputPath'] as String?,
        message: result['error'] as String?,
      );
    } catch (e) {
      return SegmentationResult(
        success: false,
        message: 'Segmentation failed: $e',
      );
    }
  }

  /// Release segmentation resources
  Future<void> release() async {
    try {
      await _channel.invokeMethod('releaseSegmenter');
      _isInitialized = false;
    } catch (e) {
      // Ignore release errors
    }
  }
}

/// Result from segmentation operations
class SegmentationResult {
  final bool success;
  final String? outputPath;
  final String? message;

  SegmentationResult({required this.success, this.outputPath, this.message});
}
