import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// A Fluent Design toast notification component that replaces Material SnackBar.
///
/// Follows Windows Fluent Design System guidelines:
/// - Appears in top-right corner (Windows-style)
/// - Smooth slide-in/slide-out animations
/// - Auto-dismisses after duration
/// - Supports manual dismiss with close button
/// - Color-coded by severity (success, error, warning, info)
///
/// Visual design:
/// - Elevated card with shadow
/// - Icon indicating type
/// - Clear, concise message
/// - Optional action button
/// - Close button (X)
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
      builder: (context) => _FluentToastWidget(
        message: message,
        type: type,
        actionLabel: actionLabel,
        onActionPressed: onActionPressed,
        onDismiss: () => overlayEntry.remove(),
      ),
    );

    overlay.insert(overlayEntry);

    // Auto-dismiss after duration
    Future.delayed(duration, () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
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

/// Toast widget that displays the actual notification.
class _FluentToastWidget extends StatefulWidget {
  const _FluentToastWidget({
    required this.message,
    required this.type,
    required this.onDismiss,
    this.actionLabel,
    this.onActionPressed,
  });

  final String message;
  final FluentToastType type;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  @override
  State<_FluentToastWidget> createState() => _FluentToastWidgetState();
}

class _FluentToastWidgetState extends State<_FluentToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0), // Slide from right
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = _getTypeConfig(theme);

    return Positioned(
      top: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 400,
                minWidth: 300,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: config.borderColor,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type icon
                    Icon(
                      config.icon,
                      color: config.iconColor,
                      size: 24,
                    ),
                    const SizedBox(width: 12),

                    // Message
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.message,
                            style: theme.textTheme.bodyMedium,
                          ),
                          if (widget.actionLabel != null &&
                              widget.onActionPressed != null) ...[
                            const SizedBox(height: 8),
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () {
                                  widget.onActionPressed?.call();
                                  _dismiss();
                                },
                                child: Text(
                                  widget.actionLabel!,
                                  style: theme.textTheme.bodyMedium!.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Close button
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _dismiss,
                        child: Icon(
                          FluentIcons.dismiss_24_regular,
                          size: 20,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  _ToastTypeConfig _getTypeConfig(ThemeData theme) {
    switch (widget.type) {
      case FluentToastType.success:
        return _ToastTypeConfig(
          icon: FluentIcons.checkmark_circle_24_filled,
          iconColor: const Color(0xFF107C10), // Success green
          borderColor: const Color(0xFF107C10),
        );
      case FluentToastType.error:
        return _ToastTypeConfig(
          icon: FluentIcons.error_circle_24_filled,
          iconColor: const Color(0xFFD13438), // Error red
          borderColor: const Color(0xFFD13438),
        );
      case FluentToastType.warning:
        return _ToastTypeConfig(
          icon: FluentIcons.warning_24_filled,
          iconColor: const Color(0xFFF7630C), // Warning orange
          borderColor: const Color(0xFFF7630C),
        );
      case FluentToastType.info:
        return _ToastTypeConfig(
          icon: FluentIcons.info_24_filled,
          iconColor: theme.colorScheme.primary,
          borderColor: theme.colorScheme.primary,
        );
    }
  }
}

/// Configuration for toast appearance based on type.
class _ToastTypeConfig {
  const _ToastTypeConfig({
    required this.icon,
    required this.iconColor,
    required this.borderColor,
  });

  final IconData icon;
  final Color iconColor;
  final Color borderColor;
}

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
