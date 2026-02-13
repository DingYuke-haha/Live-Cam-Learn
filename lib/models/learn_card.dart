import 'dart:convert';

/// Data model for a saved learning card
class LearnCard {
  final String id;
  final String imagePath;
  final String englishText;
  final String translatedText;
  final String targetLanguage;
  final DateTime createdAt;

  LearnCard({
    required this.id,
    required this.imagePath,
    required this.englishText,
    required this.translatedText,
    required this.targetLanguage,
    required this.createdAt,
  });

  /// Create a new card with auto-generated ID
  factory LearnCard.create({
    required String imagePath,
    required String englishText,
    required String translatedText,
    required String targetLanguage,
  }) {
    return LearnCard(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      imagePath: imagePath,
      englishText: englishText,
      translatedText: translatedText,
      targetLanguage: targetLanguage,
      createdAt: DateTime.now(),
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imagePath': imagePath,
      'englishText': englishText,
      'translatedText': translatedText,
      'targetLanguage': targetLanguage,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Create from JSON map
  factory LearnCard.fromJson(Map<String, dynamic> json) {
    return LearnCard(
      id: json['id'] as String,
      imagePath: json['imagePath'] as String,
      englishText: json['englishText'] as String,
      translatedText: json['translatedText'] as String,
      targetLanguage: json['targetLanguage'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// Get language display name
  String get languageDisplayName {
    const languageNames = {
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
    return languageNames[targetLanguage] ?? targetLanguage.toUpperCase();
  }

  @override
  String toString() {
    return 'LearnCard(id: $id, lang: $targetLanguage, english: ${englishText.substring(0, englishText.length.clamp(0, 30))}...)';
  }
}
