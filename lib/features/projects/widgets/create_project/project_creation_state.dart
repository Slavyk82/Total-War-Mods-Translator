import 'package:flutter/material.dart';
import '../../../../models/domain/detected_mod.dart';
import '../../../../models/domain/workshop_mod.dart';

/// Shared state for the project creation wizard (2-step version).
///
/// Step 1: Basic info (name, game, source file)
/// Step 2: Translation settings (batch size, parallel batches, custom prompt)
///
/// The target language is resolved automatically at creation time — see
/// `CreateProjectDialog._createProject`.
class ProjectCreationState {
  // Step 1: Basic info
  final TextEditingController nameController = TextEditingController();
  final TextEditingController modSteamIdController = TextEditingController();
  final TextEditingController sourceFileController = TextEditingController();
  final TextEditingController outputFileController = TextEditingController();
  String? selectedGameId;
  WorkshopMod? workshopMod;

  // Step 2: Settings
  final TextEditingController batchSizeController = TextEditingController(text: '25');
  final TextEditingController parallelBatchesController = TextEditingController(text: '3');
  final TextEditingController customPromptController = TextEditingController();

  final DetectedMod? detectedMod;

  ProjectCreationState({this.detectedMod}) {
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
