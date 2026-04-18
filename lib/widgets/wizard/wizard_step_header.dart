import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Step counter + title used at the top of wizard dialogs (Plan 5d §7.5).
///
/// Renders "STEP N/total" in mono caps above a display-font title, with a
/// 1px bottom border. Shared between Game Translation (2 steps) and
/// New Project (3 steps) dialogs.
class WizardStepHeader extends StatelessWidget {
  final int stepNumber;
  final int totalSteps;
  final String title;

  const WizardStepHeader({
    super.key,
    required this.stepNumber,
    required this.totalSteps,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STEP $stepNumber/$totalSteps',
            style: tokens.fontMono.copyWith(
              fontSize: 10,
              color: tokens.textDim,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: tokens.fontDisplay.copyWith(
              fontSize: 18,
              color: tokens.text,
              fontStyle: tokens.fontDisplayStyle,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
