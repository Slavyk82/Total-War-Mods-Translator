import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/home/providers/action_grid_providers.dart';
import 'package:twmt/features/home/providers/workflow_providers.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/widgets/cards/action_card.dart';

/// "Needs attention" action grid on the Home dashboard.
///
/// Renders five [ActionCard]s in a row, each backed by a primitive Riverpod
/// counter. Every tile uses the accent highlight treatment when its count is
/// greater than zero — the whole grid is "things that need attention", so a
/// non-zero count always warrants the visual nudge. Tapping any card
/// navigates to the relevant feature route with a query filter where
/// appropriate.
class ActionGrid extends ConsumerWidget {
  const ActionGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toReview = ref.watch(projectsToReviewCountProvider).value ?? 0;
    final ready = ref.watch(projectsReadyToCompileCountProvider).value ?? 0;
    final exportOutdated =
        ref.watch(projectsExportOutdatedCountProvider).value ?? 0;
    final updates = ref.watch(modsWithUpdatesCountProvider).value ?? 0;
    final awaiting = ref.watch(packsAwaitingPublishCountProvider).value ?? 0;

    return Row(children: [
      Expanded(
        child: ActionCard(
          label: t.home.actionGrid.toReview.label,
          value: toReview,
          description: t.home.actionGrid.toReview.description,
          highlight: true,
          onTap: () =>
              context.go('${AppRoutes.projects}?filter=needs-review'),
        ),
      ),
      const SizedBox(width: 20),
      Expanded(
        child: ActionCard(
          label: t.home.actionGrid.readyToCompile.label,
          value: ready,
          description: t.home.actionGrid.readyToCompile.description,
          highlight: true,
          onTap: () =>
              context.go('${AppRoutes.projects}?filter=ready-to-compile'),
        ),
      ),
      const SizedBox(width: 20),
      Expanded(
        child: ActionCard(
          label: t.home.actionGrid.exportOutdated.label,
          value: exportOutdated,
          description: t.home.actionGrid.exportOutdated.description,
          highlight: true,
          onTap: () =>
              context.go('${AppRoutes.projects}?filter=export-outdated'),
        ),
      ),
      const SizedBox(width: 20),
      Expanded(
        child: ActionCard(
          label: t.home.actionGrid.modUpdates.label,
          value: updates,
          description: t.home.actionGrid.modUpdates.description,
          highlight: true,
          onTap: () => context.go('${AppRoutes.mods}?filter=needs-update'),
        ),
      ),
      const SizedBox(width: 20),
      Expanded(
        child: ActionCard(
          label: t.home.actionGrid.readyToPublish.label,
          value: awaiting,
          description: t.home.actionGrid.readyToPublish.description,
          highlight: true,
          onTap: () => context.go(AppRoutes.steamPublish),
        ),
      ),
    ]);
  }
}
