import 'package:flutter/material.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'token_card.dart';

/// Dashboard action card built on top of [TokenCard].
///
/// Presents an uppercase mono label, a large tabular-numerics value in the
/// display font, and a description line. When [highlight] is true AND [value]
/// is greater than zero, the card adopts the accent variant (accent background,
/// accent border, accent-tinted label + value) and renders a pulsed dot in the
/// top-right corner to signal pending user attention.
///
/// A zero [value] suppresses the highlight treatment entirely — a dashboard
/// tile reading "0 to review" must not shout for attention.
class ActionCard extends StatelessWidget {
  /// Short label rendered uppercase in the mono font (e.g. "TO REVIEW").
  final String label;

  /// Primary integer value; rendered large with tabular figures.
  final int value;

  /// Supporting description line rendered below the value.
  final String description;

  /// When true AND [value] > 0, the card renders the accent variant with a
  /// pulsed dot. When [value] is 0 the highlight treatment is skipped.
  final bool highlight;

  /// Optional tap handler. When provided, a click cursor is shown on hover.
  final VoidCallback? onTap;

  const ActionCard({
    super.key,
    required this.label,
    required this.value,
    required this.description,
    this.highlight = false,
    this.onTap,
  });

  bool get _showPulse => highlight && value > 0;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accentActive = _showPulse;

    return MouseRegion(
      cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            TokenCard(
              backgroundColor: accentActive ? tokens.accentBg : null,
              borderColor: accentActive ? tokens.accent : null,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          label.toUpperCase(),
                          style: tokens.fontMono.copyWith(
                            fontSize: 10.5,
                            letterSpacing: 1.5,
                            color:
                                accentActive ? tokens.accent : tokens.textDim,
                          ),
                        ),
                      ),
                      if (accentActive && onTap != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, right: 14),
                          child: Text(
                            t.widgets.actionCard.clickToOpen,
                            style: tokens.fontBody.copyWith(
                              fontSize: 10,
                              height: 1,
                              fontStyle: FontStyle.italic,
                              color: tokens.textDim,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$value',
                    style: tokens.fontDisplay.copyWith(
                      fontSize: 38,
                      height: 1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: accentActive ? tokens.accent : tokens.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: tokens.fontBody.copyWith(
                      fontSize: 12.5,
                      height: 1.45,
                      color: tokens.textMid,
                    ),
                  ),
                ],
              ),
            ),
            if (_showPulse)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  key: const Key('ActionCardPulseDot'),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: tokens.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: tokens.accentBg,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
