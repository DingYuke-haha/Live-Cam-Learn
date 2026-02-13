import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';
import '../models/learn_card.dart';

/// Gallery page showing saved learning cards in a grid
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  final StorageService _storageService = StorageService.instance;
  final TtsService _ttsService = TtsService.instance;
  bool _isSpeaking = false;
  String? _speakingCardId;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await _ttsService.initialize();
    _setupMainTtsCallbacks();
  }

  Future<void> _speakText(
    LearnCard card, {
    void Function(void Function())? dialogSetState,
  }) async {
    // If already speaking the same card, stop
    if (_isSpeaking && _speakingCardId == card.id) {
      await _ttsService.stop();
      setState(() {
        _isSpeaking = false;
        _speakingCardId = null;
      });
      dialogSetState?.call(() {});
      return;
    }

    // Stop any current speech
    if (_isSpeaking) {
      await _ttsService.stop();
    }

    // Re-setup callbacks before speaking (with optional dialog state updater)
    _setupMainTtsCallbacks(dialogSetState: dialogSetState);

    setState(() {
      _isSpeaking = true;
      _speakingCardId = card.id;
    });
    dialogSetState?.call(() {});

    // Speak the translated text in the target language
    final success = await _ttsService.speak(
      card.translatedText,
      languageCode: card.targetLanguage,
    );

    if (!success && mounted) {
      setState(() {
        _isSpeaking = false;
        _speakingCardId = null;
      });
      dialogSetState?.call(() {});
    }
  }

  void _setupMainTtsCallbacks({
    void Function(void Function())? dialogSetState,
  }) {
    _ttsService.onDone = () {
      debugPrint('GalleryPage: TTS onDone callback fired');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _speakingCardId = null;
        });
        // Try to update dialog state if provided
        try {
          dialogSetState?.call(() {});
        } catch (e) {
          // Dialog may have been closed
        }
      }
    };
    _ttsService.onError = (error) {
      debugPrint('GalleryPage: TTS onError callback fired: $error');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _speakingCardId = null;
        });
        try {
          dialogSetState?.call(() {});
        } catch (e) {
          // Dialog may have been closed
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('TTS Error: $error')));
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    final cards = _storageService.cards;

    return Scaffold(
      backgroundColor: const Color(0xFFFFD54F),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFD54F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          cards.isEmpty ? 'Gallery' : 'Gallery (${cards.length})',
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (cards.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.black87),
              onPressed: _showClearAllDialog,
              tooltip: 'Clear all',
            ),
        ],
      ),
      body: cards.isEmpty ? _buildEmptyState() : _buildCardGrid(cards),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 64, color: Colors.black38),
          SizedBox(height: 16),
          Text(
            'No cards yet',
            style: TextStyle(
              fontSize: 18,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Capture images to start learning!',
            style: TextStyle(fontSize: 14, color: Colors.black38),
          ),
        ],
      ),
    );
  }

  Widget _buildCardGrid(List<LearnCard> cards) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        return _buildCardItem(cards[index]);
      },
    );
  }

  Widget _buildCardItem(LearnCard card) {
    final imageFile = File(card.imagePath);
    final imageExists = imageFile.existsSync();

    return GestureDetector(
      onTap: () => _showCardDetail(card),
      onLongPress: () => _showDeleteDialog(card),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image
              if (imageExists)
                Image.file(imageFile, fit: BoxFit.cover)
              else
                Container(
                  color: Colors.grey[300],
                  child: const Icon(
                    Icons.broken_image,
                    size: 48,
                    color: Colors.grey,
                  ),
                ),

              // Gradient overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Translated text
                      Text(
                        card.translatedText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // English text
                      Text(
                        card.englishText,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),

              // Speaker button
              Positioned(
                bottom: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => _speakText(card),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _isSpeaking && _speakingCardId == card.id
                          ? const Color(0xFFFF5722) // Orange when speaking
                          : const Color(0xFF00BCD4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _isSpeaking && _speakingCardId == card.id
                          ? Icons.stop
                          : Icons.volume_up,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),

              // Language badge
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    card.targetLanguage.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCardDetail(LearnCard card) {
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Check if this card is currently speaking
          final bool isThisCardSpeaking =
              _isSpeaking && _speakingCardId == card.id;

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 40,
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Image - tap to view full screen
                  GestureDetector(
                    onTap: () => _showFullScreenImage(card.imagePath),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      child: SizedBox(
                        height: 300,
                        width: double.infinity,
                        child: File(card.imagePath).existsSync()
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    File(card.imagePath),
                                    fit: BoxFit.cover,
                                  ),
                                  // Tap hint overlay
                                  Positioned(
                                    bottom: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.fullscreen,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Tap to expand',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Container(
                                color: Colors.grey[300],
                                child: const Icon(Icons.broken_image, size: 64),
                              ),
                      ),
                    ),
                  ),

                  // Scrollable Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Translated text
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  card.translatedText,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () => _speakText(
                                  card,
                                  dialogSetState: setDialogState,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isThisCardSpeaking
                                        ? const Color(0xFFFF5722)
                                        : const Color(0xFFFF8C00),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    isThisCardSpeaking
                                        ? Icons.stop
                                        : Icons.volume_up,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // English text
                          Text(
                            card.englishText,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Language and date
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFD54F),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  card.languageDisplayName,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                _formatDate(card.createdAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Actions - fixed at bottom
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 20,
                      right: 20,
                      bottom: 20,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _showDeleteDialog(card);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                            ),
                            child: const Text('Delete'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFD54F),
                              foregroundColor: Colors.black87,
                            ),
                            child: const Text('Close'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showFullScreenImage(String imagePath) {
    final imageFile = File(imagePath);
    if (!imageFile.existsSync()) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(imageFile, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(LearnCard card) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Card'),
        content: const Text('Are you sure you want to delete this card?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _storageService.deleteCard(card.id);
              setState(() {});
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Cards'),
        content: const Text(
          'Are you sure you want to delete all cards? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _storageService.clearAll();
              setState(() {});
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }
}
