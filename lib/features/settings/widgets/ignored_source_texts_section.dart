import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/config/tooltip_strings.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../providers/ignored_source_texts_providers.dart';
import 'ignored_source_texts_datagrid.dart';
import 'ignored_source_text_editor_dialog.dart';

/// Expandable section for managing ignored source texts
class IgnoredSourceTextsSection extends ConsumerStatefulWidget {
  const IgnoredSourceTextsSection({super.key});

  @override
  ConsumerState<IgnoredSourceTextsSection> createState() =>
      _IgnoredSourceTextsSectionState();
}

class _IgnoredSourceTextsSectionState
    extends ConsumerState<IgnoredSourceTextsSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final enabledCountAsync = ref.watch(enabledIgnoredTextsCountProvider);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Accordion header
          _buildHeader(enabledCountAsync),
          // Expanded content
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildExpandedContent(),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AsyncValue<int> enabledCountAsync) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isExpanded
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : Colors.transparent,
            borderRadius: _isExpanded
                ? const BorderRadius.vertical(top: Radius.circular(7))
                : BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Icon(
                FluentIcons.text_bullet_list_square_24_regular,
                size: 24,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ignored Source Texts',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Skip specific source texts during translation',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.6),
                          ),
                    ),
                  ],
                ),
              ),
              // Badge showing enabled count
              enabledCountAsync.when(
                data: (count) => count > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$count active',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      )
                    : const SizedBox.shrink(),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(width: 12),
              AnimatedRotation(
                turns: _isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  FluentIcons.chevron_down_24_regular,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedContent() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Description
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withOpacity(0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  FluentIcons.info_24_regular,
                  size: 18,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Source texts matching these values will be excluded from translation. '
                    'Note: Fully bracketed texts like [PLACEHOLDER] are automatically skipped. '
                    'Use this list for custom patterns specific to your mods.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.8),
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Buttons row
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Tooltip(
                message: TooltipStrings.settingsResetIgnoredDefaults,
                waitDuration: const Duration(milliseconds: 500),
                child: OutlinedButton.icon(
                  onPressed: _resetToDefaults,
                  icon: const Icon(FluentIcons.arrow_reset_24_regular, size: 18),
                  label: const Text('Reset to Defaults'),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: TooltipStrings.settingsAddIgnoredText,
                waitDuration: const Duration(milliseconds: 500),
                child: FilledButton.icon(
                  onPressed: _addText,
                  icon: const Icon(FluentIcons.add_24_regular, size: 18),
                  label: const Text('Add Text'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // DataGrid
          const IgnoredSourceTextsDataGrid(),
        ],
      ),
    );
  }

  Future<void> _addText() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const IgnoredSourceTextEditorDialog(),
    );

    if (result != null && result.isNotEmpty && mounted) {
      final (success, error) =
          await ref.read(ignoredSourceTextsProvider.notifier).addText(result);

      if (mounted) {
        if (success) {
          FluentToast.success(context, 'Text added successfully');
        } else {
          FluentToast.error(context, error ?? 'Failed to add text');
        }
      }
    }
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: const Text(
          'This will delete all current ignored texts and restore the default values:\n\n'
          '• placeholder\n'
          '• dummy\n\n'
          'Note: Texts fully enclosed in brackets like [placeholder] are always filtered automatically.\n\n'
          'Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final (success, error) =
          await ref.read(ignoredSourceTextsProvider.notifier).resetToDefaults();

      if (mounted) {
        if (success) {
          FluentToast.success(context, 'Reset to defaults successfully');
        } else {
          FluentToast.error(context, error ?? 'Failed to reset to defaults');
        }
      }
    }
  }
}
