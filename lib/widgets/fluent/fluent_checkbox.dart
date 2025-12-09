import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// A Fluent Design-style checkbox
///
/// This widget follows Microsoft's Fluent Design System guidelines
/// and replaces the Material Design Checkbox widget.
class FluentCheckbox extends StatefulWidget {
  const FluentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.checkColor,
    this.size = 20.0,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final Color? checkColor;
  final double size;

  @override
  State<FluentCheckbox> createState() => _FluentCheckboxState();
}

class _FluentCheckboxState extends State<FluentCheckbox> {
  bool _isHovered = false;
  bool _isPressed = false;

  void _handleTap() {
    if (widget.onChanged != null) {
      widget.onChanged!(!widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = widget.onChanged != null;
    final activeColor = widget.activeColor ?? theme.colorScheme.primary;
    final checkColor = widget.checkColor ?? Colors.white;

    Color borderColor;
    Color backgroundColor;

    if (!isEnabled) {
      borderColor = theme.colorScheme.onSurface.withValues(alpha: 0.3);
      backgroundColor = Colors.transparent;
    } else if (widget.value) {
      backgroundColor = activeColor;
      borderColor = activeColor;
    } else if (_isPressed) {
      borderColor = activeColor.withValues(alpha: 0.8);
      backgroundColor = activeColor.withValues(alpha: 0.1);
    } else if (_isHovered) {
      borderColor = activeColor.withValues(alpha: 0.7);
      backgroundColor = activeColor.withValues(alpha: 0.05);
    } else {
      borderColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
      backgroundColor = Colors.transparent;
    }

    // Wrap with Material to prevent errors if used without Material ancestor
    return Material(
      color: Colors.transparent,
      child: MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: isEnabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel: isEnabled ? () => setState(() => _isPressed = false) : null,
        onTap: isEnabled ? _handleTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: backgroundColor,
            border: Border.all(
              color: borderColor,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: widget.value
              ? Icon(
                  FluentIcons.checkmark_24_regular,
                  size: widget.size * 0.7,
                  color: isEnabled ? checkColor : checkColor.withValues(alpha: 0.5),
                )
              : null,
        ),
      ),
    ),
    );
  }
}
