import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import '../services/vlm_service.dart';
import '../services/storage_service.dart';
import '../services/segmentation_service.dart';
import '../services/tts_service.dart';
import '../services/app_config.dart';
import '../services/model_manager.dart';
import '../models/learn_card.dart';
import '../models/vlm_model.dart';
import '../widgets/bottom_bar.dart';
import '../widgets/result_card.dart';
import '../widgets/mode_toggle.dart';
import 'gallery_page.dart';
import 'debug_settings_page.dart';
import 'model_settings_page.dart';

/// App states for the home page
enum AppState {
  loading, // Loading model
  cameraReady, // Camera ready, waiting for capture
  segmenting, // Segmenting object (Object mode only)
  processing, // VLM processing image
  translating, // Translating VLM response
  showingCard, // Showing result card (preview, not saved)
}

/// Main home page with camera preview and capture functionality
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  // Services
  final VlmService _vlmService = VlmService.instance;
  final StorageService _storageService = StorageService.instance;
  final SegmentationService _segmentationService = SegmentationService.instance;
  final TtsService _ttsService = TtsService.instance;

  // Camera
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  // App state
  AppState _appState = AppState.loading;
  String _loadingMessage = 'Initializing...';

  // Capture mode
  CaptureMode _captureMode = CaptureMode.scene;

  // Model state
  bool _isModelLoaded = false;
  bool _isSdkReady = false;

  // Model download state (for first-time setup)
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';

  // Language
  String _targetLanguage = 'fr';
  bool _isTranslatorReady = false;

  // Current capture data
  File? _capturedImage;
  String _streamingResponse = '';
  String _translatedResponse = '';

  // TTS state
  bool _isSpeaking = false;

  // Supported languages map
  static const Map<String, String> _languageCodes = {
    'es': 'ES',
    'fr': 'FR',
    'de': 'DE',
    'ja': 'JA',
    'ko': 'KO',
    'hi': 'HI',
    'zh': 'ZH',
    'it': 'IT',
    'pt': 'PT',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initialize() async {
    setState(() {
      _appState = AppState.loading;
      _loadingMessage = 'Initializing...';
    });

    // Initialize VLM service listener
    _vlmService.initStreamListener();
    _setupVlmCallbacks();

    // Load saved cards
    await _storageService.loadCards();

    // Initialize camera, model, and segmenter in parallel
    await Future.wait([
      _initializeCamera(),
      _initializeModel(),
      _initializeSegmenter(),
    ]);

    // Initialize translator (non-blocking - app works without translation)
    await _initializeTranslator();

    // Initialize TTS
    await _initializeTts();

    // Ready! Proceed even if model isn't loaded (user can download from settings)
    if (_isCameraInitialized) {
      setState(() {
        _appState = AppState.cameraReady;
        // If model not loaded, the UI will show a friendly setup card
      });
    }
  }

  Future<void> _initializeTts() async {
    await _ttsService.initialize();
    _setupTtsCallbacks();
  }

  Future<void> _speakTranslatedText() async {
    if (_translatedResponse.isEmpty) return;

    // If already speaking, stop
    if (_isSpeaking) {
      await _ttsService.stop();
      setState(() {
        _isSpeaking = false;
      });
      return;
    }

    // Re-establish callbacks before speaking (in case another page overwrote them)
    _setupTtsCallbacks();

    setState(() {
      _isSpeaking = true;
    });

    final success = await _ttsService.speak(
      _translatedResponse,
      languageCode: _targetLanguage,
    );

    if (!success && mounted) {
      setState(() {
        _isSpeaking = false;
      });
    }
  }

  void _setupTtsCallbacks() {
    _ttsService.onDone = () {
      debugPrint('HomePage: TTS onDone callback fired');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    };
    _ttsService.onError = (error) {
      debugPrint('HomePage: TTS onError callback fired: $error');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    };
  }

  Future<void> _initializeSegmenter() async {
    // Warm up segmenter in background - triggers ML Kit model download
    // This ensures the model is ready when the user switches to Object mode
    _segmentationService.warmup().then((result) {
      if (result.success) {
        debugPrint('Segmenter warmed up successfully');
      } else {
        debugPrint('Segmenter warmup failed: ${result.message}');
      }
    });
  }

  void _setupVlmCallbacks() {
    _vlmService.onSdkInit = (success, reason) {
      setState(() {
        _isSdkReady = success;
        if (!success) {
          _loadingMessage = 'SDK init failed: $reason';
        }
      });
    };

    _vlmService.onToken = (token) {
      // In object mode, don't show streaming (just a single word anyway)
      // In scene mode, show streaming for better UX with longer sentences
      if (_captureMode == CaptureMode.scene) {
        setState(() {
          _streamingResponse += token;
        });
      }
    };

    _vlmService.onComplete = (fullResponse, profile) async {
      // Clean up VLM response (remove common prefixes)
      final cleanedResponse = _cleanVlmResponse(fullResponse);

      // VLM complete, now translate
      setState(() {
        _appState = AppState.translating;
        _streamingResponse = cleanedResponse;
      });
      await _translateResponse(cleanedResponse);
    };

    _vlmService.onError = (error) {
      setState(() {
        _appState = AppState.cameraReady;
        _loadingMessage = 'Error: $error';
      });
      _showError('Processing failed: $error');
    };

    _vlmService.onModelReloading = (message) {
      setState(() {
        _loadingMessage = message;
      });
    };

    _vlmService.onModelReloaded = (success) async {
      final isLoaded = await _vlmService.isModelLoaded();
      setState(() {
        _isModelLoaded = isLoaded;
      });
    };
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        _showError('No cameras available');
        return;
      }

      // Find back camera
      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      _showError('Camera initialization failed: $e');
    }
  }

  Future<void> _initializeModel() async {
    debugPrint('VLM: Starting model initialization...');
    setState(() {
      _loadingMessage = 'Initializing...';
    });

    // Check if SDK is ready
    _isSdkReady = await _vlmService.isSdkReady();
    debugPrint('VLM: SDK ready = $_isSdkReady');

    // Check if model is already loaded
    _isModelLoaded = await _vlmService.isModelLoaded();
    debugPrint('VLM: Model already loaded = $_isModelLoaded');

    if (_isModelLoaded) {
      setState(() {
        _loadingMessage = 'Model ready';
      });
      return;
    }

    // Get the selected model
    final selectedModel = await AppConfig.instance.getSelectedModel();
    debugPrint(
      'VLM: Selected model = ${selectedModel.id} (${selectedModel.displayName})',
    );

    // Check if model is downloaded
    final modelManager = ModelManager.instance;
    final isDownloaded = await modelManager.isModelDownloaded(selectedModel);
    debugPrint('VLM: Model downloaded = $isDownloaded');

    if (!isDownloaded) {
      debugPrint('VLM: Model not downloaded, skipping load');
      setState(() {
        _isModelLoaded = false;
        _loadingMessage =
            'Model not downloaded. Please download from Settings.';
      });
      return;
    }

    // Get model paths
    final modelPath = await modelManager.getMainModelPath(selectedModel);
    final mmprojPath = await modelManager.getMmprojPath(selectedModel);
    debugPrint('VLM: Model path = $modelPath');
    debugPrint('VLM: MMProj path = $mmprojPath');
    debugPrint(
      'VLM: Plugin ID = ${selectedModel.pluginId}, Device ID = ${selectedModel.deviceId}',
    );

    setState(() {
      _loadingMessage = 'Loading ${selectedModel.displayName}...';
    });

    // Load the model with correct configuration
    debugPrint('VLM: Loading model...');
    final result = await _vlmService.loadModel(
      modelPath: modelPath,
      mmprojPath: mmprojPath,
      pluginId: selectedModel.pluginId,
      deviceId: selectedModel.deviceId,
    );
    debugPrint(
      'VLM: Load result = ${result.success}, message = ${result.message}',
    );

    setState(() {
      _isModelLoaded = result.success;
      _loadingMessage = result.success
          ? 'Model loaded'
          : 'Model load failed: ${result.message}';
    });
  }

  Future<void> _initializeTranslator() async {
    setState(() {
      _loadingMessage = 'Initializing translator...';
    });

    try {
      // Add timeout to prevent hanging forever
      final result = await _vlmService
          .initTranslator(
            sourceLang: 'en',
            targetLang: _targetLanguage,
            requireWifi: false,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              debugPrint('Translator initialization timed out');
              return VlmResult(
                success: false,
                message: 'Translator initialization timed out',
              );
            },
          );

      setState(() {
        _isTranslatorReady = result.success;
        if (!result.success) {
          debugPrint('Translator init failed: ${result.message}');
        }
      });
    } catch (e) {
      debugPrint('Translator initialization error: $e');
      setState(() {
        _isTranslatorReady = false;
      });
    }
  }

  Future<void> _translateResponse(String text) async {
    if (!_isTranslatorReady || text.isEmpty) {
      setState(() {
        _translatedResponse = text; // Fallback to English
        _appState = AppState.showingCard;
      });
      return;
    }

    final result = await _vlmService.translate(text);

    setState(() {
      if (result.success && result.translatedText != null) {
        _translatedResponse = result.translatedText!;
      } else {
        _translatedResponse = text; // Fallback to English
      }
      _appState = AppState.showingCard;
    });
  }

  Future<void> _onCaptureTap() async {
    if (_appState == AppState.showingCard) {
      // Save to gallery
      await _saveToGallery();
      return;
    }

    if (_appState != AppState.cameraReady) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized)
      return;

    try {
      setState(() {
        _streamingResponse = '';
        _translatedResponse = '';
      });

      // Capture photo
      final XFile photo = await _cameraController!.takePicture();

      // Save to app directory
      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final savedPath = '${appDir.path}/capture_$timestamp.jpg';
      await File(photo.path).copy(savedPath);

      // Delete original camera temp file (CAP*.jpg)
      try {
        await File(photo.path).delete();
      } catch (e) {
        // Ignore if delete fails
      }

      setState(() {
        _capturedImage = File(savedPath);
      });

      String imagePathForVlm = savedPath;

      // Object mode: segment first
      if (_captureMode == CaptureMode.object) {
        setState(() {
          _appState = AppState.segmenting;
        });

        final segmentedPath = '${appDir.path}/segmented_$timestamp.png';
        final segResult = await _segmentationService.segmentImage(
          imagePath: savedPath,
          outputPath: segmentedPath,
        );

        if (!segResult.success) {
          setState(() {
            _appState = AppState.cameraReady;
          });
          _showError('Segmentation failed: ${segResult.message}');
          return;
        }

        // Use segmented image for VLM
        imagePathForVlm = segResult.outputPath ?? savedPath;

        // Update displayed image to segmented version
        setState(() {
          _capturedImage = File(imagePathForVlm);
        });
      }

      setState(() {
        _appState = AppState.processing;
      });

      // Get current model for preprocessing config
      final selectedModel = await AppConfig.instance.getSelectedModel();

      // Reset VLM context before new inference
      await _vlmService.resetContext();

      // Process with VLM - preprocessing is handled natively based on model
      await _vlmService.processImage(
        imagePath: imagePathForVlm,
        prompt: AppConfig.instance.vlmPrompt,
        preprocessMode: selectedModel.preprocessMode,
        maxImageSize: selectedModel.maxImageSize,
      );
    } catch (e) {
      setState(() {
        _appState = AppState.cameraReady;
      });
      _showError('Capture failed: $e');
    }
  }

  Future<void> _saveToGallery() async {
    if (_capturedImage == null) return;

    // Stop TTS if playing
    if (_isSpeaking) {
      await _ttsService.stop();
    }

    // Store temp file path for cleanup
    final tempImagePath = _capturedImage!.path;

    try {
      // Copy image to gallery folder
      final savedImagePath = await _storageService.saveImage(
        _capturedImage!.path,
      );

      // Create and save card
      final card = LearnCard.create(
        imagePath: savedImagePath,
        englishText: _streamingResponse,
        translatedText: _translatedResponse,
        targetLanguage: _targetLanguage,
      );

      await _storageService.addCard(card);

      // Clean up temporary files
      await _cleanupTempFiles(tempImagePath);

      // Reset state
      setState(() {
        _appState = AppState.cameraReady;
        _capturedImage = null;
        _streamingResponse = '';
        _translatedResponse = '';
        _isSpeaking = false;
      });

      // Show confirmation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved to gallery!'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      _showError('Save failed: $e');
    }
  }

  /// Clean up temporary capture and segmented files
  Future<void> _cleanupTempFiles(String imagePath) async {
    try {
      // Delete the captured/segmented image
      final imageFile = File(imagePath);
      if (await imageFile.exists()) {
        await imageFile.delete();
        debugPrint('Deleted temp file: $imagePath');
      }

      // If this was a segmented image, also delete the original capture
      // Segmented files are .png, original captures are .jpg with same timestamp
      if (imagePath.endsWith('.png') && imagePath.contains('segmented_')) {
        final originalPath = imagePath
            .replaceAll('segmented_', 'capture_')
            .replaceAll('.png', '.jpg');
        final originalFile = File(originalPath);
        if (await originalFile.exists()) {
          await originalFile.delete();
          debugPrint('Deleted original capture: $originalPath');
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up temp files: $e');
      // Don't throw - cleanup failure shouldn't break the save flow
    }
  }

  void _onCancelTap() {
    // Stop TTS if playing
    if (_isSpeaking) {
      _ttsService.stop();
    }

    // Clean up temp files
    if (_capturedImage != null) {
      _cleanupTempFiles(_capturedImage!.path);
    }

    setState(() {
      _appState = AppState.cameraReady;
      _capturedImage = null;
      _streamingResponse = '';
      _translatedResponse = '';
      _isSpeaking = false;
    });
  }

  void _onGalleryTap() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const GalleryPage()),
    ).then((_) {
      // Refresh card count when returning
      setState(() {});
    });
  }

  Future<void> _onLanguageSelected(String lang) async {
    if (lang != _targetLanguage) {
      setState(() {
        _targetLanguage = lang;
        _isTranslatorReady = false;
      });
      // Re-initialize translator with new language
      await _initializeTranslator();
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  void _onModeChanged(CaptureMode mode) {
    if (_appState != AppState.cameraReady) return;

    setState(() {
      _captureMode = mode;
      AppConfig.instance.captureMode = mode;
    });
  }

  /// Clean up VLM response by removing common prefixes
  String _cleanVlmResponse(String response) {
    String cleaned = response.trim();

    // Common prefixes to remove (case-insensitive)
    final prefixesToRemove = [
      'Output:',
      'output:',
      'English:',
      'english:',
      'Answer:',
      'answer:',
      'Result:',
      'result:',
    ];

    for (final prefix in prefixesToRemove) {
      if (cleaned.startsWith(prefix)) {
        debugPrint('Text cleanup - before: "$cleaned"');
        cleaned = cleaned.substring(prefix.length).trim();
        debugPrint('Text cleanup - after: "$cleaned"');
        break; // Only remove one prefix
      }
    }

    return cleaned;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isProcessingState =
        _appState == AppState.segmenting ||
        _appState == AppState.processing ||
        _appState == AppState.translating;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview or captured image
          _buildCameraPreview(),

          // Loading overlay
          if (_appState == AppState.loading) _buildLoadingOverlay(),

          // Result card overlay
          if (isProcessingState || _appState == AppState.showingCard)
            _buildResultOverlay(),

          // Setup card (when model not loaded)
          if (_appState == AppState.cameraReady && !_isModelLoaded)
            _buildSetupCard(),

          // Mode toggle (when camera ready and model loaded)
          if (_appState == AppState.cameraReady && _isModelLoaded)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 0,
              right: 0,
              child: Center(
                child: ModeToggle(
                  currentMode: _captureMode,
                  onModeChanged: _onModeChanged,
                  enabled: _appState == AppState.cameraReady,
                ),
              ),
            ),

          // Cancel button (when processing or showing card)
          if (_appState == AppState.showingCard || isProcessingState)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _onCancelTap,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD54F),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.black87,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),

          // Bottom bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: BottomBar(
              onGalleryTap: _onGalleryTap,
              onCaptureTap: _onCaptureTap,
              onLanguageSelected: _onLanguageSelected,
              sourceLanguage: 'EN',
              targetLanguageCode: _targetLanguage,
              targetLanguageDisplay:
                  _languageCodes[_targetLanguage] ??
                  _targetLanguage.toUpperCase(),
              isCapturing: isProcessingState,
              showSaveMode: _appState == AppState.showingCard,
            ),
          ),

          // Debug settings button (only in debug mode and when model loaded)
          if (kDebugMode && _appState == AppState.cameraReady && _isModelLoaded)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: GestureDetector(
                onTap: _onDebugSettingsTap,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.red[400],
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.bug_report,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onDebugSettingsTap() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DebugSettingsPage()),
    );
  }

  Widget _buildCameraPreview() {
    // Show captured image when processing/showing card
    if (_capturedImage != null &&
        (_appState == AppState.processing ||
            _appState == AppState.translating ||
            _appState == AppState.showingCard ||
            _appState == AppState.segmenting)) {
      // For object mode (segmented images), use contain to show the whole object
      // For scene mode, use cover to fill the screen
      final isSegmentedImage =
          _captureMode == CaptureMode.object &&
          _appState != AppState.segmenting; // After segmentation is done

      return Container(
        color: Colors.white,
        child: SizedBox.expand(
          child: Image.file(
            _capturedImage!,
            fit: isSegmentedImage ? BoxFit.contain : BoxFit.cover,
          ),
        ),
      );
    }

    // Show camera preview
    if (!_isCameraInitialized || _cameraController == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _cameraController!.value.previewSize?.height ?? 1,
          height: _cameraController!.value.previewSize?.width ?? 1,
          child: CameraPreview(_cameraController!),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFFFFD54F)),
            const SizedBox(height: 24),
            Text(
              _loadingMessage,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadDefaultModel() async {
    if (_isDownloading) return;

    final model = AvailableModels.defaultModel; // OmniNeural 4B

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = 'Starting download...';
    });

    final modelManager = ModelManager.instance;

    await modelManager.downloadModel(
      model,
      onProgress: (fileName, received, total, progress) {
        setState(() {
          _downloadProgress = progress;
          _downloadStatus = fileName;
        });
      },
      onComplete: () async {
        setState(() {
          _downloadStatus = 'Download complete! Loading model...';
        });

        // Set as selected model and load it
        await modelManager.setSelectedModelId(model.id);
        AppConfig.instance.clearCachedModel();

        // Initialize the model
        await _initializeModel();

        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
          _downloadStatus = '';
        });
      },
      onError: (error) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
          _downloadStatus = '';
        });
        _showError('Download failed: $error');
      },
    );
  }

  Widget _buildSetupCard() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD54F).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: _isDownloading
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: _downloadProgress > 0
                                  ? _downloadProgress
                                  : null,
                              color: const Color(0xFFFF8C00),
                              strokeWidth: 4,
                            ),
                            Text(
                              '${(_downloadProgress * 100).toInt()}%',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF8C00),
                              ),
                            ),
                          ],
                        )
                      : const Icon(
                          Icons.download_rounded,
                          size: 40,
                          color: Color(0xFFFF8C00),
                        ),
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  _isDownloading
                      ? 'Downloading...'
                      : 'Welcome to LiveCam Learn!',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                // Description or progress
                if (_isDownloading) ...[
                  Text(
                    _downloadStatus,
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _downloadProgress > 0 ? _downloadProgress : null,
                      backgroundColor: Colors.grey[200],
                      valueColor: const AlwaysStoppedAnimation(
                        Color(0xFFFF8C00),
                      ),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'OmniNeural 4B (NPU) - ~4GB',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ] else ...[
                  const Text(
                    'Download the AI model to get started.\nOmniNeural 4B is optimized for Snapdragon NPU.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                // Download button or cancel
                if (_isDownloading)
                  TextButton(
                    onPressed: () {
                      ModelManager.instance.cancelDownload();
                      setState(() {
                        _isDownloading = false;
                        _downloadProgress = 0.0;
                        _downloadStatus = '';
                      });
                    },
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.red),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: _downloadDefaultModel,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD54F), Color(0xFFFF8C00)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.rocket_launch_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Download OmniNeural 4B',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Link to see other models
                if (!_isDownloading) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ModelSettingsPage(),
                        ),
                      ).then((_) => _initializeModel());
                    },
                    child: const Text(
                      'See other models',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFFFF8C00),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultOverlay() {
    return Container(
      color: Colors.transparent,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 200), // Space for bottom bar
          child: StreamingResultCard(
            streamingText: _streamingResponse,
            translatedText: _appState == AppState.showingCard
                ? _translatedResponse
                : null,
            targetLanguage: _targetLanguage,
            isSegmenting: _appState == AppState.segmenting,
            isProcessing: _appState == AppState.processing,
            isTranslating: _appState == AppState.translating,
            isObjectMode: _captureMode == CaptureMode.object,
            isSpeaking: _isSpeaking,
            onSpeakerTap: _appState == AppState.showingCard
                ? _speakTranslatedText
                : null,
          ),
        ),
      ),
    );
  }
}
