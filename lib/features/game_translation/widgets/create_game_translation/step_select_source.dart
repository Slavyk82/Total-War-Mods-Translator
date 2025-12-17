import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:intl/intl.dart';

import '../../../../providers/selected_game_provider.dart';
import '../../../../services/game/game_localization_service.dart';
import '../../providers/game_translation_providers.dart';
import 'game_translation_creation_state.dart';

/// Step 1: Select source localization pack
class StepSelectSource extends ConsumerWidget {
  final GameTranslationCreationState state;
  final VoidCallback onStateChanged;

  const StepSelectSource({
    super.key,
    required this.state,
    required this.onStateChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedGameAsync = ref.watch(selectedGameProvider);
    final packsAsync = ref.watch(detectedLocalPacksProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Source Pack',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Choose the game localization pack that will serve as the source for translation.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 24),

        // Selected game info
        selectedGameAsync.when(
          data: (game) => game != null
              ? Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        FluentIcons.games_24_regular,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        game.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              : const Text('No game selected'),
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
        ),

        const SizedBox(height: 24),

        // Pack selection
        Text(
          'Available Localization Packs',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 12),

        packsAsync.when(
          data: (packs) {
            if (packs.isEmpty) {
              return _buildNoPacks(theme);
            }
            return _buildPackList(context, theme, packs);
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => _buildError(theme, e.toString()),
        ),
      ],
    );
  }

  Widget _buildNoPacks(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(
            FluentIcons.warning_24_regular,
            size: 48,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            'No localization packs found',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure the game is installed and has localization files in the data folder.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPackList(
    BuildContext context,
    ThemeData theme,
    List<DetectedLocalPack> packs,
  ) {
    final dateFormat = DateFormat.yMMMd().add_Hm();

    return Column(
      children: packs.map((pack) {
        final isSelected = state.selectedSourcePack == pack;

        return _PackSelectionItem(
          pack: pack,
          isSelected: isSelected,
          dateFormat: dateFormat,
          onTap: () {
            state.selectedSourcePack = pack;
            // Clear target languages when source changes
            state.clearLanguages();
            onStateChanged();
          },
        );
      }).toList(),
    );
  }

  Widget _buildError(ThemeData theme, String error) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// A selectable pack item following Fluent Design patterns
class _PackSelectionItem extends StatefulWidget {
  final DetectedLocalPack pack;
  final bool isSelected;
  final DateFormat dateFormat;
  final VoidCallback onTap;

  const _PackSelectionItem({
    required this.pack,
    required this.isSelected,
    required this.dateFormat,
    required this.onTap,
  });

  @override
  State<_PackSelectionItem> createState() => _PackSelectionItemState();
}

class _PackSelectionItemState extends State<_PackSelectionItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color backgroundColor;
    if (widget.isSelected) {
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.15);
    } else if (_isHovered) {
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.08);
    } else {
      backgroundColor = Colors.transparent;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.isSelected
                    ? theme.colorScheme.primary
                    : theme.dividerColor,
                width: widget.isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Radio indicator
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.isSelected
                          ? theme.colorScheme.primary
                          : theme.dividerColor,
                      width: 2,
                    ),
                  ),
                  child: widget.isSelected
                      ? Center(
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                // Language icon
                Icon(
                  FluentIcons.local_language_24_regular,
                  color: widget.isSelected
                      ? theme.colorScheme.primary
                      : theme.iconTheme.color,
                ),
                const SizedBox(width: 12),
                // Pack info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.pack.languageName,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: widget.isSelected
                              ? theme.colorScheme.primary
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'local_${widget.pack.languageCode}.pack',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color
                              ?.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                // Size and date
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      widget.pack.formattedSize,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.dateFormat.format(widget.pack.lastModified),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color
                            ?.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
