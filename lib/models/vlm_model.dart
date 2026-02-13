/// VLM Model configuration
/// Defines available models and their metadata

enum ModelPluginType {
  npu, // For NPU models (OmniNeural)
  cpuGpu, // For CPU/GPU models (GGUF)
}

/// Represents a downloadable VLM model
class VlmModel {
  final String id;
  final String displayName;
  final String description;
  final String huggingFaceRepo;
  final String fileSize; // e.g., "365MB", "1.5GB"
  final List<String> files;
  final ModelPluginType pluginType;
  final List<String> supportedLanguages;

  /// The main model file (for GGUF models)
  final String? mainModelFile;

  /// The mmproj file (for GGUF models)
  final String? mmprojFile;

  /// Max image size (longest edge) for resize preprocessing mode
  final int? maxImageSize;

  /// Get the preprocessing mode for this model
  /// - "npu": 448x448 downsample + square crop (OmniNeural)
  /// - "resize": downsample to maxImageSize, keep aspect ratio (Qwen3-VL)
  /// - "none": no preprocessing (SmolVLM, others)
  String get preprocessMode {
    if (pluginType == ModelPluginType.npu) {
      return 'npu';
    } else if (maxImageSize != null) {
      return 'resize';
    }
    return 'none';
  }

  const VlmModel({
    required this.id,
    required this.displayName,
    required this.description,
    required this.huggingFaceRepo,
    required this.fileSize,
    required this.files,
    required this.pluginType,
    required this.supportedLanguages,
    this.mainModelFile,
    this.mmprojFile,
    this.maxImageSize,
  });

  /// Get the folder name for storing the model (extracted from repo name)
  /// e.g., "NexaAI/OmniNeural-4B-mobile" -> "OmniNeural-4B-mobile"
  String get folderName {
    final parts = huggingFaceRepo.split('/');
    return parts.length > 1 ? parts.last : huggingFaceRepo;
  }

  /// Get the base URL for downloading files from HuggingFace
  String get baseDownloadUrl =>
      'https://huggingface.co/$huggingFaceRepo/resolve/main';

  /// Get download URL for a specific file
  String getFileDownloadUrl(String fileName) => '$baseDownloadUrl/$fileName';

  /// Check if this is an NPU model
  bool get isNpuModel => pluginType == ModelPluginType.npu;

  /// Check if this is a GGUF (CPU/GPU) model
  bool get isGgufModel => pluginType == ModelPluginType.cpuGpu;

  /// Get plugin ID string for VLM loading
  String get pluginId => isNpuModel ? 'npu' : 'cpu_gpu';

  /// Get device ID for VLM loading
  String get deviceId => isNpuModel ? 'HTP0' : 'GPUOpenCL';
}

/// Available VLM models
class AvailableModels {
  static const VlmModel smolVlm256m = VlmModel(
    id: 'smolvlm-256m',
    displayName: 'SmolVLM-256M',
    description: 'Lightweight model, Fast inference.',
    huggingFaceRepo: 'ggml-org/SmolVLM-256M-Instruct-GGUF',
    fileSize: '365MB',
    files: [
      // 'SmolVLM-256M-Instruct-Q8_0.gguf',
      'SmolVLM-256M-Instruct-f16.gguf',
      'mmproj-SmolVLM-256M-Instruct-f16.gguf',
    ],
    pluginType: ModelPluginType.cpuGpu,
    supportedLanguages: ['en'],
    // mainModelFile: 'SmolVLM-256M-Instruct-Q8_0.gguf',
    mainModelFile: 'SmolVLM-256M-Instruct-f16.gguf',
    mmprojFile: 'mmproj-SmolVLM-256M-Instruct-f16.gguf',
  );

  static const VlmModel qwen3Vl2b = VlmModel(
    id: 'qwen3-vl-2b',
    displayName: 'Qwen3-VL-2B',
    description: 'Medium model with good quality.',
    huggingFaceRepo: 'Qwen/Qwen3-VL-2B-Instruct-GGUF',
    fileSize: '1.5GB',
    files: [
      'Qwen3VL-2B-Instruct-Q4_K_M.gguf',
      'mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf',
    ],
    pluginType: ModelPluginType.cpuGpu,
    supportedLanguages: ['en', 'zh', 'ja', 'ko', 'fr', 'de', 'es', 'it', 'pt'],
    mainModelFile: 'Qwen3VL-2B-Instruct-Q4_K_M.gguf',
    mmprojFile: 'mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf',
    maxImageSize: 768, // Qwen3-VL requires smaller images
  );

  static const VlmModel omniNeural4b = VlmModel(
    id: 'omnineural-4b',
    displayName: 'OmniNeural 4B (NPU)',
    description: 'NPU-optimized model. Requires Snapdragon.',
    huggingFaceRepo: 'NexaAI/OmniNeural-4B-mobile',
    fileSize: '4GB',
    files: [
      'attachments-1-3.nexa',
      'attachments-2-3.nexa',
      'attachments-3-3.nexa',
      'files-1-1.nexa',
      'nexa.manifest',
      'weights-1-8.nexa',
      'weights-2-8.nexa',
      'weights-3-8.nexa',
      'weights-4-8.nexa',
      'weights-5-8.nexa',
      'weights-6-8.nexa',
      'weights-7-8.nexa',
      'weights-8-8.nexa',
    ],
    pluginType: ModelPluginType.npu,
    supportedLanguages: ['en', 'zh'],
    // For NPU models, mainModelFile points to files-1-1.nexa
    mainModelFile: 'files-1-1.nexa',
  );

  /// List of all available models
  static const List<VlmModel> all = [smolVlm256m, qwen3Vl2b, omniNeural4b];

  /// Get model by ID
  static VlmModel? getById(String id) {
    try {
      return all.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Default model
  static const VlmModel defaultModel = omniNeural4b;
}
