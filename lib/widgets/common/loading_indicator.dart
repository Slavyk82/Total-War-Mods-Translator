import 'package:flutter/material.dart';
import 'fluent_spinner.dart';

/// Fluent-style loading indicator.
///
/// Displays a Fluent spinner with optional message.
class LoadingIndicator extends StatelessWidget {
  final String? message;
  final double size;

  const LoadingIndicator({
    super.key,
    this.message,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return FluentLoadingIndicator(
      message: message,
      size: size,
    );
  }
}

/// Small inline loading indicator.
class InlineLoadingIndicator extends StatelessWidget {
  final double size;

  const InlineLoadingIndicator({
    super.key,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    return FluentInlineSpinner(size: size);
  }
}
