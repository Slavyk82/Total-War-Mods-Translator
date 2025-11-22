import 'package:flutter/material.dart';

/// A Fluent Design-style toggle switch
///
/// This widget follows Microsoft's Fluent Design System guidelines
/// and replaces the Material Design Switch widget.
class FluentToggleSwitch extends StatefulWidget {
  const FluentToggleSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
    this.width = 40.0,
    this.height = 20.0,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;
  final double width;
  final double height;

  @override
  State<FluentToggleSwitch> createState() => _FluentToggleSwitchState();
}

class _FluentToggleSwitchState extends State<FluentToggleSwitch>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _position;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _position = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    if (widget.value) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(FluentToggleSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    } else {
      // Ensure controller is in sync with value even if widget wasn't updated
      if (widget.value && _controller.value != 1.0) {
        _controller.value = 1.0;
      } else if (!widget.value && _controller.value != 0.0) {
        _controller.value = 0.0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    widget.onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = widget.activeColor ?? theme.colorScheme.primary;
    final inactiveColor = widget.inactiveColor ??
        theme.colorScheme.onSurface.withValues(alpha: 0.3);
    final thumbColor = widget.thumbColor ?? Colors.white;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedBuilder(
          animation: _position,
          builder: (context, child) {
            final trackColor = Color.lerp(
              inactiveColor,
              activeColor,
              _position.value,
            )!;

            // Add slight opacity change on hover
            final opacity = _isHovered ? 0.95 : 1.0;

            return Opacity(
              opacity: opacity,
              child: Container(
                width: widget.width,
                height: widget.height,
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: BorderRadius.circular(widget.height / 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: Align(
                    alignment: Alignment(
                      _position.value * 2 - 1,
                      0,
                    ),
                    child: Container(
                      width: widget.height - 4,
                      height: widget.height - 4,
                      decoration: BoxDecoration(
                        color: thumbColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
