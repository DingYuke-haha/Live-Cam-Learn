package com.nexa.live_cam_learn

import android.content.Context
import android.util.Log
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Translation Handler using Google ML Kit
 * Provides offline translation capabilities
 */
class TranslationHandler(private val context: Context) {
    
    companion object {
        private const val TAG = "TranslationHandler"
        
        // Supported languages mapping (language code -> TranslateLanguage)
        val SUPPORTED_LANGUAGES = mapOf(
            "en" to TranslateLanguage.ENGLISH,
            "es" to TranslateLanguage.SPANISH,
            "zh" to TranslateLanguage.CHINESE,
            "fr" to TranslateLanguage.FRENCH,
            "de" to TranslateLanguage.GERMAN,
            "it" to TranslateLanguage.ITALIAN,
            "ja" to TranslateLanguage.JAPANESE,
            "ko" to TranslateLanguage.KOREAN,
            "pt" to TranslateLanguage.PORTUGUESE,
            "ru" to TranslateLanguage.RUSSIAN,
            "ar" to TranslateLanguage.ARABIC,
            "hi" to TranslateLanguage.HINDI,
            "vi" to TranslateLanguage.VIETNAMESE,
            "th" to TranslateLanguage.THAI,
            "id" to TranslateLanguage.INDONESIAN,
            "tr" to TranslateLanguage.TURKISH,
            "nl" to TranslateLanguage.DUTCH,
            "pl" to TranslateLanguage.POLISH,
            "uk" to TranslateLanguage.UKRAINIAN,
            "cs" to TranslateLanguage.CZECH,
            "sv" to TranslateLanguage.SWEDISH,
            "da" to TranslateLanguage.DANISH,
            "fi" to TranslateLanguage.FINNISH,
            "el" to TranslateLanguage.GREEK,
            "he" to TranslateLanguage.HEBREW,
            "hu" to TranslateLanguage.HUNGARIAN,
            "no" to TranslateLanguage.NORWEGIAN,
            "ro" to TranslateLanguage.ROMANIAN,
            "sk" to TranslateLanguage.SLOVAK,
            "bg" to TranslateLanguage.BULGARIAN,
            "ca" to TranslateLanguage.CATALAN,
            "hr" to TranslateLanguage.CROATIAN,
            "lt" to TranslateLanguage.LITHUANIAN,
            "lv" to TranslateLanguage.LATVIAN,
            "sl" to TranslateLanguage.SLOVENIAN,
            "et" to TranslateLanguage.ESTONIAN,
            "ms" to TranslateLanguage.MALAY,
            "tl" to TranslateLanguage.TAGALOG,
            "bn" to TranslateLanguage.BENGALI,
            "ta" to TranslateLanguage.TAMIL,
            "te" to TranslateLanguage.TELUGU,
            "mr" to TranslateLanguage.MARATHI,
            "ur" to TranslateLanguage.URDU,
            "fa" to TranslateLanguage.PERSIAN,
            "sw" to TranslateLanguage.SWAHILI,
            "af" to TranslateLanguage.AFRIKAANS,
            "ga" to TranslateLanguage.IRISH,
            "cy" to TranslateLanguage.WELSH,
            "sq" to TranslateLanguage.ALBANIAN,
            "be" to TranslateLanguage.BELARUSIAN,
            "mk" to TranslateLanguage.MACEDONIAN,
            "eo" to TranslateLanguage.ESPERANTO
        )
        
        // Default source language (English - model output)
        const val DEFAULT_SOURCE = "en"
        // Default target language (Spanish)
        const val DEFAULT_TARGET = "es"
    }
    
    private var currentTranslator: Translator? = null
    private var currentSourceLang: String = DEFAULT_SOURCE
    private var currentTargetLang: String = DEFAULT_TARGET
    private var isModelReady = false
    
    private val modelManager = RemoteModelManager.getInstance()
    
    /**
     * Initialize translator with source and target languages
     * Downloads required models if not available
     */
    suspend fun initTranslator(
        sourceLang: String = DEFAULT_SOURCE,
        targetLang: String = DEFAULT_TARGET,
        requireWifi: Boolean = true
    ): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            val sourceLanguage = SUPPORTED_LANGUAGES[sourceLang]
                ?: return@withContext Result.failure(Exception("Unsupported source language: $sourceLang"))
            val targetLanguage = SUPPORTED_LANGUAGES[targetLang]
                ?: return@withContext Result.failure(Exception("Unsupported target language: $targetLang"))
            
            // Close previous translator if exists
            currentTranslator?.close()
            
            // Create new translator
            val options = TranslatorOptions.Builder()
                .setSourceLanguage(sourceLanguage)
                .setTargetLanguage(targetLanguage)
                .build()
            
            currentTranslator = Translation.getClient(options)
            currentSourceLang = sourceLang
            currentTargetLang = targetLang
            
            Log.d(TAG, "Initializing translator: $sourceLang -> $targetLang")
            
            // Download model if needed
            val conditions = if (requireWifi) {
                DownloadConditions.Builder().requireWifi().build()
            } else {
                DownloadConditions.Builder().build()
            }
            
            suspendCancellableCoroutine { continuation ->
                currentTranslator!!.downloadModelIfNeeded(conditions)
                    .addOnSuccessListener {
                        isModelReady = true
                        Log.d(TAG, "Translation model ready: $sourceLang -> $targetLang")
                        continuation.resume(Unit)
                    }
                    .addOnFailureListener { exception ->
                        isModelReady = false
                        Log.e(TAG, "Failed to download translation model: ${exception.message}")
                        continuation.resumeWithException(exception)
                    }
            }
            
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing translator: ${e.message}")
            Result.failure(e)
        }
    }
    
    /**
     * Translate text using the initialized translator
     */
    suspend fun translate(text: String): Result<String> = withContext(Dispatchers.IO) {
        try {
            if (currentTranslator == null || !isModelReady) {
                return@withContext Result.failure(Exception("Translator not initialized. Call initTranslator first."))
            }
            
            if (text.isBlank()) {
                return@withContext Result.success("")
            }
            
            val translatedText = suspendCancellableCoroutine<String> { continuation ->
                currentTranslator!!.translate(text)
                    .addOnSuccessListener { result ->
                        Log.d(TAG, "Translation successful: ${text.take(50)}... -> ${result.take(50)}...")
                        continuation.resume(result)
                    }
                    .addOnFailureListener { exception ->
                        Log.e(TAG, "Translation failed: ${exception.message}")
                        continuation.resumeWithException(exception)
                    }
            }
            
            Result.success(translatedText)
        } catch (e: Exception) {
            Log.e(TAG, "Error translating: ${e.message}")
            Result.failure(e)
        }
    }
    
    /**
     * Get list of downloaded translation models
     */
    suspend fun getDownloadedModels(): List<String> = withContext(Dispatchers.IO) {
        try {
            suspendCancellableCoroutine { continuation ->
                modelManager.getDownloadedModels(TranslateRemoteModel::class.java)
                    .addOnSuccessListener { models ->
                        val languages = models.map { it.language }
                        Log.d(TAG, "Downloaded models: $languages")
                        continuation.resume(languages)
                    }
                    .addOnFailureListener { exception ->
                        Log.e(TAG, "Failed to get downloaded models: ${exception.message}")
                        continuation.resume(emptyList())
                    }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting downloaded models: ${e.message}")
            emptyList()
        }
    }
    
    /**
     * Download a specific language model
     */
    suspend fun downloadModel(
        languageCode: String,
        requireWifi: Boolean = true
    ): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            val language = SUPPORTED_LANGUAGES[languageCode]
                ?: return@withContext Result.failure(Exception("Unsupported language: $languageCode"))
            
            val model = TranslateRemoteModel.Builder(language).build()
            val conditions = if (requireWifi) {
                DownloadConditions.Builder().requireWifi().build()
            } else {
                DownloadConditions.Builder().build()
            }
            
            Log.d(TAG, "Downloading model for: $languageCode")
            
            suspendCancellableCoroutine { continuation ->
                modelManager.download(model, conditions)
                    .addOnSuccessListener {
                        Log.d(TAG, "Model downloaded: $languageCode")
                        continuation.resume(Unit)
                    }
                    .addOnFailureListener { exception ->
                        Log.e(TAG, "Failed to download model: ${exception.message}")
                        continuation.resumeWithException(exception)
                    }
            }
            
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "Error downloading model: ${e.message}")
            Result.failure(e)
        }
    }
    
    /**
     * Delete a specific language model
     */
    suspend fun deleteModel(languageCode: String): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            val language = SUPPORTED_LANGUAGES[languageCode]
                ?: return@withContext Result.failure(Exception("Unsupported language: $languageCode"))
            
            val model = TranslateRemoteModel.Builder(language).build()
            
            Log.d(TAG, "Deleting model for: $languageCode")
            
            suspendCancellableCoroutine { continuation ->
                modelManager.deleteDownloadedModel(model)
                    .addOnSuccessListener {
                        Log.d(TAG, "Model deleted: $languageCode")
                        continuation.resume(Unit)
                    }
                    .addOnFailureListener { exception ->
                        Log.e(TAG, "Failed to delete model: ${exception.message}")
                        continuation.resumeWithException(exception)
                    }
            }
            
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "Error deleting model: ${e.message}")
            Result.failure(e)
        }
    }
    
    /**
     * Check if translator is ready
     */
    fun isReady(): Boolean = isModelReady && currentTranslator != null
    
    /**
     * Get current source language
     */
    fun getSourceLanguage(): String = currentSourceLang
    
    /**
     * Get current target language
     */
    fun getTargetLanguage(): String = currentTargetLang
    
    /**
     * Get list of supported languages with their codes
     */
    fun getSupportedLanguages(): Map<String, String> {
        return mapOf(
            "en" to "English",
            "es" to "Spanish",
            "zh" to "Chinese",
            "fr" to "French",
            "de" to "German",
            "it" to "Italian",
            "ja" to "Japanese",
            "ko" to "Korean",
            "pt" to "Portuguese",
            "ru" to "Russian",
            "ar" to "Arabic",
            "hi" to "Hindi",
            "vi" to "Vietnamese",
            "th" to "Thai",
            "id" to "Indonesian",
            "tr" to "Turkish",
            "nl" to "Dutch",
            "pl" to "Polish"
        )
    }
    
    /**
     * Release resources
     */
    fun release() {
        currentTranslator?.close()
        currentTranslator = null
        isModelReady = false
        Log.d(TAG, "Translation resources released")
    }
}
