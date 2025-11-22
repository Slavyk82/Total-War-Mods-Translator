import 'package:flutter/material.dart';

/// Fluent Design icon button with hover states
///
/// Provides a Windows-native button experience with:
/// - Hover state background changes
/// - Press state feedback
/// - Disabled state opacity
/// - Tooltip support
class FluentIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  const FluentIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  State<FluentIconButton> createState() => _FluentIconButtonState();
}

class _FluentIconButtonState extends State<FluentIconButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = widget.onPressed != null;

    Color backgroundColor;
    if (!isEnabled) {
      backgroundColor = Colors.transparent;
    } else if (_isPressed) {
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.1);
    } else if (_isHovered) {
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.08);
    } else {
      backgroundColor = Colors.transparent;
    }

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() {
          _isHovered = false;
          _isPressed = false;
        }),
        child: GestureDetector(
          onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
          onTapUp: isEnabled ? (_) {
            setState(() => _isPressed = false);
            widget.onPressed?.call();
          } : null,
          onTapCancel: () => setState(() => _isPressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: isEnabled
                  ? theme.iconTheme.color
                  : theme.iconTheme.color?.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fluent Design outlined button with hover states
///
/// Provides a Windows-native outlined button with:
/// - Icon and label
/// - Hover state background and border changes
/// - Press state feedback
/// - Fluent Design animations
class FluentOutlinedButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const FluentOutlinedButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  State<FluentOutlinedButton> createState() => _FluentOutlinedButtonState();
}

class _FluentOutlinedButtonState extends State<FluentOutlinedButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color backgroundColor;
    Color borderColor;
    if (_isPressed) {
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.05);
      borderColor = theme.colorScheme.primary;
    } else if (_isHovered) {
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.08);
      borderColor = theme.colorScheme.primary;
    } else {
      backgroundColor = Colors.transparent;
      borderColor = theme.dividerColor;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
