import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/vlm_service.dart';
import 'camera_page.dart';

/// VLM Test Page - Simple UI for testing VLM functionality
class VlmTestPage extends StatefulWidget {
  const VlmTestPage({super.key});

  @override
  State<VlmTestPage> createState() => _VlmTestPageState();
}

class _VlmTestPageState extends State<VlmTestPage> with WidgetsBindingObserver {
  final VlmService _vlmService = VlmService.instance;
  final TextEditingController _modelPathController = TextEditingController();
  final TextEditingController _mmprojPathController = TextEditingController();
  final TextEditingController _imagePathController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  // Captured/selected image file
  File? _selectedImageFile;

  bool _isSdkReady = false;
  bool _isModelLoaded = false;
  bool _isLoading = false;
  bool _isProcessing = false;
  String _response = '';
  String _statusMessage = '';
  String _selectedPluginId = 'npu';
  String _selectedDeviceId = 'HTP0';
  int _nGpuLayers = 0;
  PerformanceProfile? _lastProfile;

  // Translation state
  bool _enableTranslation = false;
  bool _isTranslatorReady = false;
  bool _isTranslating = false;
  String _translatedResponse = '';
  String _selectedTargetLang = 'es'; // Default: Spanish
  final Map<String, String> _supportedLanguages = {
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'ja': 'Japanese',
    'ko': 'Korean',
    'hi': 'Hindi',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initService();
    _promptController.text = 'Describe this image in short.';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Refresh status when app resumes
      _refreshModelStatus();
    }
  }

  Future<void> _refreshModelStatus() async {
    final isSdkReady = await _vlmService.isSdkReady();
    final isLoaded = await _vlmService.isModelLoaded();
    if (mounted) {
      setState(() {
        _isSdkReady = isSdkReady;
        _isModelLoaded = isLoaded;
      });
    }
  }

  Future<void> _initService() async {
    _vlmService.initStreamListener();

    // Set up callbacks
    _vlmService.onSdkInit = (success, reason) {
      setState(() {
        _isSdkReady = success;
        _statusMessage = success
            ? 'SDK initialized successfully'
            : 'SDK init failed: $reason';
      });
    };

    _vlmService.onToken = (token) {
      setState(() {
        _response += token;
      });
      _scrollToBottom();
    };

    _vlmService.onComplete = (fullResponse, profile) async {
      setState(() {
        _isProcessing = false;
        _lastProfile = profile;
        _statusMessage = profile != null
            ? 'Completed - TTFT: ${profile.ttftMs.toStringAsFixed(1)}ms, '
                  'Speed: ${profile.decodingSpeed.toStringAsFixed(1)} tok/s'
            : 'Generation completed';
      });

      // Auto-translate if enabled
      if (_enableTranslation && _isTranslatorReady && fullResponse.isNotEmpty) {
        _translateResponse(fullResponse);
      }
    };

    _vlmService.onError = (error) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error: $error';
      });
    };

    // Handle model auto-reload (after returning from camera)
    _vlmService.onModelReloading = (message) {
      setState(() {
        _isLoading = true;
        _statusMessage = message;
      });
    };

    _vlmService.onModelReloaded = (success) async {
      // Refresh model status from native
      final isLoaded = await _vlmService.isModelLoaded();
      setState(() {
        _isLoading = false;
        _isModelLoaded = isLoaded;
        _statusMessage = success
            ? 'Model auto-reloaded successfully'
            : 'Model auto-reload failed - please reload manually';
      });
    };

    // Get default model path
    final defaultPath = await _vlmService.getDefaultModelPath();
    setState(() {
      _modelPathController.text = defaultPath;
    });

    // Check SDK and model status
    final isSdkReady = await _vlmService.isSdkReady();
    final isLoaded = await _vlmService.isModelLoaded();
    setState(() {
      _isSdkReady = isSdkReady;
      _isModelLoaded = isLoaded;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadModel() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Loading model...';
    });

    final result = await _vlmService.loadModel(
      modelPath: _modelPathController.text.isNotEmpty
          ? _modelPathController.text
          : null,
      mmprojPath: _mmprojPathController.text.isNotEmpty
          ? _mmprojPathController.text
          : null,
      pluginId: _selectedPluginId,
      nGpuLayers: _nGpuLayers,
      deviceId: _selectedDeviceId,
    );

    setState(() {
      _isLoading = false;
      _isModelLoaded = result.success;
      _statusMessage = result.message;
    });
  }

  Future<void> _processImage() async {
    if (!_isModelLoaded) {
      setState(() {
        _statusMessage = 'Please load model first';
      });
      return;
    }

    final imagePath = _imagePathController.text.trim();
    final prompt = _promptController.text.trim();

    if (imagePath.isEmpty) {
      setState(() {
        _statusMessage = 'Please enter an image path';
      });
      return;
    }

    if (prompt.isEmpty) {
      setState(() {
        _statusMessage = 'Please enter a prompt';
      });
      return;
    }

    // Check if image exists
    if (!File(imagePath).existsSync()) {
      setState(() {
        _statusMessage = 'Image file does not exist: $imagePath';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _response = '';
      _translatedResponse = '';
      _lastProfile = null;
      _statusMessage = 'Processing image...';
    });

    await _vlmService.processImage(imagePath: imagePath, prompt: prompt);
  }

  Future<void> _initTranslator() async {
    setState(() {
      _statusMessage =
          'Initializing translator (en -> $_selectedTargetLang)...';
    });

    final result = await _vlmService.initTranslator(
      sourceLang: 'en',
      targetLang: _selectedTargetLang,
      requireWifi: false, // Allow mobile data for faster testing
    );

    setState(() {
      _isTranslatorReady = result.success;
      _statusMessage = result.success
          ? 'Translator ready (en -> $_selectedTargetLang)'
          : 'Translator init failed: ${result.message}';
    });
  }

  Future<void> _translateResponse(String text) async {
    if (!_isTranslatorReady || text.isEmpty) return;

    setState(() {
      _isTranslating = true;
      _statusMessage = 'Translating...';
    });

    final result = await _vlmService.translate(text);

    setState(() {
      _isTranslating = false;
      if (result.success && result.translatedText != null) {
        _translatedResponse = result.translatedText!;
        _statusMessage = 'Translation completed';
      } else {
        _statusMessage = 'Translation failed: ${result.error}';
      }
    });
  }

  Future<void> _stopStream() async {
    await _vlmService.stopStream();
    setState(() {
      _isProcessing = false;
      _statusMessage = 'Stream stopped';
    });
  }

  Future<void> _resetContext() async {
    await _vlmService.resetContext();
    setState(() {
      _response = '';
      _lastProfile = null;
      _statusMessage = 'Context reset';
    });
  }

  /// Take a photo using in-app camera (avoids process being killed)
  Future<void> _takePhoto() async {
    try {
      // Navigate to in-app camera page
      final String? capturedPath = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => const CameraPage()),
      );

      if (capturedPath != null && capturedPath.isNotEmpty) {
        final File capturedFile = File(capturedPath);
        if (capturedFile.existsSync()) {
          setState(() {
            _selectedImageFile = capturedFile;
            _imagePathController.text = capturedPath;
            _statusMessage = 'Photo captured successfully';
          });
        }
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error taking photo: $e';
      });
    }
  }

  /// Pick an image from gallery
  Future<void> _pickFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );

      if (image != null) {
        // Save to app's data directory for easy access
        final appDir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final savedPath = '${appDir.path}/selected_$timestamp.jpg';

        // Copy file to app directory
        final File savedFile = await File(image.path).copy(savedPath);

        setState(() {
          _selectedImageFile = savedFile;
          _imagePathController.text = savedPath;
          _statusMessage = 'Image selected: ${savedFile.path}';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error selecting image: $e';
      });
    }
  }

  Future<void> _verifyModel() async {
    final modelPath = _modelPathController.text.trim();
    if (modelPath.isEmpty) {
      setState(() {
        _statusMessage = 'Please enter a model path first';
      });
      return;
    }

    setState(() {
      _statusMessage = 'Verifying model...';
    });

    final info = await _vlmService.verifyModelPath(modelPath);

    String message = 'Model Verification:\n';
    message += '- File exists: ${info['modelFileExists']}\n';
    message += '- Dir exists: ${info['modelDirExists']}\n';
    message += '- Dir path: ${info['modelDirPath']}\n';

    if (info['files'] != null) {
      final files = info['files'] as List;
      message += '- Files in dir (${files.length}):\n';
      for (var file in files) {
        final f = file as Map;
        final size = (f['size'] as num) / 1024 / 1024;
        message += '  * ${f['name']} (${size.toStringAsFixed(2)} MB)\n';
      }
    }

    if (info['missingFiles'] != null) {
      final missing = info['missingFiles'] as List;
      if (missing.isNotEmpty) {
        message += '- Missing: ${missing.join(', ')}\n';
      }
    }

    // Show in a dialog
    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Model Verification'),
          content: SingleChildScrollView(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }

    setState(() {
      _statusMessage = info['modelFileExists'] == true
          ? 'Model file found'
          : 'Model file NOT found!';
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _modelPathController.dispose();
    _mmprojPathController.dispose();
    _imagePathController.dispose();
    _promptController.dispose();
    _scrollController.dispose();
    _vlmService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VLM Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isProcessing)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _stopStream,
              tooltip: 'Stop generation',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetContext,
            tooltip: 'Reset context',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isSdkReady ? Icons.check_circle : Icons.pending,
                          color: _isSdkReady ? Colors.green : Colors.orange,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'SDK: ${_isSdkReady ? "Ready" : "Initializing..."}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          _isModelLoaded ? Icons.check_circle : Icons.warning,
                          color: _isModelLoaded ? Colors.green : Colors.orange,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Model: ${_isModelLoaded ? "Loaded" : "Not Loaded"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    if (_statusMessage.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _statusMessage,
                        style: TextStyle(
                          color: _statusMessage.contains('Error')
                              ? Colors.red
                              : Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Model Loading Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Model Configuration',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _modelPathController,
                      decoration: const InputDecoration(
                        labelText: 'Model Path',
                        hintText: 'NPU: files-1-1.nexa | CPU/GPU: .gguf file',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedPluginId,
                      decoration: const InputDecoration(
                        labelText: 'Inference Backend',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'npu',
                          child: Text('NPU (Qualcomm Snapdragon 8 Gen 4)'),
                        ),
                        DropdownMenuItem(
                          value: 'cpu_gpu',
                          child: Text('CPU/GPU (GGUF models)'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedPluginId = value ?? 'npu';
                        });
                      },
                    ),
                    if (_selectedPluginId == 'cpu_gpu') ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _mmprojPathController,
                        decoration: const InputDecoration(
                          labelText: 'MMProj Path (Vision Projection)',
                          hintText: 'e.g., /path/to/mmproj-model-f16.gguf',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'GPU Layers: $_nGpuLayers',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Slider(
                              value: _nGpuLayers.toDouble(),
                              min: 0,
                              max: 999,
                              divisions: 100,
                              label: _nGpuLayers.toString(),
                              onChanged: (value) {
                                setState(() {
                                  _nGpuLayers = value.toInt();
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '0 = auto (999), 999 = offload all layers to GPU',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedDeviceId,
                        decoration: const InputDecoration(
                          labelText: 'Device ID',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'HTP0',
                            child: Text('HTP0 (Qualcomm NPU)'),
                          ),
                          DropdownMenuItem(
                            value: 'GPUOpenCL',
                            child: Text('GPUOpenCL (GPU)'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedDeviceId = value ?? 'HTP0';
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isSdkReady ? _verifyModel : null,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Verify Model'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (_isLoading || !_isSdkReady)
                                ? null
                                : _loadModel,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.download),
                            label: Text(
                              _isLoading ? 'Loading...' : 'Load Model',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Image Processing Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Image Processing',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Image capture buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _takePhoto,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Take Photo'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _pickFromGallery,
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Gallery'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Image preview
                    if (_selectedImageFile != null &&
                        _selectedImageFile!.existsSync())
                      Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                _selectedImageFile!,
                                fit: BoxFit.contain,
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _selectedImageFile = null;
                                      _imagePathController.clear();
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_selectedImageFile != null) const SizedBox(height: 12),

                    // Image path text field
                    TextField(
                      controller: _imagePathController,
                      decoration: InputDecoration(
                        labelText: 'Image Path',
                        hintText:
                            '/data/data/com.nexa.live_cam_learn/files/test1.jpg',
                        border: const OutlineInputBorder(),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              tooltip: 'Load default path',
                              onPressed: () async {
                                final defaultPath = await _vlmService
                                    .getDefaultImagePath();
                                if (defaultPath.isNotEmpty) {
                                  _imagePathController.text = defaultPath;
                                  // Try to load the image preview
                                  final file = File(defaultPath);
                                  if (file.existsSync()) {
                                    setState(() {
                                      _selectedImageFile = file;
                                    });
                                  }
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.folder_open),
                              tooltip: 'Load from path',
                              onPressed: () {
                                final path = _imagePathController.text.trim();
                                if (path.isNotEmpty) {
                                  final file = File(path);
                                  if (file.existsSync()) {
                                    setState(() {
                                      _selectedImageFile = file;
                                      _statusMessage = 'Image loaded';
                                    });
                                  } else {
                                    setState(() {
                                      _statusMessage = 'File not found: $path';
                                    });
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      onChanged: (value) {
                        // Clear preview if path is manually changed
                        if (_selectedImageFile != null &&
                            _selectedImageFile!.path != value) {
                          setState(() {
                            _selectedImageFile = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _promptController,
                      decoration: const InputDecoration(
                        labelText: 'Prompt',
                        hintText: 'What do you want to know about the image?',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (_isModelLoaded && !_isProcessing)
                                ? _processImage
                                : null,
                            icon: _isProcessing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow),
                            label: Text(
                              _isProcessing ? 'Processing...' : 'Process Image',
                            ),
                          ),
                        ),
                        if (_isProcessing) ...[
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _stopStream,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[400],
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Response Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Response',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        if (_response.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _response = '';
                                _translatedResponse = '';
                                _lastProfile = null;
                              });
                            },
                            tooltip: 'Clear response',
                          ),
                      ],
                    ),
                    if (_lastProfile != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildProfileItem(
                              'TTFT',
                              '${_lastProfile!.ttftMs.toStringAsFixed(0)}ms',
                            ),
                            _buildProfileItem(
                              'Prefill',
                              '${_lastProfile!.prefillSpeed.toStringAsFixed(1)} t/s',
                            ),
                            _buildProfileItem(
                              'Decode',
                              '${_lastProfile!.decodingSpeed.toStringAsFixed(1)} t/s',
                            ),
                            _buildProfileItem(
                              'Tokens',
                              '${_lastProfile!.generatedTokens}',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Container(
                      height: 200,
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        child: SelectableText(
                          _response.isEmpty
                              ? 'Response will appear here...'
                              : _response,
                          style: TextStyle(
                            color: _response.isEmpty
                                ? Colors.grey
                                : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Translation Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Translation',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Row(
                          children: [
                            const Text('Enable'),
                            Switch(
                              value: _enableTranslation,
                              onChanged: (value) async {
                                setState(() {
                                  _enableTranslation = value;
                                });
                                if (value && !_isTranslatorReady) {
                                  await _initTranslator();
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedTargetLang,
                            decoration: const InputDecoration(
                              labelText: 'Target Language',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            items: _supportedLanguages.entries.map((entry) {
                              return DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              );
                            }).toList(),
                            onChanged: (value) async {
                              if (value != null &&
                                  value != _selectedTargetLang) {
                                setState(() {
                                  _selectedTargetLang = value;
                                  _isTranslatorReady = false;
                                });
                                if (_enableTranslation) {
                                  await _initTranslator();
                                }
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed:
                              (_enableTranslation &&
                                  _isTranslatorReady &&
                                  _response.isNotEmpty &&
                                  !_isTranslating)
                              ? () => _translateResponse(_response)
                              : null,
                          child: _isTranslating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Translate'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isTranslatorReady
                            ? Colors.green[50]
                            : Colors.orange[50],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isTranslatorReady
                                ? Icons.check_circle
                                : Icons.info_outline,
                            size: 16,
                            color: _isTranslatorReady
                                ? Colors.green
                                : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isTranslatorReady
                                ? 'Translator ready (en -> $_selectedTargetLang)'
                                : 'Enable translation to initialize',
                            style: TextStyle(
                              color: _isTranslatorReady
                                  ? Colors.green[700]
                                  : Colors.orange[700],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_translatedResponse.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Translated Text:',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: SelectableText(
                          _translatedResponse,
                          style: const TextStyle(color: Colors.black87),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Help Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Instructions',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1. Download the OmniNeural-4B-mobile model from Hugging Face\n'
                      '2. Place it in the app\'s files directory\n'
                      '3. Click "Load Model" to initialize\n'
                      '4. Push a test image to the device:\n'
                      '   adb push test.jpg /data/local/tmp/\n'
                      '5. Enter the image path and prompt\n'
                      '6. Click "Process Image" to run inference',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'NPU models: huggingface.co/collections/NexaAI/qualcomm-npu-mobile',
                      style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}
