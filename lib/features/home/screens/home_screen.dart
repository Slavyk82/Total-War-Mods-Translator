import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/home/providers/workflow_providers.dart';
import 'package:twmt/features/home/widgets/action_grid.dart';
import 'package:twmt/features/home/widgets/empty_state_guide.dart';
import 'package:twmt/features/home/widgets/home_page_header.dart';
import 'package:twmt/features/home/widgets/workflow_ribbon.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';

/// Home/Dashboard screen.
///
/// Composes the redesigned Home dashboard widgets (header, workflow ribbon,
/// action grid) and switches to the [EmptyStateGuide] when there are no
/// active projects for the current game.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectCountAsync = ref.watch(activeProjectsCountProvider);
    final projects = projectCountAsync.value ?? 0;
    final isEmpty = projects == 0;

    return FluentScaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const HomePageHeader(),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SectionLabel('Workflow'),
                  const SizedBox(height: 10),
                  const WorkflowRibbon(),
                  const SizedBox(height: 28),
                  const _SectionLabel('Needs attention'),
                  const SizedBox(height: 10),
                  const ActionGrid(),
                  const SizedBox(height: 28),
                  if (isEmpty) const EmptyStateGuide(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Display-font accent label used above each dashboard section.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Text(
      text,
      style: tokens.fontDisplay.copyWith(
        fontSize: 18,
        color: tokens.accent,
      ),
    );
  }
}
