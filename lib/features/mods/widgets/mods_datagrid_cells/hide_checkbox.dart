import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/mods/models/mods_cell_data.dart';

/// Hide checkbox widget for toggling mod visibility.
///
/// Displays a Fluent Design styled checkbox that allows users to
/// hide or show mods in the main list. The checkbox state reflects
/// whether the mod is currently hidden.
class HideCheckbox extends StatelessWidget {
  /// The data containing the mod's hidden state.
  final HideData data;

  /// Whether the grid is currently showing hidden mods.
  final bool showingHidden;

  /// Callback for toggling the hidden state.
  final void Function(String workshopId, bool hide)? onToggle;

  const HideCheckbox({
    super.key,
    required this.data,
    required this.showingHidden,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // When showing hidden mods: checkbox is checked (mod is hidden)
    // When showing visible mods: checkbox is unchecked (mod is visible)
    // Clicking toggles the hidden state
    final isChecked = data.isHidden;

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Tooltip(
        message: showingHidden
            ? 'Uncheck to show this mod in the main list'
            : 'Check to hide this mod from the main list',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              if (onToggle != null) {
                // Toggle hidden state
                onToggle!(data.workshopId, !data.isHidden);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isChecked
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isChecked
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                  width: 1.5,
                ),
              ),
              child: isChecked
                  ? Icon(
                      FluentIcons.checkmark_16_filled,
                      size: 16,
                      color: theme.colorScheme.onPrimary,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
