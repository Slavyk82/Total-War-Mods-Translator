import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// Fluent Design action button for settings UI
///
/// Consolidates DetectButton, TestButton, BrowseButton, and DefaultPathButton
class SettingsActionButton extends StatefulWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final bool isDisabled;
  final String? tooltip;

  const SettingsActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.isDisabled = false,
    this.tooltip,
  });

  /// Factory constructor for detect button
  factory SettingsActionButton.detect({
    required VoidCallback onPressed,
    required bool isDetecting,
    String? tooltip,
  }) {
    return SettingsActionButton(
      onPressed: onPressed,
      icon: FluentIcons.search_24_regular,
      isDisabled: isDetecting,
      tooltip: tooltip ?? 'Auto-detect',
    );
  }

  /// Factory constructor for test button
  factory SettingsActionButton.test({
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return SettingsActionButton(
      onPressed: onPressed,
      icon: FluentIcons.beaker_24_regular,
      tooltip: tooltip ?? 'Test',
    );
  }

  /// Factory constructor for browse button
  factory SettingsActionButton.browse({
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return SettingsActionButton(
      onPressed: onPressed,
      icon: FluentIcons.folder_open_24_regular,
      tooltip: tooltip ?? 'Browse',
    );
  }

  /// Factory constructor for default path button
  factory SettingsActionButton.defaultPath({
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return SettingsActionButton(
      onPressed: onPressed,
      icon: FluentIcons.checkmark_circle_24_regular,
      tooltip: tooltip ?? 'Use default path',
    );
  }

  @override
  State<SettingsActionButton> createState() => _SettingsActionButtonState();
}

class _SettingsActionButtonState extends State<SettingsActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = _isHovered
        ? theme.colorScheme.primary.withValues(alpha: 0.1)
        : theme.colorScheme.surface;

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: widget.isDisabled
            ? theme.disabledColor.withValues(alpha: 0.1)
            : backgroundColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Icon(
        widget.icon,
        size: 16,
        color: widget.isDisabled
            ? theme.disabledColor
            : theme.colorScheme.primary,
      ),
    );

    final button = MouseRegion(
      cursor: widget.isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.isDisabled ? null : widget.onPressed,
        child: child,
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }

    return button;
  }
}
