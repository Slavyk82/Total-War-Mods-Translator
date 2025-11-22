import 'package:flutter/material.dart';

/// Fluent Design dialog button with hover states and loading support.
///
/// Follows Microsoft Fluent Design System principles for Windows desktop.
/// Supports both primary and secondary button styles with smooth hover animations.
///
/// Example usage:
/// ```dart
/// FluentDialogButton(
///   icon: FluentIcons.save_24_regular,
///   label: 'Save',
///   isPrimary: true,
///   onTap: _handleSave,
/// )
/// ```
class FluentDialogButton extends StatefulWidget {
  /// Icon to display on the button
  final IconData icon;

  /// Text label for the button
  final String label;

  /// Callback when button is tapped (null disables the button)
  final VoidCallback? onTap;

  /// Whether this is a primary action button (styled with accent color)
  final bool isPrimary;

  /// Whether to show loading indicator instead of icon
  final bool isLoading;

  const FluentDialogButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.isPrimary = false,
    this.isLoading = false,
  });

  @override
  State<FluentDialogButton> createState() => _FluentDialogButtonState();
}

class _FluentDialogButtonState extends State<FluentDialogButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = widget.onTap != null && !widget.isLoading;

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: isEnabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isPrimary
                ? (_isHovered && isEnabled
                    ? theme.colorScheme.primary.withValues(alpha: 0.9)
                    : theme.colorScheme.primary)
                : (_isHovered && isEnabled
                    ? theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
            border: widget.isPrimary
                ? null
                : Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isLoading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.isPrimary
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.primary,
                  ),
                )
              else
                Icon(
                  widget.icon,
                  size: 16,
                  color: isEnabled
                      ? (widget.isPrimary
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isEnabled
                      ? (widget.isPrimary
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
