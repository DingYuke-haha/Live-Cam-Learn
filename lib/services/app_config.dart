import 'package:flutter/foundation.dart';
import '../models/vlm_model.dart';
import 'model_manager.dart';

/// Capture mode enum
enum CaptureMode {
  scene, // Describe the whole scene
  object, // Identify a single object
}

/// App configuration singleton
/// Debug settings are only visible/editable in debug mode
class AppConfig {
  static AppConfig? _instance;

  AppConfig._();

  static AppConfig get instance {
    _instance ??= AppConfig._();
    return _instance!;
  }

  /// Whether the app is in debug mode
  static bool get isDebugMode => kDebugMode;

  // ==================== Mode Settings ====================

  /// Current capture mode
  CaptureMode _captureMode = CaptureMode.scene;

  CaptureMode get captureMode => _captureMode;

  set captureMode(CaptureMode value) {
    _captureMode = value;
  }

  // ==================== VLM Settings ====================

  /// Default prompt for Scene Mode - describes the whole scene
  static const String defaultScenePrompt =
      '''You are a language learning assistant for children.

The input is an image from a camera.
Identify the scene and choose ONE clear, simple relationship or action to describe.

Output a single English sentence.

Rules:
- Level: early elementary / pre-A1+
- Use present tense only
- Sentence length: 6-9 words
- Describe ONLY ONE of the following per sentence:
  • one object + location
  • one subject + one action
  • one object + one basic color
  • one object + one spatial relation (left, right, on, under, near)
- Ignore quantity (do NOT mention numbers or plurality)
- Avoid comparisons or multiple objects descriptions
- Use only very common vocabulary a child would hear in daily life
- Avoid abstract ideas, emotions, or explanations
- Do NOT combine multiple details in one sentence

Allowed sentence patterns include:
- There is a + object + location
- A + subject + verb
- A + object + is + location
- A + object + is + spatial relation + object

Output ONLY the English sentence, nothing else.''';

  /// Default prompt for Object Mode - identifies a single object
  static const String defaultObjectPrompt =
      '''You are a language learning assistant for children.

The input is an image from a camera.
Identify ONE representative visible object, even if multiple similar objects are present.

Output the English word for this object.

Rules:
- Level: early elementary / pre-A1+
- Always use singular form
- Ignore quantity and plurality
- Choose the most common everyday noun
- Avoid category or abstract words
- Do NOT output sentences or explanations
- Do NOT include articles (a, an, the)
- Do NOT include any prefix like "Output:" or "English:"

Output ONLY the single English noun, nothing else.''';

  /// Current Scene Mode VLM prompt (can be modified in debug mode)
  String _scenePrompt = defaultScenePrompt;

  /// Current Object Mode VLM prompt (can be modified in debug mode)
  String _objectPrompt = defaultObjectPrompt;

  String get scenePrompt => _scenePrompt;
  String get objectPrompt => _objectPrompt;

  /// Get the current VLM prompt based on mode
  String get vlmPrompt =>
      _captureMode == CaptureMode.scene ? _scenePrompt : _objectPrompt;

  set scenePrompt(String value) {
    if (isDebugMode) {
      _scenePrompt = value.isEmpty ? defaultScenePrompt : value;
    }
  }

  set objectPrompt(String value) {
    if (isDebugMode) {
      _objectPrompt = value.isEmpty ? defaultObjectPrompt : value;
    }
  }

  /// Reset prompts to defaults
  void resetScenePrompt() {
    _scenePrompt = defaultScenePrompt;
  }

  void resetObjectPrompt() {
    _objectPrompt = defaultObjectPrompt;
  }

  void resetAllPrompts() {
    _scenePrompt = defaultScenePrompt;
    _objectPrompt = defaultObjectPrompt;
  }

  // ==================== Debug Options ====================

  /// Show performance metrics in the UI
  bool _showPerformanceMetrics = false;

  bool get showPerformanceMetrics => isDebugMode && _showPerformanceMetrics;

  set showPerformanceMetrics(bool value) {
    if (isDebugMode) {
      _showPerformanceMetrics = value;
    }
  }

  /// Enable verbose logging
  bool _verboseLogging = false;

  bool get verboseLogging => isDebugMode && _verboseLogging;

  set verboseLogging(bool value) {
    if (isDebugMode) {
      _verboseLogging = value;
    }
  }

  // ==================== Model Settings ====================

  /// Currently selected model (cached)
  VlmModel? _selectedModel;

  /// Get the currently selected model
  Future<VlmModel> getSelectedModel() async {
    if (_selectedModel != null) return _selectedModel!;
    _selectedModel = await ModelManager.instance.getSelectedModel();
    return _selectedModel!;
  }

  /// Set the selected model
  Future<void> setSelectedModel(VlmModel model) async {
    _selectedModel = model;
    await ModelManager.instance.setSelectedModelId(model.id);
  }

  /// Clear the cached model (force reload from preferences)
  void clearCachedModel() {
    _selectedModel = null;
  }
}
