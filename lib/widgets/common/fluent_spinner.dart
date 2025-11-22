import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Fluent Design spinner/progress indicator.
///
/// A custom spinner that follows Microsoft Fluent Design principles.
/// Uses animated dots instead of Material's circular progress indicator.
class FluentSpinner extends StatefulWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const FluentSpinner({
    super.key,
    this.size = 40,
    this.color,
    this.strokeWidth = 3,
  });

  @override
  State<FluentSpinner> createState() => _FluentSpinnerState();
}

class _FluentSpinnerState extends State<FluentSpinner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _FluentSpinnerPainter(
              progress: _controller.value,
              color: color,
              strokeWidth: widget.strokeWidth,
            ),
          );
        },
      ),
    );
  }
}

class _FluentSpinnerPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _FluentSpinnerPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Draw a partial arc that rotates
    final startAngle = progress * 2 * math.pi;
    const sweepAngle = math.pi * 0.75; // 3/4 of a circle

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_FluentSpinnerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Fluent Design progress indicator with optional message.
///
/// Displays a Fluent spinner with optional message text below.
class FluentLoadingIndicator extends StatelessWidget {
  final String? message;
  final double size;
  final Color? color;

  const FluentLoadingIndicator({
    super.key,
    this.message,
    this.size = 40,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FluentSpinner(
            size: size,
            color: color,
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// Small inline Fluent spinner for use within widgets.
class FluentInlineSpinner extends StatelessWidget {
  final double size;
  final Color? color;

  const FluentInlineSpinner({
    super.key,
    this.size = 16,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return FluentSpinner(
      size: size,
      color: color,
      strokeWidth: 2,
    );
  }
}

/// Fluent Design progress bar (linear).
///
/// A linear progress indicator following Fluent Design principles.
class FluentProgressBar extends StatelessWidget {
  final double? value; // null for indeterminate
  final double height;
  final Color? color;
  final Color? backgroundColor;

  const FluentProgressBar({
    super.key,
    this.value,
    this.height = 4,
    this.color,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final progressColor = color ?? Theme.of(context).colorScheme.primary;
    final bgColor = backgroundColor ??
        Theme.of(context).colorScheme.surface.withValues(alpha: 0.3);

    if (value == null) {
      // Indeterminate progress
      return _FluentIndeterminateProgressBar(
        height: height,
        color: progressColor,
        backgroundColor: bgColor,
      );
    }

    // Determinate progress
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: LinearProgressIndicator(
          value: value,
          backgroundColor: bgColor,
          valueColor: AlwaysStoppedAnimation<Color>(progressColor),
        ),
      ),
    );
  }
}

class _FluentIndeterminateProgressBar extends StatefulWidget {
  final double height;
  final Color color;
  final Color backgroundColor;

  const _FluentIndeterminateProgressBar({
    required this.height,
    required this.color,
    required this.backgroundColor,
  });

  @override
  State<_FluentIndeterminateProgressBar> createState() =>
      _FluentIndeterminateProgressBarState();
}

class _FluentIndeterminateProgressBarState
    extends State<_FluentIndeterminateProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.height / 2),
      child: SizedBox(
        height: widget.height,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return LinearProgressIndicator(
              value: null,
              backgroundColor: widget.backgroundColor,
              valueColor: AlwaysStoppedAnimation<Color>(widget.color),
            );
          },
        ),
      ),
    );
  }
}
