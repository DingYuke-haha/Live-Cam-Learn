import 'package:flutter/material.dart';

/// Result card overlay showing the VLM description and translation
class ResultCard extends StatelessWidget {
  final String translatedText;
  final String englishText;
  final String targetLanguage;
  final VoidCallback? onSpeakerTap;
  final bool isLoading;

  const ResultCard({
    super.key,
    required this.translatedText,
    required this.englishText,
    required this.targetLanguage,
    this.onSpeakerTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Translated text (large)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: isLoading
                    ? _buildLoadingPlaceholder()
                    : Text(
                        translatedText,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                          height: 1.3,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              // Speaker button
              GestureDetector(
                onTap: onSpeakerTap,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8C00),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.volume_up,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // English text (smaller, grey)
          Text(
            englishText,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingPlaceholder() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 24,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 24,
          width: 200,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

/// Streaming result card that shows text as it's being generated
class StreamingResultCard extends StatelessWidget {
  final String streamingText;
  final String? translatedText;
  final String targetLanguage;
  final bool isSegmenting;
  final bool isProcessing;
  final bool isTranslating;
  final bool isObjectMode;
  final bool isSpeaking;
  final VoidCallback? onSpeakerTap;
  final double? maxHeight;

  const StreamingResultCard({
    super.key,
    required this.streamingText,
    this.translatedText,
    required this.targetLanguage,
    this.isSegmenting = false,
    this.isProcessing = false,
    this.isTranslating = false,
    this.isObjectMode = false,
    this.isSpeaking = false,
    this.onSpeakerTap,
    this.maxHeight,
  });

  String _getStatusText() {
    if (isSegmenting) return 'Segmenting object...';
    if (isTranslating) return 'Translating...';
    if (isProcessing) {
      return isObjectMode ? 'Identifying object...' : 'Analyzing scene...';
    }
    return '';
  }

  String _getPlaceholderText() {
    if (isSegmenting) return 'Segmenting...';
    return isObjectMode ? 'Identifying...' : 'Analyzing...';
  }

  @override
  Widget build(BuildContext context) {
    final showTranslation =
        translatedText != null && translatedText!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      constraints: BoxConstraints(
        maxHeight: maxHeight ?? MediaQuery.of(context).size.height * 0.5,
      ),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Main text (translated if available, otherwise streaming English)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: showTranslation
                        ? Text(
                            translatedText!,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                              height: 1.3,
                            ),
                          )
                        : Text(
                            streamingText.isEmpty
                                ? _getPlaceholderText()
                                : streamingText,
                            style: TextStyle(
                              fontSize: showTranslation ? 22 : 18,
                              fontWeight: showTranslation
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: showTranslation
                                  ? Colors.black87
                                  : Colors.grey[700],
                              height: 1.3,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  // Speaker button (only when translation is ready)
                  if (showTranslation)
                    GestureDetector(
                      onTap: onSpeakerTap,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSpeaking
                              ? const Color(0xFFFF5722) // Orange when speaking
                              : const Color(0xFFFF8C00),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isSpeaking ? Icons.stop : Icons.volume_up,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                ],
              ),

              // Status indicator
              if (isSegmenting || isProcessing || isTranslating) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.orange[400],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _getStatusText(),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ],

              // English text (shown below when translation is available)
              if (showTranslation && streamingText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  streamingText,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
