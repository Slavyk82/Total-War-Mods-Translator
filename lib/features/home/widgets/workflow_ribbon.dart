import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/home/providers/action_grid_providers.dart';
import 'package:twmt/features/home/providers/workflow_providers.dart';
import 'package:twmt/i18n/strings.g.dart';
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
    final inProgress =
        ref.watch(projectsInProgressCountProvider).value ?? 0;
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
          title: t.home.workflow.detect.title,
          stateLabel: mods > 0 ? t.home.workflow.detect.done : t.home.workflow.detect.startHere,
          metric: '$mods',
          subtitle: '${mods > 0 ? t.home.workflow.detect.modsDiscovered : t.home.workflow.detect.noModsYet}'
              '${modUpdates > 0 ? t.home.workflow.detect.withUpdates(count: modUpdates) : ''}',
          cta: t.home.workflow.detect.cta,
          state: WorkflowCardState.current,
          onTap: () => context.go(AppRoutes.mods),
        ),
      ),
      arrow(),
      Expanded(
        child: WorkflowCard(
          stepNumber: 2,
          title: t.home.workflow.translate.title,
          stateLabel: inProgress > 0
              ? t.home.workflow.translate.inProgress
              : (projects > 0 ? t.home.workflow.translate.idle : t.home.workflow.translate.waiting),
          metric: '$inProgress',
          subtitle:
              '${t.home.workflow.translate.subtitle}${toReview > 0 ? t.home.workflow.translate.toReview(count: toReview) : ''}',
          cta: t.home.workflow.translate.cta,
          state: WorkflowCardState.current,
          onTap: () => context.go(AppRoutes.projects),
        ),
      ),
      arrow(),
      Expanded(
        child: WorkflowCard(
          stepNumber: 3,
          title: t.home.workflow.publish.title,
          stateLabel: awaitingPub > 0
              ? t.home.workflow.publish.waitingCount(count: awaitingPub)
              : t.home.workflow.publish.waiting,
          metric: '$awaitingPub',
          subtitle: t.home.workflow.publish.subtitle,
          cta: t.home.workflow.publish.cta,
          state: WorkflowCardState.current,
          onTap: () => context.go(AppRoutes.steamPublish),
        ),
      ),
    ]);
  }
}
