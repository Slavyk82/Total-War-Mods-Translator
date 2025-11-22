import 'package:flutter/material.dart';

/// A Fluent Design outlined button component that replaces Material OutlinedButton.
///
/// Follows Windows Fluent Design System guidelines:
/// - No ripple effects (uses border color and background opacity changes)
/// - Smooth AnimatedContainer transitions (150ms)
/// - MouseRegion for cursor management
/// - Prominent border that changes on interaction
///
/// Visual feedback:
/// - Normal: Neutral border, transparent background
/// - Hover: Primary color border, 5% background opacity
/// - Pressed: Primary color border, 8% background opacity
/// - Disabled: 50% border and text opacity
///
/// Common use cases:
/// - Secondary actions alongside primary buttons
/// - Form submit/cancel pairs
/// - Filter/toggle buttons
/// - Card action buttons
///
/// Example:
/// ```dart
/// FluentOutlinedButton(
///   onPressed: () => _applyFilters(),
///   icon: Icon(FluentIcons.filter_24_regular),
///   child: Text('Apply Filters'),
/// )
/// ```
class FluentOutlinedButton extends StatefulWidget {
  const FluentOutlinedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.borderColor,
    this.foregroundColor,
    this.padding,
    this.borderRadius,
    this.borderWidth = 1.5,
    this.minWidth,
    this.minHeight,
  });

  /// Callback when the button is pressed. If null, button is disabled.
  final VoidCallback? onPressed;

  /// The widget to display inside the button (usually Text).
  final Widget child;

  /// Optional icon to display before the child.
  final Widget? icon;

  /// Border color. Defaults to theme divider color (normal) or primary color (hover/pressed).
  final Color? borderColor;

  /// Foreground color (text/icon). Defaults to theme primary color.
  final Color? foregroundColor;

  /// Internal padding. Defaults to EdgeInsets.symmetric(horizontal: 20, vertical: 12).
  final EdgeInsets? padding;

  /// Border radius. Defaults to 4.0.
  final double? borderRadius;

  /// Border width. Defaults to 1.5.
  final double borderWidth;

  /// Minimum width. Defaults to 80.
  final double? minWidth;

  /// Minimum height. Defaults to 32.
  final double? minHeight;

  @override
  State<FluentOutlinedButton> createState() => _FluentOutlinedButtonState();
}

class _FluentOutlinedButtonState extends State<FluentOutlinedButton> {
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
            ? 0.08
            : _isHovered
                ? 0.05
                : 0.0;

    final foregroundColor =
        widget.foregroundColor ?? theme.colorScheme.primary;

    // Border color changes based on interaction state
    final Color effectiveBorderColor;
    if (!isEnabled) {
      effectiveBorderColor = (widget.borderColor ?? theme.dividerColor)
          .withValues(alpha: 0.5);
    } else if (_isPressed || _isHovered) {
      effectiveBorderColor = foregroundColor;
    } else {
      effectiveBorderColor = widget.borderColor ?? theme.dividerColor;
    }

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
            color: foregroundColor.withValues(alpha: backgroundOpacity),
            border: Border.all(
              color: effectiveBorderColor,
              width: widget.borderWidth,
            ),
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
