import 'package:flutter/material.dart';

import '../../theme/twmt_theme_tokens.dart';

/// Circular numbered chip used as a waypoint on a pipeline timeline rail.
///
/// Shared between the main navigation sidebar and the translation-editor
/// inner sidebar so the execution order badges read identically in both
/// places. The [primary] variant fills solid accent — used for the
/// currently-active workflow step in the main sidebar, and for the main
/// call-to-action (step 1) in the editor sidebar. The outlined variant
/// matches the inactive workflow-card look for steps that follow.
class StepBadge extends StatelessWidget {
  final int step;
  final bool primary;

  const StepBadge({
    super.key,
    required this.step,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bg = primary ? tokens.accent : tokens.panel2;
    final fg = primary ? tokens.accentFg : tokens.textDim;
    final borderColor = primary ? tokens.accent : tokens.border;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Text(
        '$step',
        style: tokens.fontMono.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
          height: 1,
        ),
      ),
    );
  }
}

/// Left-side gutter for a pipeline row — a thin vertical line that threads
/// through successive pipeline steps, broken by a [StepBadge] at each step's
/// anchor row.
///
/// Pair with [pipelineRow] so the rail stretches to match the content
/// height via [IntrinsicHeight]. Set [lineAbove] to `false` on the first
/// row and [lineBelow] to `false` on the last row so the line doesn't
/// bleed past the first/last badges.
class TimelineRail extends StatelessWidget {
  /// 1-based step number. When non-null, renders a numbered [StepBadge] at
  /// the row's vertical centre and the line gaps around it.
  final int? step;

  /// Styles the badge as the active / primary step.
  final bool primary;

  final bool lineAbove;
  final bool lineBelow;

  const TimelineRail({
    super.key,
    this.step,
    this.primary = false,
    this.lineAbove = true,
    this.lineBelow = true,
  });

  /// Total gutter width — this is the column the rail occupies in the host
  /// row, to the left of the content.
  static const double width = 28;

  // Radius taken around the [StepBadge] when gapping the connecting line so
  // it doesn't kiss the badge border. Keep in sync with [StepBadge]'s size.
  static const double _badgeGap = 13;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _RailPainter(
                color: tokens.border,
                lineAbove: lineAbove,
                lineBelow: lineBelow,
                hasBadge: step != null,
                badgeGap: _badgeGap,
              ),
            ),
          ),
          if (step != null)
            Positioned.fill(
              child: Center(
                child: StepBadge(step: step!, primary: primary),
              ),
            ),
        ],
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  final Color color;
  final bool lineAbove;
  final bool lineBelow;
  final bool hasBadge;
  final double badgeGap;

  const _RailPainter({
    required this.color,
    required this.lineAbove,
    required this.lineBelow,
    required this.hasBadge,
    required this.badgeGap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final topEnd = hasBadge ? cy - badgeGap : size.height;
    final bottomStart = hasBadge ? cy + badgeGap : 0.0;
    if (lineAbove) {
      canvas.drawLine(Offset(cx, 0), Offset(cx, topEnd), paint);
    }
    if (lineBelow) {
      canvas.drawLine(Offset(cx, bottomStart), Offset(cx, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RailPainter old) =>
      old.color != color ||
      old.lineAbove != lineAbove ||
      old.lineBelow != lineBelow ||
      old.hasBadge != hasBadge ||
      old.badgeGap != badgeGap;
}

/// Wraps a pipeline row's [child] with a [TimelineRail] slot on the left.
/// Uses [IntrinsicHeight] so the rail stretches to match the content height
/// — the connecting line and badge therefore centre on the row regardless
/// of what the child renders.
Widget pipelineRow({
  required TimelineRail rail,
  required Widget child,
  Key? key,
}) {
  return IntrinsicHeight(
    key: key,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [rail, Expanded(child: child)],
    ),
  );
}
