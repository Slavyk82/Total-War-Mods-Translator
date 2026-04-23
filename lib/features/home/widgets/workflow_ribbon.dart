import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/home/providers/action_grid_providers.dart';
import 'package:twmt/features/home/providers/workflow_providers.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/cards/workflow_card.dart';

/// Three-step workflow ribbon on the Home dashboard.
///
/// Renders the Detect / Translate / Publish pipeline as a row of three
/// [WorkflowCard]s separated by arrow icons. All cards use the
/// [WorkflowCardState.current] visual style; only the textual labels and
/// metrics reflect the underlying Riverpod counters.
class WorkflowRibbon extends ConsumerWidget {
  const WorkflowRibbon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final mods = ref.watch(modsDiscoveredCountProvider).value ?? 0;
    final modUpdates = ref.watch(modsWithUpdatesCountProvider).value ?? 0;
    final projects = ref.watch(activeProjectsCountProvider).value ?? 0;
    final toReview = ref.watch(projectsToReviewCountProvider).value ?? 0;
    final awaitingPub =
        ref.watch(packsAwaitingPublishCountProvider).value ?? 0;

    Widget arrow() => SizedBox(
          width: 20,
          child: Icon(Icons.arrow_forward, color: tokens.textFaint, size: 18),
        );

    return Row(children: [
      Expanded(
        child: WorkflowCard(
          stepNumber: 1,
          title: 'Detect',
          stateLabel: mods > 0 ? 'Done' : 'Start here',
          metric: '$mods',
          subtitle: '${mods > 0 ? 'mods discovered' : 'no mods yet'}'
              '${modUpdates > 0 ? ' · $modUpdates with updates' : ''}',
          cta: 'View mods',
          state: WorkflowCardState.current,
          onTap: () => context.go(AppRoutes.mods),
        ),
      ),
      arrow(),
      Expanded(
        child: WorkflowCard(
          stepNumber: 2,
          title: 'Translate',
          stateLabel: projects > 0 ? 'In progress' : 'Waiting',
          metric: '$projects',
          subtitle:
              'active projects${toReview > 0 ? ' · $toReview to review' : ''}',
          cta: 'Open projects',
          state: WorkflowCardState.current,
          onTap: () => context.go(AppRoutes.projects),
        ),
      ),
      arrow(),
      Expanded(
        child: WorkflowCard(
          stepNumber: 3,
          title: 'Publish',
          stateLabel: awaitingPub > 0 ? '$awaitingPub waiting' : 'Waiting',
          metric: '$awaitingPub',
          subtitle: 'compiled packs ready for Workshop',
          cta: 'Publish',
          state: WorkflowCardState.current,
          onTap: () => context.go(AppRoutes.steamPublish),
        ),
      ),
    ]);
  }
}
