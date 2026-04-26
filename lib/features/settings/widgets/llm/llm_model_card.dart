import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../../../../models/domain/llm_provider_model.dart';
import '../../../../widgets/common/fluent_spinner.dart';

/// Rounded-border card rendering a single model row inside the
/// [ModelManagementDialog].
///
/// Distinct from [LlmModelRow] (which renders a flat, gap-less row inside a
/// shared container): each card has its own border, margin, and supports the
/// archived state (icon placeholder, faint text, "Archived" badge). All
/// colours come from [context.tokens]; interactions are delegated to the
/// parent through [onToggleEnabled] and [onSetAsDefault] so the card itself
/// is stateless.
class LlmModelCard extends StatelessWidget {
  /// Model to display.
  final LlmProviderModel model;

  /// Whether the dialog is currently processing a mutation for this model
  /// (shows a spinner instead of the checkbox).
  final bool isProcessingThis;

  /// Whether any mutation is currently in flight (disables interactions).
  final bool isProcessing;

  /// Invoked when the user taps the checkbox on a non-archived, non-busy row.
  final VoidCallback? onToggleEnabled;

  /// Invoked when the user taps the star on a non-default, non-archived,
  /// non-busy row.
  final VoidCallback? onSetAsDefault;

  const LlmModelCard({
    super.key,
    required this.model,
    required this.isProcessingThis,
    required this.isProcessing,
    this.onToggleEnabled,
    this.onSetAsDefault,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final canInteract = !isProcessing && !model.isArchived;

    return MouseRegion(
      cursor: canInteract ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: model.isEnabled && !model.isArchived
              ? tokens.accentBg
              : tokens.panel2,
          border: Border.all(
            color: model.isEnabled && !model.isArchived
                ? tokens.accent.withValues(alpha: 0.5)
                : tokens.border,
          ),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
        child: Row(
          children: [
            // Checkbox
            if (model.isArchived)
              Icon(
                FluentIcons.archive_24_regular,
                size: 20,
                color: tokens.textFaint,
              )
            else if (isProcessingThis)
              const FluentSpinner(size: 20, strokeWidth: 2)
            else
              GestureDetector(
                onTap: canInteract ? onToggleEnabled : null,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: model.isEnabled ? tokens.accent : Colors.transparent,
                    border: Border.all(
                      color:
                          model.isEnabled ? tokens.accent : tokens.border,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                  child: model.isEnabled
                      ? Icon(
                          FluentIcons.checkmark_24_regular,
                          size: 14,
                          color: tokens.accentFg,
                        )
                      : null,
                ),
              ),

            const SizedBox(width: 12),

            // Model name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.friendlyName,
                    style: tokens.fontBody.copyWith(
                      fontSize: 13,
                      fontWeight: model.isDefault
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: model.isArchived
                          ? tokens.textFaint
                          : tokens.text,
                    ),
                  ),
                  if (model.modelId != model.friendlyName) ...[
                    const SizedBox(height: 2),
                    Text(
                      model.modelId,
                      style: tokens.fontMono.copyWith(
                        fontSize: 11.5,
                        color: tokens.textDim,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Default star button
            if (!model.isArchived) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: canInteract && !model.isDefault ? onSetAsDefault : null,
                child: MouseRegion(
                  cursor: canInteract && !model.isDefault
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: model.isDefault
                          ? tokens.accent.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                    child: Icon(
                      model.isDefault
                          ? FluentIcons.star_24_filled
                          : FluentIcons.star_24_regular,
                      size: 20,
                      color:
                          model.isDefault ? tokens.accent : tokens.textFaint,
                    ),
                  ),
                ),
              ),
            ],

            // Status badges
            if (model.isDefault || model.isArchived) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: model.isDefault
                      ? tokens.accent.withValues(alpha: 0.1)
                      : tokens.textFaint.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
                child: Text(
                  model.isDefault ? t.settings.llmProviders.models.badges.kDefault : t.settings.llmProviders.models.badges.archived,
                  style: tokens.fontMono.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: model.isDefault ? tokens.accent : tokens.textFaint,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
