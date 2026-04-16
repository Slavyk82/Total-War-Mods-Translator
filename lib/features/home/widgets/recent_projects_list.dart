import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/home/models/next_project_action.dart';
import 'package:twmt/features/home/providers/home_providers.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/cards/token_card.dart';

/// Recent projects dashboard list.
///
/// Reads [recentProjectsProvider] and renders one [TokenCard] row per
/// project. Each row displays the project name, the translated percentage
/// and a `_NextActionBadge` that summarises the contextual next action.
/// Rows route to the project detail screen on tap.
class RecentProjectsList extends ConsumerWidget {
  const RecentProjectsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final async = ref.watch(recentProjectsProvider);

    // Keep loading/error surfaces as a silent reserved slot: the Home
    // dashboard already surfaces status through `homeStatusProvider`, so the
    // recent-projects panel stays quiet while it settles.
    final list = async.value ?? const [];

    return Column(
      children: [
        for (final p in list)
          // The row's marker key lives on the inner TokenCard — placing it
          // on the Padding (a direct Column child) would violate the
          // "direct children must have unique keys" rule since every row
          // shares the same logical tag.
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TokenCard(
              key: const Key('RecentProjectsRow'),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              child: Row(children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        context.go(AppRoutes.projectDetail(p.project.id)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.project.name,
                          style: tokens.fontBody.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: tokens.text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${p.translatedPct}% translated',
                          style: tokens.fontMono.copyWith(
                            fontSize: 11.5,
                            color: tokens.textDim,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                _NextActionBadge(action: p.action),
              ]),
            ),
          ),
      ],
    );
  }
}

/// Colored pill summarising the next contextual action on a project.
///
/// Uses the token palette's `ok` slots when the project is ready to
/// compile (success affordance), and the `accent` slots otherwise (a call
/// to action for review / translate / continue).
class _NextActionBadge extends StatelessWidget {
  final NextProjectAction action;
  const _NextActionBadge({required this.action});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isDone = action == NextProjectAction.readyToCompile;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDone ? tokens.okBg : tokens.accentBg,
        border: Border.all(
          color: isDone ? Colors.transparent : tokens.accent,
        ),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: Text(
        action.label,
        style: tokens.fontBody.copyWith(
          fontSize: 11.5,
          color: isDone ? tokens.ok : tokens.accent,
        ),
      ),
    );
  }
}
