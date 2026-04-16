import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/home/providers/action_grid_providers.dart';
import 'package:twmt/features/home/providers/workflow_providers.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/cards/workflow_card.dart';

/// Four-step workflow ribbon on the Home dashboard.
///
/// Renders the Detect / Translate / Compile / Publish pipeline as a row of
/// four [WorkflowCard]s separated by arrow icons. Each card derives its state
/// (done / current / next) from primitive Riverpod counters, and tapping a
/// card navigates to the associated feature route.
class WorkflowRibbon extends ConsumerWidget {
  const WorkflowRibbon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final mods = ref.watch(modsDiscoveredCountProvider).value ?? 0;
    final modUpdates = ref.watch(modsWithUpdatesCountProvider).value ?? 0;
    final projects = ref.watch(activeProjectsCountProvider).value ?? 0;
    final toReview = ref.watch(projectsToReviewCountProvider).value ?? 0;
    final ready = ref.watch(projectsReadyToCompileCountProvider).value ?? 0;
    final awaitingPub =
        ref.watch(packsAwaitingPublishCountProvider).value ?? 0;

    WorkflowCardState stateFor(int step) {
      if (step == 1) {
        return mods > 0 ? WorkflowCardState.done : WorkflowCardState.current;
      }
      if (step == 2) {
        if (projects == 0) return WorkflowCardState.next;
        return projects > 0 && ready < projects
            ? WorkflowCardState.current
            : WorkflowCardState.done;
      }
      if (step == 3) {
        if (ready == 0) return WorkflowCardState.next;
        return WorkflowCardState.current;
      }
      return awaitingPub == 0
          ? WorkflowCardState.next
          : WorkflowCardState.current;
    }

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
          state: stateFor(1),
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
          state: stateFor(2),
          onTap: () => context.go(AppRoutes.projects),
        ),
      ),
      arrow(),
      Expanded(
        child: WorkflowCard(
          stepNumber: 3,
          title: 'Compile',
          stateLabel: ready > 0 ? '$ready ready' : 'Waiting',
          metric: '$ready',
          subtitle: 'packs to generate when ready',
          cta: 'Compile',
          state: stateFor(3),
          onTap: () => context.go(AppRoutes.packCompilation),
        ),
      ),
      arrow(),
      Expanded(
        child: WorkflowCard(
          stepNumber: 4,
          title: 'Publish',
          stateLabel: awaitingPub > 0 ? '$awaitingPub waiting' : 'Waiting',
          metric: '$awaitingPub',
          subtitle: 'compiled packs ready for Workshop',
          cta: 'Publish',
          state: stateFor(4),
          onTap: () => context.go(AppRoutes.steamPublish),
        ),
      ),
    ]);
  }
}
