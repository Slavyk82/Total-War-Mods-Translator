import 'package:flutter/material.dart';

/// A Fluent Design text button component that replaces Material TextButton.
///
/// Follows Windows Fluent Design System guidelines:
/// - No ripple effects (uses subtle background opacity changes)
/// - Smooth AnimatedContainer transitions (150ms)
/// - MouseRegion for cursor management
/// - Minimal visual weight (no background by default)
///
/// Visual feedback:
/// - Normal: Transparent background
/// - Hover: 8% background opacity
/// - Pressed: 10% background opacity
/// - Disabled: 50% text opacity
///
/// Common use cases:
/// - Dialog action buttons (Cancel, OK)
/// - Secondary actions
/// - Navigation links
/// - Toolbar buttons
///
/// Example:
/// ```dart
/// FluentTextButton(
///   onPressed: () => Navigator.pop(context),
///   child: Text('Cancel'),
/// )
/// ```
class FluentTextButton extends StatefulWidget {
  const FluentTextButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.foregroundColor,
    this.padding,
    this.borderRadius,
  });

  /// Callback when the button is pressed. If null, button is disabled.
  final VoidCallback? onPressed;

  /// The widget to display inside the button (usually Text).
  final Widget child;

  /// Optional icon to display before the child.
  final Widget? icon;

  /// Foreground color (text/icon). Defaults to theme primary color.
  final Color? foregroundColor;

  /// Internal padding. Defaults to EdgeInsets.symmetric(horizontal: 16, vertical: 8).
  final EdgeInsets? padding;

  /// Border radius. Defaults to 4.0.
  final double? borderRadius;

  @override
  State<FluentTextButton> createState() => _FluentTextButtonState();
}

class _FluentTextButtonState extends State<FluentTextButton> {
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

    final foregroundColor =
        widget.foregroundColor ?? theme.colorScheme.primary;
    final padding = widget.padding ??
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
    final borderRadius = widget.borderRadius ?? 4.0;

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
          padding: padding,
          decoration: BoxDecoration(
            color: foregroundColor.withValues(alpha: backgroundOpacity),
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
    return widget.child;
  }
}
