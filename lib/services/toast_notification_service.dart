import 'package:flutter/material.dart';
import '../widgets/fluent_toast.dart';

/// Toast notification service for displaying Fluent Design toast messages
///
/// This service provides a centralized way to show toast notifications
/// throughout the app using Windows Fluent Design patterns.
class ToastNotificationService {
  static OverlayEntry? _currentToast;
  static bool _isShowing = false;

  /// Shows a success toast notification
  static void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _showToast(
      context,
      message: message,
      type: ToastType.success,
      duration: duration,
    );
  }

  /// Shows an error toast notification
  static void showError(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    _showToast(
      context,
      message: message,
      type: ToastType.error,
      duration: duration,
    );
  }

  /// Shows a warning toast notification
  static void showWarning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _showToast(
      context,
      message: message,
      type: ToastType.warning,
      duration: duration,
    );
  }

  /// Shows an info toast notification
  static void showInfo(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _showToast(
      context,
      message: message,
      type: ToastType.info,
      duration: duration,
    );
  }

  /// Internal method to show toast with specified type
  static void _showToast(
    BuildContext context, {
    required String message,
    required ToastType type,
    required Duration duration,
  }) {
    // Remove any existing toast first
    if (_isShowing) {
      _currentToast?.remove();
      _currentToast = null;
      _isShowing = false;
    }

    final overlay = Overlay.of(context);

    _currentToast = OverlayEntry(
      builder: (context) => FluentToast(
        message: message,
        type: type,
        duration: duration,
        onDismissed: () {
          _currentToast?.remove();
          _currentToast = null;
          _isShowing = false;
        },
      ),
    );

    _isShowing = true;
    overlay.insert(_currentToast!);
  }

  /// Dismisses the current toast immediately
  static void dismiss() {
    if (_isShowing && _currentToast != null) {
      _currentToast?.remove();
      _currentToast = null;
      _isShowing = false;
    }
  }
}
