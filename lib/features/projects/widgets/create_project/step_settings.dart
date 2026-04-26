import 'package:flutter/material.dart';

import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/wizard/labeled_field.dart';
import 'package:twmt/widgets/wizard/token_text_field.dart';

import 'project_creation_state.dart';

/// Step 3: Translation settings.
///
/// Configures batch size, parallel batches, and custom translation prompt.
///
/// Retokenised (Plan 5d · Task 6): [TokenTextField] + [LabeledField] inputs.
class StepSettings extends StatelessWidget {
  final ProjectCreationState state;

  const StepSettings({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.projects.createProject.translationSettings.description,
          style: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.textDim,
          ),
        ),
        const SizedBox(height: 16),

        // Batch size
        LabeledField(
          label: t.projects.createProject.translationSettings.fieldBatchSize,
          child: TokenTextField(
            controller: state.batchSizeController,
            hint: t.projects.createProject.translationSettings.hintBatchSize,
            enabled: true,
          ),
        ),
        const SizedBox(height: 12),

        // Parallel batches
        LabeledField(
          label: t.projects.createProject.translationSettings.fieldParallelBatches,
          child: TokenTextField(
            controller: state.parallelBatchesController,
            hint: t.projects.createProject.translationSettings.hintParallelBatches,
            enabled: true,
          ),
        ),
        const SizedBox(height: 12),

        // Custom prompt
        LabeledField(
          label: t.projects.createProject.translationSettings.fieldCustomPrompt,
          child: TokenTextField(
            controller: state.customPromptController,
            hint: t.projects.createProject.translationSettings.hintCustomPrompt,
            enabled: true,
            maxLines: 6,
          ),
        ),
      ],
    );
  }
}
