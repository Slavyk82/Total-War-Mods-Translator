import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../providers/settings_providers.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../../widgets/common/fluent_spinner.dart';
import 'llm_models_list.dart';

/// Accordion section for a single LLM provider.
///
/// Displays provider settings and API key configuration.
class LlmProviderSection extends ConsumerStatefulWidget {
  final String providerCode;
  final String providerName;
  final TextEditingController apiKeyController;
  final VoidCallback onSaveApiKey;
  final Widget? additionalSettings;

  const LlmProviderSection({
    super.key,
    required this.providerCode,
    required this.providerName,
    required this.apiKeyController,
    required this.onSaveApiKey,
    this.additionalSettings,
  });

  @override
  ConsumerState<LlmProviderSection> createState() => _LlmProviderSectionState();
}

class _LlmProviderSectionState extends ConsumerState<LlmProviderSection> {
  bool _isExpanded = false;
  bool _isTesting = false;

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);

    try {
      final notifier = ref.read(llmProviderSettingsProvider.notifier);
      final (success, errorMessage) = await notifier.testConnection(widget.providerCode);

      if (mounted) {
        if (success) {
          FluentToast.success(context, 'Connection successful!');
        } else {
          FluentToast.error(
            context,
            'Connection failed: ${errorMessage ?? "Unknown error"}',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header (always visible)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isExpanded
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : null,
                  borderRadius: _isExpanded
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        )
                      : BorderRadius.circular(8),
                ),
              child: Row(
                children: [
                  Icon(
                    _isExpanded
                        ? FluentIcons.chevron_down_24_regular
                        : FluentIcons.chevron_right_24_regular,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.providerName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),

          // Expanded content
          if (_isExpanded)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // API Key field
                  Text(
                    'API Key',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: widget.apiKeyController,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'Enter API key...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          onChanged: (_) => widget.onSaveApiKey(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildIconButton(
                        icon: FluentIcons.plug_connected_24_regular,
                        tooltip: 'Test connection',
                        isLoading: _isTesting,
                        onTap: _testConnection,
                      ),
                    ],
                  ),

                  // Additional settings (model dropdown, etc.)
                  if (widget.additionalSettings != null) ...[
                    const SizedBox(height: 16),
                    widget.additionalSettings!,
                  ],

                  // Models list
                  const SizedBox(height: 16),
                  LlmModelsList(providerCode: widget.providerCode),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: isLoading ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: isLoading ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: isLoading
                    ? Theme.of(context).disabledColor
                    : Theme.of(context).colorScheme.primary,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: isLoading
                ? const FluentSpinner(size: 16, strokeWidth: 2)
                : Icon(
                    icon,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
          ),
        ),
      ),
    );
  }

}
