import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../../../../models/domain/llm_provider_model.dart';
import '../../providers/settings_providers.dart';
import '../../../../widgets/fluent/fluent_widgets.dart';
import '../../../../widgets/common/fluent_spinner.dart';

/// A single row inside [LlmModelsList].
///
/// Renders a checkbox, the model's friendly name (with optional model-id
/// secondary label and "Default" badge), and a star button to set the model
/// as the global default. Handles its own enable/disable and set-default
/// Riverpod interactions so the parent list only has to pass the model and
/// a divider flag.
class LlmModelRow extends ConsumerStatefulWidget {
  final LlmProviderModel model;
  final String providerCode;
  final bool showDivider;

  const LlmModelRow({
    super.key,
    required this.model,
    required this.providerCode,
    required this.showDivider,
  });

  @override
  ConsumerState<LlmModelRow> createState() => _LlmModelRowState();
}

class _LlmModelRowState extends ConsumerState<LlmModelRow> {
  bool _isProcessing = false;

  Future<void> _toggleEnabled() async {
    if (_isProcessing) return;

    if (!mounted) return;
    setState(() => _isProcessing = true);

    try {
      final notifier = ref.read(llmModelsProvider(widget.providerCode).notifier);
      final (success, errorMessage) = await notifier.toggleEnabled(widget.model.id);

      if (!mounted) return;

      if (success) {
        FluentToast.success(
          context,
          widget.model.isEnabled ? t.settings.llmProviders.models.toasts.disabled : t.settings.llmProviders.models.toasts.enabled,
        );
      } else {
        FluentToast.error(
          context,
          t.settings.llmProviders.models.toasts.toggleFailed(error: errorMessage ?? 'Unknown error'),
        );
      }
    } finally {
      if (mounted) {
        // Use post-frame callback to avoid MouseRegion issues during rebuild
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _isProcessing = false);
          }
        });
      }
    }
  }

  Future<void> _setAsDefault() async {
    if (_isProcessing || widget.model.isDefault) return;

    if (!mounted) return;
    setState(() => _isProcessing = true);

    try {
      final notifier = ref.read(llmModelsProvider(widget.providerCode).notifier);
      final (success, errorMessage) = await notifier.setAsDefault(widget.model.id);

      if (!mounted) return;

      if (success) {
        FluentToast.success(context, t.settings.llmProviders.models.toasts.setDefaultSuccess);
      } else {
        FluentToast.error(
          context,
          t.settings.llmProviders.models.toasts.setDefaultFailed(error: errorMessage ?? 'Unknown error'),
        );
      }
    } finally {
      if (mounted) {
        // Use post-frame callback to avoid MouseRegion issues during rebuild
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _isProcessing = false);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: _isProcessing ? SystemMouseCursors.basic : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _isProcessing ? null : _toggleEnabled,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.model.isEnabled
                    ? tokens.accentBg
                    : Colors.transparent,
              ),
              child: Row(
                children: [
                  // Checkbox
                  if (_isProcessing)
                    const FluentSpinner(size: 20, strokeWidth: 2)
                  else
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: widget.model.isEnabled
                            ? tokens.accent
                            : Colors.transparent,
                        border: Border.all(
                          color: widget.model.isEnabled
                              ? tokens.accent
                              : tokens.border,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                      ),
                      child: widget.model.isEnabled
                          ? Icon(
                              FluentIcons.checkmark_24_regular,
                              size: 14,
                              color: tokens.accentFg,
                            )
                          : null,
                    ),

                  const SizedBox(width: 12),

                  // Model name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.model.friendlyName,
                                style: tokens.fontBody.copyWith(
                                  fontSize: 13,
                                  color: tokens.text,
                                  fontWeight: widget.model.isDefault
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (widget.model.isDefault) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.accentBg,
                                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                                ),
                                child: Text(
                                  t.settings.llmProviders.models.badges.kDefault,
                                  style: tokens.fontBody.copyWith(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.accent,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (widget.model.modelId != widget.model.friendlyName) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.model.modelId,
                            style: tokens.fontBody.copyWith(
                              fontSize: 12,
                              color: tokens.textDim,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Default star button
                  const SizedBox(width: 8),
                  Tooltip(
                    message: t.tooltips.settings.setDefaultModel,
                    waitDuration: const Duration(milliseconds: 500),
                    child: GestureDetector(
                      onTap: _isProcessing || widget.model.isDefault
                          ? null
                          : _setAsDefault,
                      child: MouseRegion(
                        cursor: _isProcessing || widget.model.isDefault
                            ? SystemMouseCursors.basic
                            : SystemMouseCursors.click,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: widget.model.isDefault
                                ? tokens.accentBg
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(tokens.radiusSm),
                          ),
                          child: Icon(
                            widget.model.isDefault
                                ? FluentIcons.star_24_filled
                                : FluentIcons.star_24_regular,
                            size: 20,
                            color: widget.model.isDefault
                                ? tokens.accent
                                : tokens.textDim,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: tokens.border,
          ),
      ],
    );
  }
}
