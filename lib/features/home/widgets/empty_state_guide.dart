import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/cards/token_card.dart';

/// Three-step onboarding guide rendered when the user has no active projects.
///
/// Each step is a [TokenCard] containing a numbered badge, a title and a CTA
/// label. Tapping a step routes to the relevant feature (Sources for steps 1
/// and 2, Projects for step 3). The row lays the three steps side by side
/// using [Expanded] children separated by a 14 px gap.
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
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String title;
  final String ctaLabel;
  final VoidCallback onTap;

  const _Step({
    required this.number,
    required this.title,
    required this.ctaLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: TokenCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.accent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$number',
                style: tokens.fontMono.copyWith(
                  fontSize: 14,
                  color: tokens.accentFg,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: tokens.fontBody.copyWith(
                fontSize: 15,
                color: tokens.text,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              ctaLabel,
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
