package com.nexa.live_cam_learn

import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.util.Log
import com.nexa.sdk.NexaSdk
import com.nexa.sdk.VlmWrapper
import com.nexa.sdk.bean.VlmCreateInput
import com.nexa.sdk.bean.VlmContent
import com.nexa.sdk.bean.VlmChatMessage
import com.nexa.sdk.bean.LlmStreamResult
import com.nexa.sdk.bean.ModelConfig
import com.nexa.sdk.bean.GenerationConfig
// ImgUtil is in the same package
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collect
import java.io.File

/**
 * VLM (Vision Language Model) Handler for Nexa SDK
 * Provides methods to load VLM model and process images with text prompts
 */
class VlmHandler(private val context: Context) {
    
    companion object {
        private const val TAG = "VlmHandler"
        private const val MODEL_NAME = "omni-neural"
        private const val PLUGIN_ID = "npu" // Use "cpu_gpu" for non-NPU devices
    }
    
    private var vlmWrapper: VlmWrapper? = null
    private var isModelLoaded = false
    private var isSdkInitialized = false
    private var currentPluginId: String = "npu" // Track current model type for preprocessing
    private var scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    // Callbacks for SDK init status
    var onSdkInitSuccess: (() -> Unit)? = null
    var onSdkInitFailure: ((String) -> Unit)? = null
    
    /**
     * Initialize the Nexa SDK with callback
     */
    fun initSdk() {
        NexaSdk.getInstance().init(context, object : NexaSdk.InitCallback {
            override fun onSuccess() {
                isSdkInitialized = true
                Log.d(TAG, "Nexa SDK initialized successfully")
                onSdkInitSuccess?.invoke()
            }
            
            override fun onFailure(reason: String) {
                isSdkInitialized = false
                Log.e(TAG, "Nexa SDK init failed: $reason")
                onSdkInitFailure?.invoke(reason)
            }
        })
    }
    
    /**
     * Check if SDK is initialized
     */
    fun isSdkReady(): Boolean = isSdkInitialized
    
    /**
     * Verify model directory has required files
     * @param modelDir The model directory to check
     * @return List of missing files, empty if all present
     */
    fun verifyModelDirectory(modelDir: File): List<String> {
        val missingFiles = mutableListOf<String>()
        
        // Check for common required files
        val requiredPatterns = listOf(
            ".*\\.nexa$" to "NEXA model file",
            "nexa.manifest" to "Manifest file"
        )
        
        val files = modelDir.listFiles() ?: emptyArray()
        val fileNames = files.map { it.name }
        
        for ((pattern, description) in requiredPatterns) {
            val regex = Regex(pattern)
            if (!fileNames.any { regex.matches(it) }) {
                missingFiles.add(description)
            }
        }
        
        return missingFiles
    }
    
    /**
     * List available model files in the models directory
     */
    fun listAvailableModels(): List<String> {
        val modelsDir = File(context.filesDir, "models")
        if (!modelsDir.exists()) {
            Log.d(TAG, "Models directory does not exist: ${modelsDir.absolutePath}")
            return emptyList()
        }
        
        return modelsDir.listFiles()?.filter { it.isDirectory }?.map { dir ->
            val nexaFiles = dir.listFiles()?.filter { it.name.endsWith(".nexa") } ?: emptyList()
            "${dir.name}: ${nexaFiles.map { it.name }}"
        } ?: emptyList()
    }
    
    /**
     * Load VLM model from specified path
     * @param modelPath Path to model folder (for NPU) or .gguf file (for CPU/GPU)
     * @param mmprojPath Optional path to multimodal projection file (for CPU/GPU)
     * @param pluginId "npu" for NPU inference, "cpu_gpu" for CPU/GPU
     * @param nGpuLayers Number of GPU layers for CPU/GPU mode (0 = auto)
     * @param maxTokens Maximum tokens for generation
     * @param deviceId Device ID for CPU/GPU mode: "HTP0" (Qualcomm NPU) or "GPUOpenCL" (GPU)
     * @return true if model loaded successfully
     */
    suspend fun loadModel(
        modelPath: String,
        mmprojPath: String? = null,
        pluginId: String = PLUGIN_ID,
        nGpuLayers: Int = 0,
        maxTokens: Int = 2048,
        deviceId: String = "HTP0"
    ): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                if (!isSdkInitialized) {
                    Log.e(TAG, "SDK not initialized. Call initSdk() first.")
                    return@withContext false
                }
                
                Log.d(TAG, "Loading VLM model from: $modelPath")
                Log.d(TAG, "Plugin ID: $pluginId")
                
                val modelFile = File(modelPath)
                
                // Both NPU and CPU/GPU: modelPath should be a file
                // NPU: path to files-1-1.nexa
                // CPU/GPU: path to .gguf file
                if (!modelFile.exists()) {
                    Log.e(TAG, "Model file does not exist: $modelPath")
                    return@withContext false
                }
                
                // Log model directory contents for debugging
                val modelDir = modelFile.parentFile
                if (modelDir != null) {
                    Log.d(TAG, "Model directory: ${modelDir.absolutePath}")
                    Log.d(TAG, "Model directory contents:")
                    modelDir.listFiles()?.forEach { file ->
                        Log.d(TAG, "  - ${file.name} (${file.length() / 1024 / 1024} MB)")
                    }
                }
                
                // Configure ModelConfig and VlmCreateInput based on plugin type
                val createInput = if (pluginId == "npu") {
                    // NPU mode - simple config
                    val config = ModelConfig(
                        max_tokens = maxTokens,
                        enable_thinking = false
                    )
                    Log.d(TAG, "NPU ModelConfig: max_tokens=$maxTokens, enable_thinking=false")
                    
                    VlmCreateInput(
                        model_name = MODEL_NAME,
                        model_path = modelPath,
                        config = config,
                        plugin_id = pluginId
                    )
                } else {
                    // CPU/GPU mode for GGUF models (e.g., Qwen3-VL)
                    // nGpuLayers > 0 enables offloading; 999 attempts to offload all layers
                    val effectiveGpuLayers = if (nGpuLayers == 0) 999 else nGpuLayers
                    val config = ModelConfig(
                        nCtx = 4096,
                        nGpuLayers = effectiveGpuLayers
                    )
                    Log.d(TAG, "CPU/GPU ModelConfig: nCtx=4096, nGpuLayers=$effectiveGpuLayers")
                    Log.d(TAG, "mmproj_path: $mmprojPath")
                    Log.d(TAG, "device_id: $deviceId")
                    
                    VlmCreateInput(
                        model_name = "",  // GGUF: keep model_name empty
                        model_path = modelPath,
                        mmproj_path = mmprojPath,  // vision projection weights
                        config = config,
                        plugin_id = pluginId,
                        device_id = deviceId  // "HTP0" for Qualcomm NPU, "GPUOpenCL" for GPU
                    )
                }
                
                Log.d(TAG, "Creating VLM with: model_name=${createInput.model_name}, model_path=${createInput.model_path}, plugin_id=${createInput.plugin_id}")
                
                VlmWrapper.builder()
                    .vlmCreateInput(createInput)
                    .build()
                    .onSuccess { wrapper ->
                        vlmWrapper = wrapper
                        isModelLoaded = true
                        currentPluginId = pluginId // Track for preprocessing decisions
                        Log.d(TAG, "VLM model loaded successfully (pluginId=$pluginId)")
                    }
                    .onFailure { error ->
                        Log.e(TAG, "Failed to load VLM model: ${error.message}")
                        error.printStackTrace()
                        isModelLoaded = false
                    }
                
                isModelLoaded
            } catch (e: Exception) {
                Log.e(TAG, "Exception loading VLM model: ${e.message}")
                e.printStackTrace()
                isModelLoaded = false
                false
            }
        }
    }
    
    /**
     * Process an image with a text prompt using the VLM
     * @param imagePath Path to the image file
     * @param prompt Text prompt for the model
     * @param enableThinking Enable thinking mode for supported models
     * @param preprocessMode Image preprocessing mode: "npu" (448x448 crop), "resize" (downscale only), "none"
     * @param maxImageSize Max size for resize mode (longest edge)
     * @param onToken Callback for each generated token (streaming)
     * @param onComplete Callback when generation is complete with performance profile
     * @param onError Callback for errors
     */
    fun processImage(
        imagePath: String,
        prompt: String,
        enableThinking: Boolean = false,
        preprocessMode: String = "none",
        maxImageSize: Int = 768,
        onToken: (String) -> Unit,
        onComplete: (String, PerformanceProfile?) -> Unit,
        onError: (String) -> Unit
    ) {
        if (!isModelLoaded || vlmWrapper == null) {
            onError("Model not loaded. Please load model first.")
            return
        }
        
        scope.launch {
            try {
                val imageFile = File(imagePath)
                if (!imageFile.exists()) {
                    withContext(Dispatchers.Main) {
                        onError("Image file does not exist: $imagePath")
                    }
                    return@launch
                }
                
                Log.d(TAG, "Processing image: $imagePath with prompt: $prompt, preprocessMode: $preprocessMode")
                
                // Preprocess image based on mode:
                // - "npu": downscale and square crop to 448x448 (OmniNeural)
                // - "resize": downscale to maxImageSize, keep aspect ratio (Qwen3-VL)
                // - "none": no preprocessing (SmolVLM, others)
                val processedImagePath = withContext(Dispatchers.IO) {
                    when (preprocessMode) {
                        "npu" -> preprocessImageForNpu(imageFile)
                        "resize" -> preprocessImageResize(imageFile, maxImageSize)
                        else -> imagePath // "none" - use original
                    }
                }
                
                Log.d(TAG, "Image path for VLM: $processedImagePath (preprocessMode=$preprocessMode)")
                
                // Create content list with preprocessed image and text
                val contents = listOf(
                    VlmContent("image", processedImagePath),
                    VlmContent("text", prompt)
                )
                
                // Create chat message
                val chatList = arrayListOf(VlmChatMessage("user", contents))
                
                // Apply chat template
                vlmWrapper!!.applyChatTemplate(chatList.toTypedArray(), null, enableThinking)
                    .onSuccess { template ->
                        // Inject media paths and generate response
                        val baseConfig = GenerationConfig(maxTokens=2048)
                        val configWithMedia = vlmWrapper!!.injectMediaPathsToConfig(
                            chatList.toTypedArray(),
                            baseConfig
                        )
                        
                        val fullResponse = StringBuilder()
                        
                        scope.launch {
                            try {
                                vlmWrapper!!.generateStreamFlow(template.formattedText, configWithMedia)
                                    .collect { result ->
                                        when (result) {
                                            is LlmStreamResult.Token -> {
                                                fullResponse.append(result.text)
                                                withContext(Dispatchers.Main) {
                                                    onToken(result.text)
                                                }
                                            }
                                            is LlmStreamResult.Completed -> {
                                                val profile = result.profile
                                                Log.d(TAG, "Generation completed - TTFT: ${profile.ttftMs}ms, " +
                                                    "Prefill: ${profile.prefillSpeed} tok/s, " +
                                                    "Decoding: ${profile.decodingSpeed} tok/s")
                                                Log.d(TAG, "VLM Output: ${fullResponse.toString()}")
                                                
                                                // Clean up preprocessed image cache
                                                cleanupPreprocessedImage(processedImagePath, imagePath)
                                                
                                                val perfProfile = PerformanceProfile(
                                                    ttftMs = profile.ttftMs,
                                                    promptTokens = profile.promptTokens.toInt(),
                                                    prefillSpeed = profile.prefillSpeed,
                                                    generatedTokens = profile.generatedTokens.toInt(),
                                                    decodingSpeed = profile.decodingSpeed
                                                )
                                                
                                                withContext(Dispatchers.Main) {
                                                    onComplete(fullResponse.toString(), perfProfile)
                                                }
                                            }
                                            is LlmStreamResult.Error -> {
                                                Log.e(TAG, "Generation error: ${result.throwable.message}")
                                                // Clean up preprocessed image cache
                                                cleanupPreprocessedImage(processedImagePath, imagePath)
                                                withContext(Dispatchers.Main) {
                                                    onError(result.throwable.message ?: "Unknown error")
                                                }
                                            }
                                        }
                                    }
                            } catch (e: Exception) {
                                Log.e(TAG, "Stream error: ${e.message}")
                                cleanupPreprocessedImage(processedImagePath, imagePath)
                                withContext(Dispatchers.Main) {
                                    onError(e.message ?: "Stream error")
                                }
                            }
                        }
                    }
                    .onFailure { error ->
                        Log.e(TAG, "Failed to apply chat template: ${error.message}")
                        cleanupPreprocessedImage(processedImagePath, imagePath)
                        scope.launch(Dispatchers.Main) {
                            onError(error.message ?: "Failed to apply chat template")
                        }
                    }
                    
            } catch (e: Exception) {
                Log.e(TAG, "Exception processing image: ${e.message}")
                withContext(Dispatchers.Main) {
                    onError(e.message ?: "Exception processing image")
                }
            }
        }
    }
    
    /**
     * Clean up preprocessed image from cache
     * Only deletes if it's different from the original (i.e., was preprocessed)
     */
    private fun cleanupPreprocessedImage(processedPath: String, originalPath: String) {
        if (processedPath != originalPath) {
            try {
                val file = File(processedPath)
                if (file.exists()) {
                    file.delete()
                    Log.d(TAG, "Cleaned up preprocessed image: $processedPath")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clean up preprocessed image: ${e.message}")
            }
        }
    }
    
    /**
     * Stop ongoing stream generation
     */
    fun stopStream() {
        scope.launch {
            vlmWrapper?.stopStream()
            Log.d(TAG, "Stream stopped")
        }
    }
    
    /**
     * Reset the model context
     */
    fun resetContext() {
        scope.launch {
            vlmWrapper?.reset()
            Log.d(TAG, "Context reset")
        }
    }
    
    /**
     * Check if model is loaded
     */
    fun isLoaded(): Boolean = isModelLoaded
    
    /**
     * Get the default model path for this app
     * For NPU: pass the path to files-1-1.nexa file
     * For CPU/GPU: pass the .gguf file path
     */
    fun getDefaultModelPath(): String {
         return "/data/data/com.nexa.live_cam_learn/files/models/OmniNeural-4B-mobile/files-1-1.nexa"
    //    return "${context.filesDir.absolutePath}/models/Qwen3-VL-4B-Instruct-GGUF/Qwen3VL-4B-Instruct-Q4_K_M.gguf"
    }
    
    /**
     * Get the default test image path
     */
    fun getDefaultImagePath(): String {
        return "/data/data/com.nexa.live_cam_learn/files/demo.jpeg"
    }
    
    /**
     * Get the native library directory path
     */
    fun getNativeLibPath(): String {
        return context.applicationInfo.nativeLibraryDir
    }
    
    /**
     * Preprocess image for NPU models (OmniNeural)
     * - Downscales to max 448px on longest edge
     * - Square crops to 448x448
     */
    private fun preprocessImageForNpu(imageFile: File): String {
        val cacheDir = context.cacheDir
        val timestamp = System.currentTimeMillis()
        
        // Step 1: Downscale image to max 448px on longest edge
        val downscaledFile = File(cacheDir, "downscaled_$timestamp.jpg")
        ImgUtil.downscaleAndSave(
            imageFile = imageFile,
            outFile = downscaledFile,
            maxSize = 448,
            format = Bitmap.CompressFormat.JPEG,
            quality = 90
        )
        
        // Step 2: Square crop to 448x448
        val croppedFile = File(cacheDir, "cropped_$timestamp.jpg")
        ImgUtil.squareCrop(
            imageFile = downscaledFile,
            outFile = croppedFile,
            size = 448
        )
        
        // Clean up intermediate file
        if (downscaledFile.exists() && downscaledFile != croppedFile) {
            downscaledFile.delete()
        }
        
        Log.d(TAG, "NPU image preprocessed: ${imageFile.absolutePath} -> ${croppedFile.absolutePath} (448x448)")
        return croppedFile.absolutePath
    }
    
    /**
     * Preprocess image by resizing only (no crop)
     * - Downscales to maxSize on longest edge, keeps aspect ratio
     * Used for models like Qwen3-VL
     */
    private fun preprocessImageResize(imageFile: File, maxSize: Int): String {
        val cacheDir = context.cacheDir
        val timestamp = System.currentTimeMillis()
        
        val resizedFile = File(cacheDir, "resized_$timestamp.jpg")
        ImgUtil.downscaleAndSave(
            imageFile = imageFile,
            outFile = resizedFile,
            maxSize = maxSize,
            format = Bitmap.CompressFormat.JPEG,
            quality = 90
        )
        
        Log.d(TAG, "Image resized: ${imageFile.absolutePath} -> ${resizedFile.absolutePath} (max $maxSize px)")
        return resizedFile.absolutePath
    }
    
    /**
     * Release resources
     */
    fun release() {
        // Cancel current scope and create a new one for future use
        scope.cancel()
        scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        
        vlmWrapper?.destroy()
        vlmWrapper = null
        isModelLoaded = false
        currentPluginId = "npu" // Reset to default
        Log.d(TAG, "VLM resources released")
    }
}

/**
 * Performance profile data class
 */
data class PerformanceProfile(
    val ttftMs: Double,           // Time to first token (ms)
    val promptTokens: Int,        // Number of prompt tokens
    val prefillSpeed: Double,     // Prefill speed (tok/s)
    val generatedTokens: Int,     // Number of generated tokens
    val decodingSpeed: Double     // Decoding speed (tok/s)
)
