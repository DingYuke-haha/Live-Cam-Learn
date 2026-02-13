import 'package:flutter/material.dart';

/// Bottom bar with gallery, capture button, and language selector
class BottomBar extends StatelessWidget {
  final VoidCallback onGalleryTap;
  final VoidCallback onCaptureTap;
  final Function(String) onLanguageSelected;
  final String sourceLanguage;
  final String targetLanguageCode; // Actual code like 'fr'
  final String targetLanguageDisplay; // Display code like 'FR'
  final bool isCapturing;
  final bool showSaveMode;

  const BottomBar({
    super.key,
    required this.onGalleryTap,
    required this.onCaptureTap,
    required this.onLanguageSelected,
    this.sourceLanguage = 'EN',
    required this.targetLanguageCode,
    required this.targetLanguageDisplay,
    this.isCapturing = false,
    this.showSaveMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 16, bottom: 24, left: 16, right: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFFFD54F), // Yellow
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Hint text
            if (!showSaveMode)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Tap to capture!',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (showSaveMode)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Tap to save to gallery',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            // Mascot eyes
            _buildMascotEyes(),
            const SizedBox(height: 12),

            // Controls row - Expanded on both sides keeps capture button centered
            Row(
              children: [
                // Gallery button - left side with flexible space
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildGalleryButton(),
                  ),
                ),

                // Capture button - always centered
                _buildCaptureButton(),

                // Language selector - right side with flexible space
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _buildLanguageButton(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMascotEyes() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Left eye
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black87, width: 2),
          ),
          child: Center(
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.black87,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Nose
        Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            color: Color(0xFFFF8C00),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        // Right eye
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black87, width: 2),
          ),
          child: Center(
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.black87,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGalleryButton() {
    return GestureDetector(
      onTap: onGalleryTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 110),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.grid_view_rounded, color: Colors.orange[700], size: 20),
            const SizedBox(width: 8),
            const Text(
              'Gallery',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: isCapturing ? null : onCaptureTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: showSaveMode ? Colors.green : const Color(0xFFFF5722),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: (showSaveMode ? Colors.green : const Color(0xFFFF5722))
                  .withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: isCapturing
              ? const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
              : Icon(
                  showSaveMode ? Icons.check : Icons.camera_alt,
                  color: Colors.white,
                  size: 28,
                ),
        ),
      ),
    );
  }

  Widget _buildLanguageButton() {
    return PopupMenuButton<String>(
      onSelected: onLanguageSelected,
      offset: const Offset(0, -10),
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      elevation: 8,
      itemBuilder: (context) => LanguageSelector.supportedLanguages.entries
          .map(
            (entry) => PopupMenuItem<String>(
              value: entry.key,
              height: 44,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: entry.key == targetLanguageCode
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  if (entry.key == targetLanguageCode)
                    const Icon(Icons.check, color: Color(0xFFFF8C00), size: 18),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        constraints: const BoxConstraints(minWidth: 110),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              targetLanguageDisplay,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.translate, color: Colors.orange[700], size: 20),
          ],
        ),
      ),
    );
  }
}

/// Language selection - supported languages map
class LanguageSelector {
  static const Map<String, String> supportedLanguages = {
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'ja': 'Japanese',
    'ko': 'Korean',
    'hi': 'Hindi',
    'zh': 'Chinese',
    'it': 'Italian',
    'pt': 'Portuguese',
  };
}
