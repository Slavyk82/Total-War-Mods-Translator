import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'token_card.dart';

/// Visual state of a [WorkflowCard] in the Home dashboard's four-step pipeline.
///
/// - [done]: the step has been completed — the number badge is replaced by a
///   check mark and the title/state label use the success color.
/// - [current]: the step the user should act on next — rendered with the
///   accent background and border to draw attention.
/// - [next]: an upcoming step that is not yet actionable — the card is dimmed
///   and the call-to-action row is hidden.
enum WorkflowCardState { done, current, next }

/// Dashboard card representing one step of the translation workflow pipeline.
///
/// Built on top of [TokenCard]; the appearance is derived entirely from the
/// active theme tokens via `context.tokens`, so the card re-themes itself when
/// the app switches between Atelier and Forge.
class WorkflowCard extends StatelessWidget {
  /// Ordinal of the step (1-based). Replaced by a check mark when
  /// [state] is [WorkflowCardState.done].
  final int stepNumber;

  /// Short human-readable title for the step (e.g. "Translate").
  final String title;

  /// Status pill rendered uppercase in the mono font (e.g. "IN PROGRESS").
  final String stateLabel;

  /// Large numeric metric associated with this step (e.g. active project
  /// count). Rendered with tabular figures in the display font.
  final String metric;

  /// Supporting description rendered below the [metric].
  final String subtitle;

  /// Call-to-action label shown in the bottom row. Hidden entirely when
  /// [state] is [WorkflowCardState.next].
  final String cta;

  /// Current visual state of the card. See [WorkflowCardState].
  final WorkflowCardState state;

  /// Optional tap handler. When provided, the card shows a click cursor on
  /// hover and invokes this callback when tapped.
  final VoidCallback? onTap;

  const WorkflowCard({
    super.key,
    required this.stepNumber,
    required this.title,
    required this.stateLabel,
    required this.metric,
    required this.subtitle,
    required this.cta,
    required this.state,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final Color bg;
    final Color border;
    double opacity = 1.0;
    switch (state) {
      case WorkflowCardState.done:
        bg = tokens.panel;
        border = tokens.border;
        break;
      case WorkflowCardState.current:
        bg = tokens.accentBg;
        border = tokens.accent;
        break;
      case WorkflowCardState.next:
        bg = tokens.panel2;
        border = tokens.border;
        opacity = 0.65;
        break;
    }

    final numberBg = switch (state) {
      WorkflowCardState.done => tokens.okBg,
      WorkflowCardState.current => tokens.accent,
      WorkflowCardState.next => Colors.transparent,
    };
    final numberFg = switch (state) {
      WorkflowCardState.done => tokens.ok,
      WorkflowCardState.current => tokens.accentFg,
      WorkflowCardState.next => tokens.textDim,
    };

    return MouseRegion(
      cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: opacity,
          child: TokenCard(
            backgroundColor: bg,
            borderColor: border,
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: numberBg,
                        shape: BoxShape.circle,
                        border: state == WorkflowCardState.next
                            ? Border.all(color: tokens.border)
                            : null,
                      ),
                      child: Text(
                        state == WorkflowCardState.done ? '✓' : '$stepNumber',
                        style: tokens.fontMono.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: numberFg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      title,
                      style: tokens.fontDisplay.copyWith(
                        fontSize: 16,
                        color: state == WorkflowCardState.current
                            ? tokens.text
                            : tokens.textMid,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  stateLabel.toUpperCase(),
                  style: tokens.fontMono.copyWith(
                    fontSize: 10.5,
                    letterSpacing: 1.3,
                    color: switch (state) {
                      WorkflowCardState.current => tokens.accent,
                      WorkflowCardState.done => tokens.ok,
                      WorkflowCardState.next => tokens.textDim,
                    },
                  ),
                ),
                Text(
                  metric,
                  style: tokens.fontDisplay.copyWith(
                    fontSize: 32,
                    height: 1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: state == WorkflowCardState.current
                        ? tokens.accent
                        : tokens.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: tokens.fontBody.copyWith(
                    fontSize: 12.5,
                    height: 1.5,
                    color: tokens.textDim,
                  ),
                ),
                if (state != WorkflowCardState.next)
                  Padding(
                    key: const Key('WorkflowCardCTA'),
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Text(
                          cta,
                          style: tokens.fontBody.copyWith(
                            fontSize: 12,
                            color: tokens.accent,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.arrow_forward, size: 14, color: tokens.accent),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
