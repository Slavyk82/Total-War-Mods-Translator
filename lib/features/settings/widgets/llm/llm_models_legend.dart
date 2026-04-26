import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Informational "legend" box shown at the top of the
/// [ModelManagementDialog].
///
/// Renders an info icon plus an explanatory line describing how the checkbox
/// and star-default controls work. All colours come from [context.tokens].
class LlmModelsLegend extends StatelessWidget {
  const LlmModelsLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.panel2,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.info_24_regular,
            size: 16,
            color: tokens.accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.settings.llmProviders.models.legend,
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
