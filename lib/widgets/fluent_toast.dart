import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// Type of toast notification
enum ToastType {
  success,
  error,
  warning,
  info,
}

/// Fluent Design toast notification widget
///
/// Displays a non-intrusive notification at the bottom-right of the screen
/// following Windows Fluent Design principles.
class FluentToast extends StatefulWidget {
  const FluentToast({
    super.key,
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final ToastType type;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<FluentToast> createState() => _FluentToastState();
}

class _FluentToastState extends State<FluentToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();

    // Auto-dismiss after duration
    Future.delayed(widget.duration, () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _controller.reverse();
    if (mounted) {
      widget.onDismissed();
    }
  }

  ToastConfig _getConfig() {
    switch (widget.type) {
      case ToastType.success:
        return ToastConfig(
          icon: FluentIcons.checkmark_circle_24_filled,
          iconColor: const Color(0xFF107C10),
          backgroundColor: const Color(0xFFDFF6DD),
          borderColor: const Color(0xFF107C10),
        );
      case ToastType.error:
        return ToastConfig(
          icon: FluentIcons.error_circle_24_filled,
          iconColor: const Color(0xFFA80000),
          backgroundColor: const Color(0xFFFDE7E9),
          borderColor: const Color(0xFFA80000),
        );
      case ToastType.warning:
        return ToastConfig(
          icon: FluentIcons.warning_24_filled,
          iconColor: const Color(0xFFF7630C),
          backgroundColor: const Color(0xFFFFF4CE),
          borderColor: const Color(0xFFF7630C),
        );
      case ToastType.info:
        return ToastConfig(
          icon: FluentIcons.info_24_filled,
          iconColor: const Color(0xFF0078D4),
          backgroundColor: const Color(0xFFF3F2F1),
          borderColor: const Color(0xFF0078D4),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _getConfig();

    return Positioned(
      right: 16,
      bottom: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(
                minWidth: 280,
                maxWidth: 400,
              ),
              decoration: BoxDecoration(
                color: config.backgroundColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: config.borderColor,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.13),
                    blurRadius: 6.4,
                    offset: const Offset(0, 3.2),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.11),
                    blurRadius: 1.6,
                    offset: const Offset(0, 0.8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      config.icon,
                      color: config.iconColor,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF323130),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _DismissButton(onPressed: _dismiss),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Configuration for toast appearance
class ToastConfig {
  const ToastConfig({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.borderColor,
  });

  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;
}

/// Dismiss button for toast notification
class _DismissButton extends StatefulWidget {
  const _DismissButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_DismissButton> createState() => _DismissButtonState();
}

class _DismissButtonState extends State<_DismissButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _isHovered
                ? const Color(0xFF000000).withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
          child: const Icon(
            FluentIcons.dismiss_24_regular,
            size: 12,
            color: Color(0xFF605E5C),
          ),
        ),
      ),
    );
  }
}
