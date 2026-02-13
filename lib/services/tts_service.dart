import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'vlm_service.dart';

/// Service for Text-to-Speech functionality using Android's TTS engine
class TtsService {
  static const MethodChannel _channel = MethodChannel(
    'com.nexa.live_cam_learn/vlm',
  );

  bool _isInitialized = false;
  bool _isSpeaking = false;
  String? _currentUtteranceId;

  // Callbacks
  VoidCallback? onStart;
  VoidCallback? onDone;
  Function(String)? onError;

  /// Singleton instance
  static final TtsService _instance = TtsService._internal();
  static TtsService get instance => _instance;

  TtsService._internal() {
    // Set up VLM service callbacks for TTS events
    _setupEventCallbacks();
  }

  void _setupEventCallbacks() {
    final vlmService = VlmService.instance;

    vlmService.onTtsStart = (utteranceId) {
      debugPrint('TTS Event: onTtsStart - utteranceId=$utteranceId');
      _isSpeaking = true;
      _currentUtteranceId = utteranceId;
      onStart?.call();
    };

    vlmService.onTtsDone = (utteranceId) {
      debugPrint('TTS Event: onTtsDone - utteranceId=$utteranceId');
      _isSpeaking = false;
      _currentUtteranceId = null;
      onDone?.call();
      debugPrint(
        'TTS Event: onDone callback called, onDone is ${onDone != null ? "set" : "null"}',
      );
    };

    vlmService.onTtsError = (utteranceId, error) {
      debugPrint(
        'TTS Event: onTtsError - utteranceId=$utteranceId, error=$error',
      );
      _isSpeaking = false;
      _currentUtteranceId = null;
      onError?.call(error);
    };
  }

  /// Re-establish event callbacks (call this after page navigation)
  void ensureCallbacksSetup() {
    _setupEventCallbacks();
  }

  /// Check if TTS is initialized
  bool get isInitialized => _isInitialized;

  /// Check if TTS is currently speaking
  bool get isSpeaking => _isSpeaking;

  /// Get the current utterance ID (if speaking)
  String? get currentUtteranceId => _currentUtteranceId;

  /// Initialize the TTS engine
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      final result = await _channel.invokeMethod<Map>('initTts');
      _isInitialized = result?['success'] == true;
      debugPrint(
        'TTS initialization: ${_isInitialized ? 'SUCCESS' : 'FAILED'}',
      );
      return _isInitialized;
    } catch (e) {
      debugPrint('TTS initialization error: $e');
      return false;
    }
  }

  /// Check if TTS is ready
  Future<bool> isReady() async {
    try {
      final result = await _channel.invokeMethod<bool>('isTtsReady');
      return result ?? false;
    } catch (e) {
      debugPrint('TTS isReady error: $e');
      return false;
    }
  }

  /// Speak the given text
  /// [text] - The text to speak
  /// [languageCode] - Optional language code (e.g., "es", "fr", "de", "ja", etc.)
  Future<bool> speak(String text, {String? languageCode}) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        debugPrint('TTS not initialized');
        onError?.call('TTS not initialized');
        return false;
      }
    }

    try {
      final result = await _channel.invokeMethod<Map>('ttsSpeak', {
        'text': text,
        'languageCode': languageCode,
      });

      final success = result?['success'] == true;
      if (success) {
        _isSpeaking = true;
        _currentUtteranceId = result?['utteranceId'];
        onStart?.call();
      }
      return success;
    } catch (e) {
      debugPrint('TTS speak error: $e');
      onError?.call(e.toString());
      return false;
    }
  }

  /// Stop any ongoing speech
  Future<void> stop() async {
    try {
      await _channel.invokeMethod('ttsStop');
      _isSpeaking = false;
      _currentUtteranceId = null;
    } catch (e) {
      debugPrint('TTS stop error: $e');
    }
  }

  /// Check if TTS is currently speaking (from native)
  Future<bool> checkIsSpeaking() async {
    try {
      final result = await _channel.invokeMethod<bool>('ttsIsSpeaking');
      _isSpeaking = result ?? false;
      return _isSpeaking;
    } catch (e) {
      debugPrint('TTS isSpeaking error: $e');
      return false;
    }
  }

  /// Set the language for TTS
  Future<bool> setLanguage(String languageCode) async {
    try {
      final result = await _channel.invokeMethod<Map>('ttsSetLanguage', {
        'languageCode': languageCode,
      });
      return result?['success'] == true;
    } catch (e) {
      debugPrint('TTS setLanguage error: $e');
      return false;
    }
  }

  /// Check if a language is available
  Future<bool> isLanguageAvailable(String languageCode) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'ttsIsLanguageAvailable',
        {'languageCode': languageCode},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('TTS isLanguageAvailable error: $e');
      return false;
    }
  }

  /// Get list of available languages
  Future<List<String>> getAvailableLanguages() async {
    try {
      final result = await _channel.invokeMethod<List>(
        'ttsGetAvailableLanguages',
      );
      return result?.cast<String>() ?? [];
    } catch (e) {
      debugPrint('TTS getAvailableLanguages error: $e');
      return [];
    }
  }

  /// Set speech rate (1.0 is normal, 0.5 is half speed, 2.0 is double speed)
  Future<void> setSpeechRate(double rate) async {
    try {
      await _channel.invokeMethod('ttsSetSpeechRate', {'rate': rate});
    } catch (e) {
      debugPrint('TTS setSpeechRate error: $e');
    }
  }

  /// Set speech pitch (1.0 is normal)
  Future<void> setPitch(double pitch) async {
    try {
      await _channel.invokeMethod('ttsSetPitch', {'pitch': pitch});
    } catch (e) {
      debugPrint('TTS setPitch error: $e');
    }
  }

  /// Handle TTS events from the native side
  void handleTtsEvent(Map<dynamic, dynamic> event) {
    final type = event['type'];

    switch (type) {
      case 'tts_start':
        _isSpeaking = true;
        onStart?.call();
        break;
      case 'tts_done':
        _isSpeaking = false;
        _currentUtteranceId = null;
        onDone?.call();
        break;
      case 'tts_error':
        _isSpeaking = false;
        _currentUtteranceId = null;
        final error = event['error'] ?? 'Unknown error';
        onError?.call(error);
        break;
    }
  }

  /// Release TTS resources
  Future<void> release() async {
    try {
      await _channel.invokeMethod('releaseTts');
      _isInitialized = false;
      _isSpeaking = false;
      _currentUtteranceId = null;
    } catch (e) {
      debugPrint('TTS release error: $e');
    }
  }
}
