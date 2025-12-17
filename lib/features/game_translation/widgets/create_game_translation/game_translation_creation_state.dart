import 'package:flutter/material.dart';

import '../../../../services/game/game_localization_service.dart';

/// State management for the game translation creation wizard.
class GameTranslationCreationState {
  /// Selected game installation ID
  String? selectedGameId;

  /// Selected source pack
  DetectedLocalPack? selectedSourcePack;

  /// Selected target language IDs
  final Set<String> selectedLanguageIds = {};

  /// Controller for batch size
  final TextEditingController batchSizeController =
      TextEditingController(text: '25');

  /// Controller for parallel batches
  final TextEditingController parallelBatchesController =
      TextEditingController(text: '3');

  /// Controller for custom prompt
  final TextEditingController customPromptController = TextEditingController();

  /// Dispose all controllers
  void dispose() {
    batchSizeController.dispose();
    parallelBatchesController.dispose();
    customPromptController.dispose();
  }

  /// Toggle a target language selection
  void toggleLanguage(String languageId) {
    if (selectedLanguageIds.contains(languageId)) {
      selectedLanguageIds.remove(languageId);
    } else {
      selectedLanguageIds.add(languageId);
    }
  }

  /// Check if a language is selected
  bool isLanguageSelected(String languageId) {
    return selectedLanguageIds.contains(languageId);
  }

  /// Clear all selected languages
  void clearLanguages() {
    selectedLanguageIds.clear();
  }
}
