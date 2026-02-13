package com.nexa.live_cam_learn

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenter
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentationResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Handler for ML Kit Subject Segmentation
 * Segments the main subject/object from an image
 */
class SegmentationHandler(private val context: Context) {
    
    companion object {
        private const val TAG = "SegmentationHandler"
    }
    
    private var segmenter: SubjectSegmenter? = null
    private var isInitialized = false
    
    /**
     * Initialize the subject segmenter
     */
    fun initialize(): Boolean {
        return try {
            val options = SubjectSegmenterOptions.Builder()
                .enableForegroundBitmap()  // Get the segmented foreground as bitmap
                .enableForegroundConfidenceMask()  // Get confidence mask for better processing
                .build()
            
            segmenter = SubjectSegmentation.getClient(options)
            isInitialized = true
            Log.d(TAG, "Subject segmenter initialized successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize segmenter: ${e.message}")
            isInitialized = false
            false
        }
    }
    
    /**
     * Check if segmenter is ready
     */
    fun isReady(): Boolean = isInitialized && segmenter != null
    
    /**
     * Warm up the segmenter by running a dummy inference
     * This triggers the ML Kit model download if not already downloaded
     */
    suspend fun warmup(): Boolean {
        if (!isReady()) {
            val initSuccess = initialize()
            if (!initSuccess) {
                return false
            }
        }
        
        return withContext(Dispatchers.IO) {
            try {
                // Create a small dummy bitmap for warmup
                val dummyBitmap = Bitmap.createBitmap(100, 100, Bitmap.Config.ARGB_8888)
                val inputImage = InputImage.fromBitmap(dummyBitmap, 0)
                
                Log.d(TAG, "Starting segmenter warmup (triggers model download)...")
                
                // Process with segmenter - this will trigger the model download
                val result = processWithSegmenter(inputImage)
                
                dummyBitmap.recycle()
                
                Log.d(TAG, "Segmenter warmup complete, model is ready")
                true
            } catch (e: Exception) {
                Log.e(TAG, "Segmenter warmup failed: ${e.message}", e)
                false
            }
        }
    }
    
    /**
     * Segment the main subject from an image
     * @param imagePath Path to the input image
     * @param outputPath Path to save the segmented image
     * @return Result containing success status and any error message
     */
    suspend fun segmentImage(imagePath: String, outputPath: String): SegmentationResult {
        if (!isReady()) {
            val initSuccess = initialize()
            if (!initSuccess) {
                return SegmentationResult(
                    success = false,
                    error = "Segmenter not initialized"
                )
            }
        }
        
        return withContext(Dispatchers.IO) {
            try {
                // Load the image
                var bitmap = BitmapFactory.decodeFile(imagePath)
                    ?: return@withContext SegmentationResult(
                        success = false,
                        error = "Failed to load image from $imagePath"
                    )
                
                Log.d(TAG, "Loaded image: ${bitmap.width}x${bitmap.height}")
                
                // Get EXIF rotation and apply it
                val rotation = getExifRotation(imagePath)
                if (rotation != 0) {
                    Log.d(TAG, "Applying EXIF rotation: $rotation degrees")
                    val rotatedBitmap = rotateBitmap(bitmap, rotation)
                    bitmap.recycle()
                    bitmap = rotatedBitmap
                    Log.d(TAG, "After rotation: ${bitmap.width}x${bitmap.height}")
                }
                
                // Create InputImage for ML Kit (rotation already applied)
                val inputImage = InputImage.fromBitmap(bitmap, 0)
                
                // Process with segmenter
                val result = processWithSegmenter(inputImage)
                
                // Get foreground bitmap (segmented subject)
                val foregroundBitmap = result.foregroundBitmap
                if (foregroundBitmap == null) {
                    bitmap.recycle()
                    return@withContext SegmentationResult(
                        success = false,
                        error = "No foreground subject detected"
                    )
                }
                
                Log.d(TAG, "Segmentation successful: ${foregroundBitmap.width}x${foregroundBitmap.height}")
                
                // Crop to the subject bounds to remove transparent areas
                val croppedBitmap = cropToSubject(foregroundBitmap)
                
                // Save the segmented image
                val outputFile = File(outputPath)
                FileOutputStream(outputFile).use { out ->
                    croppedBitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                }
                
                Log.d(TAG, "Saved segmented image to: $outputPath")
                
                // Clean up
                if (croppedBitmap != foregroundBitmap) {
                    croppedBitmap.recycle()
                }
                foregroundBitmap.recycle()
                bitmap.recycle()
                
                SegmentationResult(
                    success = true,
                    outputPath = outputPath
                )
            } catch (e: Exception) {
                Log.e(TAG, "Segmentation failed: ${e.message}", e)
                SegmentationResult(
                    success = false,
                    error = e.message ?: "Unknown segmentation error"
                )
            }
        }
    }
    
    /**
     * Get EXIF rotation from image file
     */
    private fun getExifRotation(imagePath: String): Int {
        return try {
            val exif = ExifInterface(imagePath)
            when (exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90
                ExifInterface.ORIENTATION_ROTATE_180 -> 180
                ExifInterface.ORIENTATION_ROTATE_270 -> 270
                else -> 0
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read EXIF: ${e.message}")
            0
        }
    }
    
    /**
     * Rotate a bitmap by the given degrees
     */
    private fun rotateBitmap(bitmap: Bitmap, degrees: Int): Bitmap {
        val matrix = Matrix().apply {
            postRotate(degrees.toFloat())
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }
    
    /**
     * Process image with ML Kit segmenter using coroutines
     */
    private suspend fun processWithSegmenter(image: InputImage): SubjectSegmentationResult {
        return suspendCancellableCoroutine { continuation ->
            segmenter?.process(image)
                ?.addOnSuccessListener { result ->
                    continuation.resume(result)
                }
                ?.addOnFailureListener { e ->
                    continuation.resumeWithException(e)
                }
                ?: continuation.resumeWithException(IllegalStateException("Segmenter is null"))
        }
    }
    
    /**
     * Crop bitmap to remove transparent areas around the subject
     */
    private fun cropToSubject(bitmap: Bitmap): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        
        // Find bounding box of non-transparent pixels
        for (y in 0 until height) {
            for (x in 0 until width) {
                val pixel = bitmap.getPixel(x, y)
                val alpha = (pixel shr 24) and 0xFF
                if (alpha > 10) {  // Threshold for non-transparent
                    minX = minOf(minX, x)
                    minY = minOf(minY, y)
                    maxX = maxOf(maxX, x)
                    maxY = maxOf(maxY, y)
                }
            }
        }
        
        // If no subject found, return original
        if (minX >= maxX || minY >= maxY) {
            Log.w(TAG, "No subject bounds found, returning original")
            return bitmap
        }
        
        // Add some padding
        val padding = 20
        minX = maxOf(0, minX - padding)
        minY = maxOf(0, minY - padding)
        maxX = minOf(width - 1, maxX + padding)
        maxY = minOf(height - 1, maxY + padding)
        
        val cropWidth = maxX - minX
        val cropHeight = maxY - minY
        
        Log.d(TAG, "Cropping to bounds: ($minX, $minY) - ($maxX, $maxY), size: ${cropWidth}x${cropHeight}")
        
        return Bitmap.createBitmap(bitmap, minX, minY, cropWidth, cropHeight)
    }
    
    /**
     * Release resources
     */
    fun release() {
        try {
            segmenter?.close()
            segmenter = null
            isInitialized = false
            Log.d(TAG, "Segmenter released")
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing segmenter: ${e.message}")
        }
    }
}

/**
 * Result of segmentation operation
 */
data class SegmentationResult(
    val success: Boolean,
    val outputPath: String? = null,
    val error: String? = null
)
