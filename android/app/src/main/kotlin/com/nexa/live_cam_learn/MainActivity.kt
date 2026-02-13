package com.nexa.live_cam_learn

import android.content.ComponentCallbacks2
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {
    
    companion object {
        private const val TAG = "MainActivity"
        private const val METHOD_CHANNEL = "com.nexa.live_cam_learn/vlm"
        private const val EVENT_CHANNEL = "com.nexa.live_cam_learn/vlm_stream"
        private const val PREFS_NAME = "vlm_state"
        private const val KEY_MODEL_LOADED = "model_loaded"
        private const val KEY_MODEL_PATH = "model_path"
        private const val KEY_MMPROJ_PATH = "mmproj_path"
        private const val KEY_PLUGIN_ID = "plugin_id"
        private const val KEY_N_GPU_LAYERS = "n_gpu_layers"
        private const val KEY_DEVICE_ID = "device_id"
    }
    
    private lateinit var vlmHandler: VlmHandler
    private lateinit var translationHandler: TranslationHandler
    private lateinit var segmentationHandler: SegmentationHandler
    private lateinit var ttsHandler: TtsHandler
    private lateinit var prefs: SharedPreferences
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var eventSink: EventChannel.EventSink? = null
    private var methodChannel: MethodChannel? = null
    private var wasModelLoadedBeforePause = false
    private var isReturningFromExternalActivity = false
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize SharedPreferences for state persistence
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        
        // Initialize VLM Handler
        vlmHandler = VlmHandler(this)
        
        // Initialize Translation Handler
        translationHandler = TranslationHandler(this)
        
        // Initialize Segmentation Handler
        segmentationHandler = SegmentationHandler(this)
        
        // Initialize TTS Handler
        ttsHandler = TtsHandler(this)
        
        // Set SDK init callbacks
        vlmHandler.onSdkInitSuccess = {
            Log.d(TAG, "SDK initialized successfully")
            eventSink?.success(mapOf(
                "type" to "sdk_init",
                "data" to "success"
            ))
        }
        
        vlmHandler.onSdkInitFailure = { reason ->
            Log.e(TAG, "SDK init failed: $reason")
            eventSink?.success(mapOf(
                "type" to "sdk_init",
                "data" to "failed: $reason"
            ))
        }
        
        // Initialize SDK
        vlmHandler.initSdk()
        
        // Setup Method Channel for request-response calls
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSdkReady" -> {
                    result.success(vlmHandler.isSdkReady())
                }
                
                "loadModel" -> {
                    val modelPath = call.argument<String>("modelPath") ?: vlmHandler.getDefaultModelPath()
                    val mmprojPath = call.argument<String>("mmprojPath")
                    val pluginId = call.argument<String>("pluginId") ?: "npu"
                    val nGpuLayers = call.argument<Int>("nGpuLayers") ?: 0
                    val deviceId = call.argument<String>("deviceId") ?: "HTP0"
                    
                    scope.launch {
                        val success = vlmHandler.loadModel(
                            modelPath = modelPath,
                            mmprojPath = mmprojPath,
                            pluginId = pluginId,
                            nGpuLayers = nGpuLayers,
                            deviceId = deviceId
                        )
                        
                        // Save model config for auto-reload after camera
                        if (success) {
                            prefs.edit().apply {
                                putBoolean(KEY_MODEL_LOADED, true)
                                putString(KEY_MODEL_PATH, modelPath)
                                putString(KEY_MMPROJ_PATH, mmprojPath)
                                putString(KEY_PLUGIN_ID, pluginId)
                                putInt(KEY_N_GPU_LAYERS, nGpuLayers)
                                putString(KEY_DEVICE_ID, deviceId)
                                apply()
                            }
                            Log.d(TAG, "Model config saved for auto-reload")
                        }
                        
                        result.success(mapOf(
                            "success" to success,
                            "message" to if (success) "Model loaded successfully" else "Failed to load model"
                        ))
                    }
                }
                
                "isModelLoaded" -> {
                    result.success(vlmHandler.isLoaded())
                }
                
                "getDefaultModelPath" -> {
                    result.success(vlmHandler.getDefaultModelPath())
                }
                
                "getDefaultImagePath" -> {
                    result.success(vlmHandler.getDefaultImagePath())
                }
                
                "getNativeLibPath" -> {
                    result.success(vlmHandler.getNativeLibPath())
                }
                
                "listAvailableModels" -> {
                    result.success(vlmHandler.listAvailableModels())
                }
                
                "verifyModelPath" -> {
                    val modelPath = call.argument<String>("modelPath")
                    if (modelPath == null) {
                        result.error("INVALID_ARGS", "modelPath is required", null)
                        return@setMethodCallHandler
                    }
                    
                    val modelFile = java.io.File(modelPath)
                    val modelDir = modelFile.parentFile
                    
                    val info = mutableMapOf<String, Any>()
                    info["modelFileExists"] = modelFile.exists()
                    info["modelDirExists"] = modelDir?.exists() ?: false
                    info["modelDirPath"] = modelDir?.absolutePath ?: ""
                    
                    if (modelDir?.exists() == true) {
                        val files = modelDir.listFiles()?.map { 
                            mapOf("name" to it.name, "size" to it.length(), "isFile" to it.isFile)
                        } ?: emptyList()
                        info["files"] = files
                        info["missingFiles"] = vlmHandler.verifyModelDirectory(modelDir)
                    }
                    
                    result.success(info)
                }
                
                "processImage" -> {
                    val imagePath = call.argument<String>("imagePath")
                    val prompt = call.argument<String>("prompt")
                    val enableThinking = call.argument<Boolean>("enableThinking") ?: false
                    val preprocessMode = call.argument<String>("preprocessMode") ?: "none"
                    val maxImageSize = call.argument<Int>("maxImageSize") ?: 768
                    
                    if (imagePath == null || prompt == null) {
                        result.error("INVALID_ARGS", "imagePath and prompt are required", null)
                        return@setMethodCallHandler
                    }
                    
                    // Return immediately, results will be sent via EventChannel
                    result.success(mapOf("status" to "processing"))
                    
                    vlmHandler.processImage(
                        imagePath = imagePath,
                        prompt = prompt,
                        enableThinking = enableThinking,
                        preprocessMode = preprocessMode,
                        maxImageSize = maxImageSize,
                        onToken = { token ->
                            eventSink?.success(mapOf(
                                "type" to "token",
                                "data" to token
                            ))
                        },
                        onComplete = { fullResponse, profile ->
                            eventSink?.success(mapOf(
                                "type" to "complete",
                                "data" to fullResponse,
                                "profile" to profile?.let {
                                    mapOf(
                                        "ttftMs" to it.ttftMs,
                                        "promptTokens" to it.promptTokens,
                                        "prefillSpeed" to it.prefillSpeed,
                                        "generatedTokens" to it.generatedTokens,
                                        "decodingSpeed" to it.decodingSpeed
                                    )
                                }
                            ))
                        },
                        onError = { error ->
                            eventSink?.success(mapOf(
                                "type" to "error",
                                "data" to error
                            ))
                        }
                    )
                }
                
                "stopStream" -> {
                    vlmHandler.stopStream()
                    result.success(true)
                }
                
                "resetContext" -> {
                    vlmHandler.resetContext()
                    result.success(true)
                }
                
                "release" -> {
                    vlmHandler.release()
                    // Clear saved model state
                    prefs.edit().putBoolean(KEY_MODEL_LOADED, false).apply()
                    result.success(true)
                }
                
                // Translation methods
                "initTranslator" -> {
                    val sourceLang = call.argument<String>("sourceLang") ?: "en"
                    val targetLang = call.argument<String>("targetLang") ?: "es"
                    val requireWifi = call.argument<Boolean>("requireWifi") ?: true
                    
                    scope.launch {
                        val initResult = translationHandler.initTranslator(
                            sourceLang = sourceLang,
                            targetLang = targetLang,
                            requireWifi = requireWifi
                        )
                        result.success(mapOf(
                            "success" to initResult.isSuccess,
                            "message" to (initResult.exceptionOrNull()?.message ?: "Translator initialized")
                        ))
                    }
                }
                
                "translate" -> {
                    val text = call.argument<String>("text")
                    if (text == null) {
                        result.error("INVALID_ARGS", "text is required", null)
                        return@setMethodCallHandler
                    }
                    
                    scope.launch {
                        val translateResult = translationHandler.translate(text)
                        translateResult.onSuccess { translatedText ->
                            result.success(mapOf(
                                "success" to true,
                                "translatedText" to translatedText
                            ))
                        }.onFailure { error ->
                            result.success(mapOf(
                                "success" to false,
                                "error" to (error.message ?: "Translation failed")
                            ))
                        }
                    }
                }
                
                "isTranslatorReady" -> {
                    result.success(translationHandler.isReady())
                }
                
                "getDownloadedTranslationModels" -> {
                    scope.launch {
                        val models = translationHandler.getDownloadedModels()
                        result.success(models)
                    }
                }
                
                "downloadTranslationModel" -> {
                    val languageCode = call.argument<String>("languageCode")
                    val requireWifi = call.argument<Boolean>("requireWifi") ?: true
                    
                    if (languageCode == null) {
                        result.error("INVALID_ARGS", "languageCode is required", null)
                        return@setMethodCallHandler
                    }
                    
                    scope.launch {
                        val downloadResult = translationHandler.downloadModel(languageCode, requireWifi)
                        result.success(mapOf(
                            "success" to downloadResult.isSuccess,
                            "message" to (downloadResult.exceptionOrNull()?.message ?: "Model downloaded")
                        ))
                    }
                }
                
                "deleteTranslationModel" -> {
                    val languageCode = call.argument<String>("languageCode")
                    if (languageCode == null) {
                        result.error("INVALID_ARGS", "languageCode is required", null)
                        return@setMethodCallHandler
                    }
                    
                    scope.launch {
                        val deleteResult = translationHandler.deleteModel(languageCode)
                        result.success(mapOf(
                            "success" to deleteResult.isSuccess,
                            "message" to (deleteResult.exceptionOrNull()?.message ?: "Model deleted")
                        ))
                    }
                }
                
                "getSupportedLanguages" -> {
                    result.success(translationHandler.getSupportedLanguages())
                }
                
                "releaseTranslator" -> {
                    translationHandler.release()
                    result.success(true)
                }
                
                // Segmentation methods
                "initSegmenter" -> {
                    val success = segmentationHandler.initialize()
                    result.success(mapOf(
                        "success" to success,
                        "message" to if (success) "Segmenter initialized" else "Failed to initialize segmenter"
                    ))
                }
                
                "isSegmenterReady" -> {
                    result.success(segmentationHandler.isReady())
                }
                
                "warmupSegmenter" -> {
                    scope.launch {
                        val success = segmentationHandler.warmup()
                        result.success(mapOf(
                            "success" to success,
                            "message" to if (success) "Segmenter warmed up and model ready" else "Warmup failed"
                        ))
                    }
                }
                
                "segmentImage" -> {
                    val imagePath = call.argument<String>("imagePath")
                    val outputPath = call.argument<String>("outputPath")
                    
                    if (imagePath == null || outputPath == null) {
                        result.error("INVALID_ARGS", "imagePath and outputPath are required", null)
                        return@setMethodCallHandler
                    }
                    
                    scope.launch {
                        val segResult = segmentationHandler.segmentImage(imagePath, outputPath)
                        result.success(mapOf(
                            "success" to segResult.success,
                            "outputPath" to segResult.outputPath,
                            "error" to segResult.error
                        ))
                    }
                }
                
                "releaseSegmenter" -> {
                    segmentationHandler.release()
                    result.success(true)
                }
                
                // TTS methods
                "initTts" -> {
                    ttsHandler.initialize { success ->
                        result.success(mapOf(
                            "success" to success,
                            "message" to if (success) "TTS initialized" else "Failed to initialize TTS"
                        ))
                    }
                }
                
                "isTtsReady" -> {
                    result.success(ttsHandler.isReady())
                }
                
                "ttsSpeak" -> {
                    val text = call.argument<String>("text")
                    val languageCode = call.argument<String>("languageCode")
                    
                    if (text == null) {
                        result.error("INVALID_ARGS", "text is required", null)
                        return@setMethodCallHandler
                    }
                    
                    // Set up callbacks to send events (must run on UI thread for EventChannel)
                    ttsHandler.onSpeakStart = { utteranceId ->
                        runOnUiThread {
                            eventSink?.success(mapOf(
                                "type" to "tts_start",
                                "utteranceId" to utteranceId
                            ))
                        }
                    }
                    
                    ttsHandler.onSpeakDone = { utteranceId ->
                        Log.d(TAG, "TTS onSpeakDone callback fired, utteranceId=$utteranceId, posting to UI thread")
                        runOnUiThread {
                            Log.d(TAG, "TTS onSpeakDone sending event via eventSink")
                            eventSink?.success(mapOf(
                                "type" to "tts_done",
                                "utteranceId" to utteranceId
                            ))
                        }
                    }
                    
                    ttsHandler.onSpeakError = { utteranceId, error ->
                        runOnUiThread {
                            eventSink?.success(mapOf(
                                "type" to "tts_error",
                                "utteranceId" to utteranceId,
                                "error" to error
                            ))
                        }
                    }
                    
                    val utteranceId = ttsHandler.speak(text, languageCode)
                    result.success(mapOf(
                        "success" to (utteranceId != null),
                        "utteranceId" to utteranceId
                    ))
                }
                
                "ttsStop" -> {
                    ttsHandler.stop()
                    result.success(true)
                }
                
                "ttsIsSpeaking" -> {
                    result.success(ttsHandler.isSpeaking())
                }
                
                "ttsSetLanguage" -> {
                    val languageCode = call.argument<String>("languageCode")
                    if (languageCode == null) {
                        result.error("INVALID_ARGS", "languageCode is required", null)
                        return@setMethodCallHandler
                    }
                    
                    val success = ttsHandler.setLanguage(languageCode)
                    result.success(mapOf(
                        "success" to success,
                        "message" to if (success) "Language set to $languageCode" else "Language not supported: $languageCode"
                    ))
                }
                
                "ttsIsLanguageAvailable" -> {
                    val languageCode = call.argument<String>("languageCode")
                    if (languageCode == null) {
                        result.error("INVALID_ARGS", "languageCode is required", null)
                        return@setMethodCallHandler
                    }
                    
                    result.success(ttsHandler.isLanguageAvailable(languageCode))
                }
                
                "ttsGetAvailableLanguages" -> {
                    result.success(ttsHandler.getAvailableLanguages())
                }
                
                "ttsSetSpeechRate" -> {
                    val rate = call.argument<Double>("rate")?.toFloat() ?: 1.0f
                    ttsHandler.setSpeechRate(rate)
                    result.success(true)
                }
                
                "ttsSetPitch" -> {
                    val pitch = call.argument<Double>("pitch")?.toFloat() ?: 1.0f
                    ttsHandler.setPitch(pitch)
                    result.success(true)
                }
                
                "releaseTts" -> {
                    ttsHandler.release()
                    result.success(true)
                }
                
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Setup Event Channel for streaming responses
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }
    
    override fun onPause() {
        super.onPause()
        // Remember if model was loaded before pause
        wasModelLoadedBeforePause = vlmHandler.isLoaded()
        isReturningFromExternalActivity = true
        Log.d(TAG, "onPause - Model was loaded: $wasModelLoadedBeforePause")
    }
    
    override fun onResume() {
        super.onResume()
        Log.d(TAG, "onResume - isReturningFromExternalActivity: $isReturningFromExternalActivity")
        
        if (isReturningFromExternalActivity) {
            isReturningFromExternalActivity = false
            
            // Check if model should be loaded but isn't
            val shouldBeLoaded = prefs.getBoolean(KEY_MODEL_LOADED, false)
            val isCurrentlyLoaded = vlmHandler.isLoaded()
            
            Log.d(TAG, "onResume - shouldBeLoaded: $shouldBeLoaded, isCurrentlyLoaded: $isCurrentlyLoaded")
            
            if (shouldBeLoaded && !isCurrentlyLoaded) {
                Log.d(TAG, "Model was lost, auto-reloading...")
                
                // Notify Flutter that we're reloading
                eventSink?.success(mapOf(
                    "type" to "model_reloading",
                    "data" to "Auto-reloading model after camera..."
                ))
                
                // Auto-reload the model
                val modelPath = prefs.getString(KEY_MODEL_PATH, vlmHandler.getDefaultModelPath()) ?: vlmHandler.getDefaultModelPath()
                val mmprojPath = prefs.getString(KEY_MMPROJ_PATH, null)
                val pluginId = prefs.getString(KEY_PLUGIN_ID, "npu") ?: "npu"
                val nGpuLayers = prefs.getInt(KEY_N_GPU_LAYERS, 0)
                val deviceId = prefs.getString(KEY_DEVICE_ID, "HTP0") ?: "HTP0"
                
                scope.launch {
                    // Re-initialize SDK if needed
                    if (!vlmHandler.isSdkReady()) {
                        Log.d(TAG, "Re-initializing SDK...")
                        vlmHandler.initSdk()
                        // Wait a bit for SDK to initialize
                        delay(500)
                    }
                    
                    val success = vlmHandler.loadModel(
                        modelPath = modelPath,
                        mmprojPath = mmprojPath,
                        pluginId = pluginId,
                        nGpuLayers = nGpuLayers,
                        deviceId = deviceId
                    )
                    
                    Log.d(TAG, "Auto-reload result: $success")
                    
                    // Notify Flutter about the reload result
                    eventSink?.success(mapOf(
                        "type" to "model_reloaded",
                        "data" to if (success) "success" else "failed"
                    ))
                }
            }
        }
    }
    
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        // Log memory pressure levels for debugging
        val levelName = when (level) {
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_MODERATE -> "RUNNING_MODERATE"
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW -> "RUNNING_LOW"
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL -> "RUNNING_CRITICAL"
            ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN -> "UI_HIDDEN"
            ComponentCallbacks2.TRIM_MEMORY_BACKGROUND -> "BACKGROUND"
            ComponentCallbacks2.TRIM_MEMORY_MODERATE -> "MODERATE"
            ComponentCallbacks2.TRIM_MEMORY_COMPLETE -> "COMPLETE"
            else -> "UNKNOWN($level)"
        }
        Log.w(TAG, "onTrimMemory: $levelName - Model loaded: ${vlmHandler.isLoaded()}")
        
        // We intentionally don't release the model here to try to keep it loaded
        // The system will kill the process if it really needs the memory
    }
    
    override fun onDestroy() {
        scope.cancel()
        vlmHandler.release()
        translationHandler.release()
        segmentationHandler.release()
        ttsHandler.release()
        super.onDestroy()
    }
}
