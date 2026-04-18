import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/cards/token_card.dart';

/// Five-step onboarding guide rendered when the user has no active projects.
///
/// The first three steps are clickable and route to the feature that makes the
/// step actionable. The last two (Compile, Publish) are rendered greyed and
/// non-clickable so a brand-new user sees the full journey on first launch.
class EmptyStateGuide extends StatelessWidget {
  const EmptyStateGuide({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Step(
            number: 1,
            title: 'Detect your mods in Sources',
            ctaLabel: 'Go to Sources',
            onTap: () => context.go(AppRoutes.mods),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _Step(
            number: 2,
            title: 'Create a project from a mod',
            ctaLabel: 'Open Sources',
            onTap: () => context.go(AppRoutes.mods),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _Step(
            number: 3,
            title: 'Translate the units',
            ctaLabel: 'Open Projects',
            onTap: () => context.go(AppRoutes.projects),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _Step(
            number: 4,
            title: 'Compile your pack',
            ctaLabel: null,
            onTap: null,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _Step(
            number: 5,
            title: 'Publish on Steam Workshop',
            ctaLabel: null,
            onTap: null,
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String title;
  final String? ctaLabel;
  final VoidCallback? onTap;

  const _Step({
    required this.number,
    required this.title,
    required this.ctaLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final disabled = onTap == null;
    final content = TokenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: disabled ? tokens.panel2 : tokens.accent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: tokens.fontMono.copyWith(
                fontSize: 14,
                color: disabled ? tokens.textFaint : tokens.accentFg,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: tokens.fontBody.copyWith(
              fontSize: 15,
              color: disabled ? tokens.textDim : tokens.text,
            ),
          ),
          const SizedBox(height: 10),
          if (ctaLabel != null)
            Text(
              ctaLabel!,
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.accent,
              ),
            )
          else
            const SizedBox(height: 16),
        ],
      ),
    );
    return GestureDetector(
      onTap: onTap,
      child: disabled ? Opacity(opacity: 0.5, child: content) : content,
    );
  }
}
