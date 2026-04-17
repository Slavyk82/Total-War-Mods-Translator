import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Full-width meta-bandeau for detail screens (§7.2).
///
/// Lays out cover (110×68 typically) + title + subtitle segments (font-mono,
/// separator "·" auto-inserted between non-empty children) + optional
/// description + actions anchored to the right.
class DetailMetaBanner extends StatelessWidget {
  final Widget cover;
  final String title;
  final List<Widget> subtitle;
  final String? description;
  final List<Widget> actions;

  const DetailMetaBanner({
    super.key,
    required this.cover,
    required this.title,
    required this.subtitle,
    this.description,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      decoration: BoxDecoration(
        color: tokens.panel2,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          cover,
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: tokens.fontDisplay.copyWith(
                    fontSize: 20,
                    color: tokens.text,
                    fontStyle: tokens.fontDisplayItalic
                        ? FontStyle.italic
                        : FontStyle.normal,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                DefaultTextStyle(
                  style: tokens.fontMono.copyWith(
                    fontSize: 11,
                    color: tokens.textDim,
                    letterSpacing: 0.4,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: _intersperseSeparators(
                      subtitle,
                      Text('·', style: tokens.fontMono.copyWith(color: tokens.textFaint)),
                    ),
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    description!,
                    key: const Key('detail-meta-banner-description'),
                    style: tokens.fontBody.copyWith(
                      fontSize: 13,
                      color: tokens.textMid,
                      height: 1.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  actions[i],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  static List<Widget> _intersperseSeparators(List<Widget> children, Widget sep) {
    if (children.isEmpty) return const [];
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) out.add(sep);
      out.add(children[i]);
    }
    return out;
  }
}
