import 'package:flutter/material.dart';
import '../../../../widgets/fluent/fluent_widgets.dart';
import 'project_creation_state.dart';

/// Step 3: Translation settings.
///
/// Configures batch size, parallel batches, and custom translation prompt.
class StepSettings extends StatelessWidget {
  final ProjectCreationState state;

  const StepSettings({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Batch size
        Text(
          'Batch Size',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        FluentTextField(
          controller: state.batchSizeController,
          decoration: InputDecoration(
            hintText: 'Number of units per batch (default: 25)',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),

        // Parallel batches
        Text(
          'Parallel Batches',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        FluentTextField(
          controller: state.parallelBatchesController,
          decoration: InputDecoration(
            hintText: 'Number of batches to process in parallel (default: 3)',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),

        // Custom prompt
        Text(
          'Custom Translation Prompt (Optional)',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        FluentTextField(
          controller: state.customPromptController,
          decoration: InputDecoration(
            hintText: 'Enter custom instructions for the AI translator',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          maxLines: 4,
        ),
      ],
    );
  }
}
