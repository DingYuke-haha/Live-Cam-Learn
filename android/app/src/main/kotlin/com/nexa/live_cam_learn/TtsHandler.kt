package com.nexa.live_cam_learn

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.util.Locale
import java.util.UUID

/**
 * Handler for Android Text-to-Speech functionality
 */
class TtsHandler(private val context: Context) {
    
    companion object {
        private const val TAG = "TtsHandler"
    }
    
    private var tts: TextToSpeech? = null
    private var isInitialized = false
    private var currentLocale: Locale = Locale.US
    
    // Callbacks
    var onInitComplete: ((Boolean) -> Unit)? = null
    var onSpeakStart: ((String) -> Unit)? = null
    var onSpeakDone: ((String) -> Unit)? = null
    var onSpeakError: ((String, String) -> Unit)? = null
    
    /**
     * Initialize the TTS engine
     */
    fun initialize(callback: (Boolean) -> Unit) {
        if (isInitialized && tts != null) {
            callback(true)
            return
        }
        
        tts = TextToSpeech(context) { status ->
            isInitialized = status == TextToSpeech.SUCCESS
            Log.d(TAG, "TTS initialization: ${if (isInitialized) "SUCCESS" else "FAILED"}")
            
            if (isInitialized) {
                setupUtteranceListener()
            }
            
            callback(isInitialized)
            onInitComplete?.invoke(isInitialized)
        }
    }
    
    private fun setupUtteranceListener() {
        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                Log.d(TAG, "Speech started: $utteranceId")
                utteranceId?.let { onSpeakStart?.invoke(it) }
            }
            
            override fun onDone(utteranceId: String?) {
                Log.d(TAG, "Speech done: $utteranceId, onSpeakDone callback is ${if (onSpeakDone != null) "set" else "null"}")
                utteranceId?.let { 
                    Log.d(TAG, "Invoking onSpeakDone callback with utteranceId=$it")
                    onSpeakDone?.invoke(it) 
                }
            }
            
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {
                Log.e(TAG, "Speech error: $utteranceId")
                utteranceId?.let { onSpeakError?.invoke(it, "Unknown error") }
            }
            
            override fun onError(utteranceId: String?, errorCode: Int) {
                val errorMessage = when (errorCode) {
                    TextToSpeech.ERROR_SYNTHESIS -> "Synthesis error"
                    TextToSpeech.ERROR_SERVICE -> "Service error"
                    TextToSpeech.ERROR_OUTPUT -> "Output error"
                    TextToSpeech.ERROR_NETWORK -> "Network error"
                    TextToSpeech.ERROR_NETWORK_TIMEOUT -> "Network timeout"
                    TextToSpeech.ERROR_INVALID_REQUEST -> "Invalid request"
                    TextToSpeech.ERROR_NOT_INSTALLED_YET -> "Language not installed"
                    else -> "Unknown error ($errorCode)"
                }
                Log.e(TAG, "Speech error: $utteranceId - $errorMessage")
                utteranceId?.let { onSpeakError?.invoke(it, errorMessage) }
            }
        })
    }
    
    /**
     * Check if TTS is ready
     */
    fun isReady(): Boolean = isInitialized && tts != null
    
    /**
     * Set the language for TTS
     * @param languageCode The language code (e.g., "es", "fr", "de", "ja", "ko", "zh", "hi", "it", "pt")
     * @return true if the language is supported and set successfully
     */
    fun setLanguage(languageCode: String): Boolean {
        if (!isInitialized || tts == null) {
            Log.e(TAG, "TTS not initialized")
            return false
        }
        
        val locale = getLocaleForLanguageCode(languageCode)
        val result = tts?.setLanguage(locale) ?: TextToSpeech.LANG_NOT_SUPPORTED
        
        return when (result) {
            TextToSpeech.LANG_AVAILABLE,
            TextToSpeech.LANG_COUNTRY_AVAILABLE,
            TextToSpeech.LANG_COUNTRY_VAR_AVAILABLE -> {
                currentLocale = locale
                Log.d(TAG, "Language set to: $locale")
                true
            }
            TextToSpeech.LANG_MISSING_DATA -> {
                Log.w(TAG, "Language data missing for: $locale")
                false
            }
            TextToSpeech.LANG_NOT_SUPPORTED -> {
                Log.w(TAG, "Language not supported: $locale")
                false
            }
            else -> {
                Log.w(TAG, "Unknown language result: $result for $locale")
                false
            }
        }
    }
    
    private fun getLocaleForLanguageCode(code: String): Locale {
        return when (code.lowercase()) {
            "es" -> Locale("es", "ES")
            "fr" -> Locale.FRANCE
            "de" -> Locale.GERMANY
            "ja" -> Locale.JAPAN
            "ko" -> Locale.KOREA
            "zh" -> Locale.SIMPLIFIED_CHINESE
            "hi" -> Locale("hi", "IN")
            "it" -> Locale.ITALY
            "pt" -> Locale("pt", "BR")
            "en" -> Locale.US
            else -> Locale(code)
        }
    }
    
    /**
     * Speak the given text
     * @param text The text to speak
     * @param languageCode Optional language code to set before speaking
     * @return The utterance ID
     */
    fun speak(text: String, languageCode: String? = null): String? {
        if (!isInitialized || tts == null) {
            Log.e(TAG, "TTS not initialized")
            return null
        }
        
        // Set language if provided
        languageCode?.let { setLanguage(it) }
        
        val utteranceId = UUID.randomUUID().toString()
        val result = tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)
        
        return if (result == TextToSpeech.SUCCESS) {
            Log.d(TAG, "Speaking: $text (utteranceId: $utteranceId)")
            utteranceId
        } else {
            Log.e(TAG, "Failed to speak: $text")
            null
        }
    }
    
    /**
     * Stop any ongoing speech
     */
    fun stop() {
        tts?.stop()
        Log.d(TAG, "Speech stopped")
    }
    
    /**
     * Check if TTS is currently speaking
     */
    fun isSpeaking(): Boolean = tts?.isSpeaking == true
    
    /**
     * Get list of available languages
     */
    fun getAvailableLanguages(): List<String> {
        if (!isInitialized || tts == null) return emptyList()
        
        return tts?.availableLanguages?.map { it.language }?.distinct() ?: emptyList()
    }
    
    /**
     * Check if a specific language is available
     */
    fun isLanguageAvailable(languageCode: String): Boolean {
        if (!isInitialized || tts == null) return false
        
        val locale = getLocaleForLanguageCode(languageCode)
        val result = tts?.isLanguageAvailable(locale) ?: TextToSpeech.LANG_NOT_SUPPORTED
        
        return result >= TextToSpeech.LANG_AVAILABLE
    }
    
    /**
     * Set speech rate
     * @param rate Speech rate (1.0 is normal, 0.5 is half speed, 2.0 is double speed)
     */
    fun setSpeechRate(rate: Float) {
        tts?.setSpeechRate(rate.coerceIn(0.1f, 3.0f))
    }
    
    /**
     * Set speech pitch
     * @param pitch Speech pitch (1.0 is normal)
     */
    fun setPitch(pitch: Float) {
        tts?.setPitch(pitch.coerceIn(0.1f, 2.0f))
    }
    
    /**
     * Release TTS resources
     */
    fun release() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        isInitialized = false
        Log.d(TAG, "TTS released")
    }
}
