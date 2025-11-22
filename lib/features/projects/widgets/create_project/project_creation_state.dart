import 'package:flutter/material.dart';
import '../../../../models/domain/detected_mod.dart';
import '../../../../models/domain/workshop_mod.dart';

/// Shared state for the project creation wizard.
///
/// Manages all form fields and state across the 3-step wizard:
/// 1. Basic info (name, game, source file)
/// 2. Target languages selection
/// 3. Translation settings
class ProjectCreationState {
  // Step 1: Basic info
  final TextEditingController nameController = TextEditingController();
  final TextEditingController modSteamIdController = TextEditingController();
  final TextEditingController sourceFileController = TextEditingController();
  final TextEditingController outputFileController = TextEditingController();
  String? selectedGameId;
  WorkshopMod? workshopMod;

  // Step 2: Languages
  final Set<String> selectedLanguageIds = {};

  // Step 3: Settings
  final TextEditingController batchSizeController = TextEditingController(text: '25');
  final TextEditingController parallelBatchesController = TextEditingController(text: '3');
  final TextEditingController customPromptController = TextEditingController();

  // Detected mod context (if provided)
  final DetectedMod? detectedMod;

  ProjectCreationState({this.detectedMod}) {
    // Pre-fill fields if a mod is provided
    if (detectedMod != null) {
      nameController.text = detectedMod!.name;
      sourceFileController.text = detectedMod!.packFilePath;
      modSteamIdController.text = detectedMod!.workshopId;
    }
  }

  void dispose() {
    nameController.dispose();
    modSteamIdController.dispose();
    sourceFileController.dispose();
    outputFileController.dispose();
    batchSizeController.dispose();
    parallelBatchesController.dispose();
    customPromptController.dispose();
  }
}
