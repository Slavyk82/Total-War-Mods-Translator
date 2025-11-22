import 'package:flutter/material.dart';

/// A Fluent Design-style circular progress indicator
///
/// This widget follows Microsoft's Fluent Design System guidelines
/// and replaces the Material Design CircularProgressIndicator widget.
class FluentProgressRing extends StatelessWidget {
  const FluentProgressRing({
    super.key,
    this.value,
    this.strokeWidth = 4.0,
    this.color,
    this.backgroundColor,
  });

  final double? value;
  final double strokeWidth;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progressColor = color ?? theme.colorScheme.primary;
    final bgColor = backgroundColor ??
        theme.colorScheme.onSurface.withValues(alpha: 0.1);

    return SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        value: value,
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(progressColor),
        backgroundColor: bgColor,
      ),
    );
  }
}

/// A Fluent Design-style linear progress indicator
///
/// This widget follows Microsoft's Fluent Design System guidelines
/// and replaces the Material Design LinearProgressIndicator widget.
class FluentProgressBar extends StatelessWidget {
  const FluentProgressBar({
    super.key,
    this.value,
    this.height = 4.0,
    this.color,
    this.backgroundColor,
    this.borderRadius,
  });

  final double? value;
  final double height;
  final Color? color;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progressColor = color ?? theme.colorScheme.primary;
    final bgColor = backgroundColor ??
        theme.colorScheme.onSurface.withValues(alpha: 0.1);

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: LinearProgressIndicator(
          value: value,
          valueColor: AlwaysStoppedAnimation<Color>(progressColor),
          backgroundColor: bgColor,
        ),
      ),
    );
  }
}
