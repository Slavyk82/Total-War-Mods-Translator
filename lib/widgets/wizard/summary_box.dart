import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Semantic variants for [SummaryBox] / [SummaryLine].
enum SummarySemantics { neutral, accent, ok, warn, err }

Color _semanticColor(TwmtThemeTokens tokens, SummarySemantics s) {
  return switch (s) {
    SummarySemantics.neutral => tokens.textMid,
    SummarySemantics.accent => tokens.accent,
    SummarySemantics.ok => tokens.ok,
    SummarySemantics.warn => tokens.warn,
    SummarySemantics.err => tokens.err,
  };
}

/// Single key/value row within a [SummaryBox].
class SummaryLine {
  final String key;
  final String value;
  final SummarySemantics? semantics;

  const SummaryLine({
    required this.key,
    required this.value,
    this.semantics,
  });
}

/// Live-preview box for wizard forms (§7.5). Dashed border + uppercase
/// kicker + stacked key/value rows. Semantic color applies to the kicker
/// and border; per-[SummaryLine] semantics overrides the row value color.
class SummaryBox extends StatelessWidget {
  final String label;
  final List<SummaryLine> lines;
  final SummarySemantics semantics;

  const SummaryBox({
    super.key,
    required this.label,
    required this.lines,
    this.semantics = SummarySemantics.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fg = _semanticColor(tokens, semantics);
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: fg.withValues(alpha: 0.7),
        strokeWidth: 1,
        gap: 4,
        dashLength: 6,
        radius: tokens.radiusSm,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: tokens.fontMono.copyWith(
                fontSize: 10,
                color: fg,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        line.key,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.fontBody.copyWith(
                          fontSize: 12,
                          color: tokens.textMid,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        line.value,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.fontMono.copyWith(
                          fontSize: 12,
                          color: _semanticColor(tokens, line.semantics ?? semantics),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gap;
  final double radius;

  _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashLength,
    required this.gap,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();
    for (final metric in metrics) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashLength != dashLength ||
      oldDelegate.gap != gap ||
      oldDelegate.radius != radius;
}
