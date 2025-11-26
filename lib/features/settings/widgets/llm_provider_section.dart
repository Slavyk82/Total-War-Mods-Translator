import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../providers/settings_providers.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../../services/llm/i_llm_service.dart';
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
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
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
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
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

                  // Circuit breaker status
                  const SizedBox(height: 16),
                  _CircuitBreakerStatusWidget(providerCode: widget.providerCode),
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
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
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

/// Widget showing circuit breaker status for a provider
class _CircuitBreakerStatusWidget extends ConsumerStatefulWidget {
  final String providerCode;

  const _CircuitBreakerStatusWidget({required this.providerCode});

  @override
  ConsumerState<_CircuitBreakerStatusWidget> createState() => _CircuitBreakerStatusWidgetState();
}

class _CircuitBreakerStatusWidgetState extends ConsumerState<_CircuitBreakerStatusWidget> {
  bool _isResetting = false;

  Future<void> _resetCircuitBreaker() async {
    setState(() => _isResetting = true);

    try {
      final notifier = ref.read(circuitBreakerStatusProvider(widget.providerCode).notifier);
      final (success, errorMessage) = await notifier.resetCircuitBreaker();

      if (mounted) {
        if (success) {
          FluentToast.success(context, 'Circuit breaker reset successfully');
        } else {
          FluentToast.error(context, 'Failed to reset: ${errorMessage ?? "Unknown error"}');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isResetting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(circuitBreakerStatusProvider(widget.providerCode));

    return statusAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (status) {
        // Only show when circuit breaker is not closed (has issues)
        if (status.state == CircuitBreakerState.closed && status.failureCount == 0) {
          return const SizedBox.shrink();
        }

        final isOpen = status.state == CircuitBreakerState.open;
        final isHalfOpen = status.state == CircuitBreakerState.halfOpen;
        final hasFailures = status.failureCount > 0;

        final (icon, color, label) = switch (status.state) {
          CircuitBreakerState.open => (
              FluentIcons.warning_24_filled,
              Theme.of(context).colorScheme.error,
              'Circuit Breaker OPEN',
            ),
          CircuitBreakerState.halfOpen => (
              FluentIcons.arrow_sync_24_regular,
              Colors.orange,
              'Circuit Breaker Testing',
            ),
          CircuitBreakerState.closed when hasFailures => (
              FluentIcons.info_24_regular,
              Colors.amber,
              'Circuit Breaker OK (${status.failureCount} failures)',
            ),
          _ => (
              FluentIcons.checkmark_circle_24_regular,
              Theme.of(context).colorScheme.primary,
              'Circuit Breaker OK',
            ),
        };

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                    ),
                  ),
                  if (isOpen || isHalfOpen)
                    MouseRegion(
                      cursor: _isResetting ? SystemMouseCursors.basic : SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _isResetting ? null : _resetCircuitBreaker,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: _isResetting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Reset',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                        ),
                      ),
                    ),
                ],
              ),

              // Show last error if available
              if (status.lastErrorMessage != null && status.lastErrorMessage!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (status.lastErrorType != null)
                        Text(
                          'Error type: ${status.lastErrorType}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        status.lastErrorMessage!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                            ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],

              // Show retry time if open
              if (isOpen && status.willAttemptCloseAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Will retry at: ${_formatTime(status.willAttemptCloseAt!)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = time.difference(now);

    if (diff.isNegative) {
      return 'Now';
    } else if (diff.inMinutes < 1) {
      return '${diff.inSeconds}s';
    } else {
      return '${diff.inMinutes}m ${diff.inSeconds % 60}s';
    }
  }
}
