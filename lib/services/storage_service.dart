import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/learn_card.dart';

/// Service for persisting LearnCards to local storage
class StorageService {
  static const String _cardsFileName = 'learn_cards.json';
  static const String _imagesFolder = 'card_images';

  static StorageService? _instance;
  List<LearnCard> _cards = [];
  bool _isLoaded = false;

  StorageService._();

  /// Get singleton instance
  static StorageService get instance {
    _instance ??= StorageService._();
    return _instance!;
  }

  /// Get all saved cards (most recent first)
  List<LearnCard> get cards => List.unmodifiable(_cards);

  /// Check if cards have been loaded
  bool get isLoaded => _isLoaded;

  /// Get the app's documents directory
  Future<Directory> _getAppDir() async {
    return await getApplicationDocumentsDirectory();
  }

  /// Get the cards JSON file
  Future<File> _getCardsFile() async {
    final appDir = await _getAppDir();
    return File('${appDir.path}/$_cardsFileName');
  }

  /// Get the images directory
  Future<Directory> _getImagesDir() async {
    final appDir = await _getAppDir();
    final imagesDir = Directory('${appDir.path}/$_imagesFolder');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  /// Load cards from storage
  Future<void> loadCards() async {
    try {
      final file = await _getCardsFile();
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final List<dynamic> jsonList = json.decode(jsonString);
        _cards = jsonList
            .map((json) => LearnCard.fromJson(json as Map<String, dynamic>))
            .toList();
        // Sort by createdAt descending (newest first)
        _cards.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
      _isLoaded = true;
    } catch (e) {
      print('Error loading cards: $e');
      _cards = [];
      _isLoaded = true;
    }
  }

  /// Save cards to storage
  Future<void> _saveCards() async {
    try {
      final file = await _getCardsFile();
      final jsonList = _cards.map((card) => card.toJson()).toList();
      await file.writeAsString(json.encode(jsonList));
    } catch (e) {
      print('Error saving cards: $e');
    }
  }

  /// Copy image to app storage and return new path
  Future<String> saveImage(String sourcePath) async {
    try {
      final imagesDir = await _getImagesDir();
      final sourceFile = File(sourcePath);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = sourcePath.split('.').last;
      final newPath = '${imagesDir.path}/card_$timestamp.$extension';
      await sourceFile.copy(newPath);
      return newPath;
    } catch (e) {
      print('Error saving image: $e');
      return sourcePath; // Return original path if copy fails
    }
  }

  /// Add a new card
  Future<void> addCard(LearnCard card) async {
    _cards.insert(0, card); // Add to beginning (newest first)
    await _saveCards();
  }

  /// Delete a card by ID
  Future<void> deleteCard(String cardId) async {
    final cardIndex = _cards.indexWhere((c) => c.id == cardId);
    if (cardIndex >= 0) {
      final card = _cards[cardIndex];

      // Delete the image file
      try {
        final imageFile = File(card.imagePath);
        if (await imageFile.exists()) {
          await imageFile.delete();
        }
      } catch (e) {
        print('Error deleting image: $e');
      }

      _cards.removeAt(cardIndex);
      await _saveCards();
    }
  }

  /// Get a card by ID
  LearnCard? getCard(String cardId) {
    try {
      return _cards.firstWhere((c) => c.id == cardId);
    } catch (e) {
      return null;
    }
  }

  /// Clear all cards
  Future<void> clearAll() async {
    // Delete all image files
    for (final card in _cards) {
      try {
        final imageFile = File(card.imagePath);
        if (await imageFile.exists()) {
          await imageFile.delete();
        }
      } catch (e) {
        print('Error deleting image: $e');
      }
    }
    _cards.clear();
    await _saveCards();
  }

  /// Get card count
  int get cardCount => _cards.length;
}
