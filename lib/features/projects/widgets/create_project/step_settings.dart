import 'package:flutter/material.dart';

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
          'Tune translation throughput and optionally provide an extra prompt.',
          style: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.textDim,
          ),
        ),
        const SizedBox(height: 16),

        // Batch size
        LabeledField(
          label: 'BATCH SIZE',
          child: TokenTextField(
            controller: state.batchSizeController,
            hint: 'Number of units per batch (default: 25)',
            enabled: true,
          ),
        ),
        const SizedBox(height: 12),

        // Parallel batches
        LabeledField(
          label: 'PARALLEL BATCHES',
          child: TokenTextField(
            controller: state.parallelBatchesController,
            hint: 'Number of batches to process in parallel (default: 3)',
            enabled: true,
          ),
        ),
        const SizedBox(height: 12),

        // Custom prompt
        LabeledField(
          label: 'CUSTOM TRANSLATION PROMPT (OPTIONAL)',
          child: TokenTextField(
            controller: state.customPromptController,
            hint: 'Enter custom instructions for the AI translator',
            enabled: true,
            maxLines: 6,
          ),
        ),
      ],
    );
  }
}
