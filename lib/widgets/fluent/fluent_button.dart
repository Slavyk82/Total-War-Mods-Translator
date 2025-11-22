import 'package:flutter/material.dart';

/// A Fluent Design button component that replaces Material ElevatedButton.
///
/// Follows Windows Fluent Design System guidelines:
/// - No ripple effects (uses opacity changes instead)
/// - Smooth AnimatedContainer transitions (150ms)
/// - MouseRegion for cursor management
/// - Proper hover, pressed, and disabled states
///
/// Visual feedback:
/// - Normal: Full opacity background with primary color
/// - Hover: 95% opacity background
/// - Pressed: 90% opacity background
/// - Disabled: 50% opacity
///
/// Example:
/// ```dart
/// FluentButton(
///   onPressed: () => print('Clicked'),
///   child: Text('Click Me'),
/// )
/// ```
class FluentButton extends StatefulWidget {
  const FluentButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.padding,
    this.borderRadius,
    this.minWidth,
    this.minHeight,
  });

  /// Callback when the button is pressed. If null, button is disabled.
  final VoidCallback? onPressed;

  /// The widget to display inside the button (usually Text).
  final Widget child;

  /// Optional icon to display before the child.
  final Widget? icon;

  /// Background color of the button. Defaults to theme primary color.
  final Color? backgroundColor;

  /// Foreground color (text/icon). Defaults to white.
  final Color? foregroundColor;

  /// Internal padding. Defaults to EdgeInsets.symmetric(horizontal: 20, vertical: 12).
  final EdgeInsets? padding;

  /// Border radius. Defaults to 4.0.
  final double? borderRadius;

  /// Minimum width. Defaults to 80.
  final double? minWidth;

  /// Minimum height. Defaults to 32.
  final double? minHeight;

  @override
  State<FluentButton> createState() => _FluentButtonState();
}

class _FluentButtonState extends State<FluentButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = widget.onPressed != null;

    // Determine opacity based on state
    final double opacity = !isEnabled
        ? 0.5
        : _isPressed
            ? 0.9
            : _isHovered
                ? 0.95
                : 1.0;

    final backgroundColor =
        widget.backgroundColor ?? theme.colorScheme.primary;
    final foregroundColor = widget.foregroundColor ?? Colors.white;
    final padding = widget.padding ??
        const EdgeInsets.symmetric(horizontal: 20, vertical: 12);
    final borderRadius = widget.borderRadius ?? 4.0;
    final minWidth = widget.minWidth ?? 80.0;
    final minHeight = widget.minHeight ?? 32.0;

    return MouseRegion(
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
          constraints: BoxConstraints(
            minWidth: minWidth,
            minHeight: minHeight,
          ),
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: DefaultTextStyle(
            style: theme.textTheme.bodyMedium!.copyWith(
              color: foregroundColor.withValues(alpha: isEnabled ? 1.0 : 0.5),
              fontWeight: FontWeight.w600,
            ),
            child: IconTheme(
              data: IconThemeData(
                color: foregroundColor.withValues(alpha: isEnabled ? 1.0 : 0.5),
                size: 16,
              ),
              child: _buildContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (widget.icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          widget.icon!,
          const SizedBox(width: 8),
          widget.child,
        ],
      );
    }
    return Center(child: widget.child);
  }
}
