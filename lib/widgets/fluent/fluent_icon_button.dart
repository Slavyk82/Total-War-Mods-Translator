import 'package:flutter/material.dart';

/// A Fluent Design icon button component that replaces Material IconButton.
///
/// Follows Windows Fluent Design System guidelines:
/// - No ripple effects (uses subtle background opacity changes)
/// - Smooth AnimatedContainer transitions (150ms)
/// - MouseRegion for cursor management
/// - 32x32 minimum touch target
/// - Circular or square button shapes
///
/// Visual feedback:
/// - Normal: Transparent background
/// - Hover: 8% background opacity
/// - Pressed: 10% background opacity
/// - Disabled: 50% icon opacity
///
/// Common use cases:
/// - Toolbar actions
/// - Close/minimize/maximize buttons
/// - Navigation icons
/// - Quick actions in lists
///
/// Example:
/// ```dart
/// FluentIconButton(
///   icon: Icon(FluentIcons.delete_24_regular),
///   onPressed: () => _deleteItem(),
///   tooltip: 'Delete',
/// )
/// ```
class FluentIconButton extends StatefulWidget {
  const FluentIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconColor,
    this.backgroundColor,
    this.size = 32.0,
    this.iconSize = 20.0,
    this.shape = FluentIconButtonShape.square,
  });

  /// The icon to display.
  final Widget icon;

  /// Callback when the button is pressed. If null, button is disabled.
  final VoidCallback? onPressed;

  /// Optional tooltip to display on hover.
  final String? tooltip;

  /// Icon color. Defaults to theme foreground color.
  final Color? iconColor;

  /// Background color when hovered/pressed. Defaults to theme foreground color.
  final Color? backgroundColor;

  /// Size of the button (width and height). Defaults to 32.0.
  final double size;

  /// Size of the icon. Defaults to 20.0.
  final double iconSize;

  /// Shape of the button. Defaults to square.
  final FluentIconButtonShape shape;

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

    // Determine background opacity based on state
    final double backgroundOpacity = !isEnabled
        ? 0.0
        : _isPressed
            ? 0.10
            : _isHovered
                ? 0.08
                : 0.0;

    final iconColor = widget.iconColor ?? theme.colorScheme.onSurface;
    final backgroundColor = widget.backgroundColor ?? theme.colorScheme.onSurface;

    final button = MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: isEnabled ? (_) => setState(() => _isHovered = true) : null,
      onExit: isEnabled ? (_) => setState(() => _isHovered = false) : null,
      child: GestureDetector(
        onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: isEnabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel:
            isEnabled ? () => setState(() => _isPressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: backgroundColor.withValues(alpha: backgroundOpacity),
            borderRadius: widget.shape == FluentIconButtonShape.circle
                ? BorderRadius.circular(widget.size / 2)
                : BorderRadius.circular(4.0),
          ),
          child: Center(
            child: IconTheme(
              data: IconThemeData(
                color: iconColor.withValues(alpha: isEnabled ? 1.0 : 0.5),
                size: widget.iconSize,
              ),
              child: widget.icon,
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 500),
        child: button,
      );
    }

    return button;
  }
}

/// Shape options for FluentIconButton.
enum FluentIconButtonShape {
  /// Square button with rounded corners (4px radius).
  square,

  /// Circular button.
  circle,
}
