import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../../theme/twmt_theme_tokens.dart';

/// Types of toast notifications.
enum FluentToastType {
  /// Success message (green, checkmark icon).
  success,

  /// Error message (red, error icon).
  error,

  /// Warning message (orange, warning icon).
  warning,

  /// Info message (blue, info icon).
  info,
}

/// A Fluent Design toast notification component that replaces Material SnackBar.
///
/// Follows Windows Fluent Design System guidelines:
/// - Appears in the bottom-right corner
/// - Smooth slide-in/fade-out animations
/// - Auto-dismisses after [duration]
/// - Supports manual dismiss with close button
/// - Colour-coded by severity via [TwmtThemeTokens]
///
/// Example:
/// ```dart
/// FluentToast.show(
///   context: context,
///   message: 'Changes saved successfully',
///   type: FluentToastType.success,
/// );
/// ```
class FluentToast {
  /// Show a toast notification.
  ///
  /// [actionLabel] and [onActionPressed] are accepted for source-compat with
  /// the previous façade API but are currently not rendered by the unified
  /// bottom-right toast widget.
  static void show({
    required BuildContext context,
    required String message,
    FluentToastType type = FluentToastType.info,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onActionPressed,
  }) {
    final overlay = Overlay.of(context);
    late final OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => FluentToastWidget(
        message: message,
        type: type,
        duration: duration,
        onDismissed: () {
          if (overlayEntry.mounted) {
            overlayEntry.remove();
          }
        },
      ),
    );

    overlay.insert(overlayEntry);
  }

  /// Show a success toast (green).
  static void success(BuildContext context, String message) {
    show(context: context, message: message, type: FluentToastType.success);
  }

  /// Show an error toast (red).
  static void error(BuildContext context, String message) {
    show(context: context, message: message, type: FluentToastType.error);
  }

  /// Show a warning toast (orange).
  static void warning(BuildContext context, String message) {
    show(context: context, message: message, type: FluentToastType.warning);
  }

  /// Show an info toast (blue).
  static void info(BuildContext context, String message) {
    show(context: context, message: message, type: FluentToastType.info);
  }
}

/// Animated toast widget rendered by the [FluentToast] façade.
///
/// Exposed publicly so it can be embedded in custom overlays (e.g. the shared
/// [ToastNotificationService]) and exercised in widget tests.
class FluentToastWidget extends StatefulWidget {
  const FluentToastWidget({
    super.key,
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final FluentToastType type;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<FluentToastWidget> createState() => _FluentToastWidgetState();
}

class _FluentToastWidgetState extends State<FluentToastWidget>
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

    // Auto-dismiss after duration.
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

  _ToastConfig _getConfig(TwmtThemeTokens tokens) {
    switch (widget.type) {
      case FluentToastType.success:
        return _ToastConfig(
          icon: FluentIcons.checkmark_circle_24_filled,
          iconColor: tokens.ok,
          backgroundColor: tokens.okBg,
          borderColor: tokens.ok,
        );
      case FluentToastType.error:
        return _ToastConfig(
          icon: FluentIcons.error_circle_24_filled,
          iconColor: tokens.err,
          backgroundColor: tokens.errBg,
          borderColor: tokens.err,
        );
      case FluentToastType.warning:
        return _ToastConfig(
          icon: FluentIcons.warning_24_filled,
          iconColor: tokens.warn,
          backgroundColor: tokens.warnBg,
          borderColor: tokens.warn,
        );
      case FluentToastType.info:
        return _ToastConfig(
          icon: FluentIcons.info_24_filled,
          iconColor: tokens.info,
          backgroundColor: tokens.infoBg,
          borderColor: tokens.info,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final config = _getConfig(tokens);

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
                borderRadius: BorderRadius.circular(tokens.radiusSm),
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
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: tokens.text,
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

/// Per-type icon + colour configuration for [FluentToastWidget].
class _ToastConfig {
  const _ToastConfig({
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

/// Dismiss button for toast notification.
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
    final tokens = context.tokens;
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
                ? tokens.border.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(tokens.radiusXs),
          ),
          child: Icon(
            FluentIcons.dismiss_24_regular,
            size: 12,
            color: tokens.textMid,
          ),
        ),
      ),
    );
  }
}
