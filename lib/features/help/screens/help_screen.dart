import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../models/help_section.dart';
import '../providers/help_providers.dart';
import '../widgets/help_section_content.dart';
import '../widgets/help_toc_sidebar.dart';

/// Help screen that displays the README.md documentation.
///
/// The documentation is split by sections (H2 headers) for performance —
/// only the selected section is rendered at a time. Uses the TWMT design
/// tokens (Atelier / Forge) via `context.tokens` rather than the legacy
/// FluentScaffold chrome.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final sectionsAsync = ref.watch(helpSectionsProvider);
    final selectedIndex = ref.watch(selectedSectionIndexProvider);

    return Material(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _HelpHeader(),
          Container(height: 1, color: tokens.border),
          Expanded(
            child: sectionsAsync.when(
              data: (sections) =>
                  _buildContent(context, ref, sections, selectedIndex),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _HelpError(error: error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    List<HelpSection> sections,
    int selectedIndex,
  ) {
    final tokens = context.tokens;
    if (sections.isEmpty) {
      return Center(
        child: Text(
          'No documentation available.',
          style: tokens.fontBody.copyWith(color: tokens.textDim),
        ),
      );
    }

    // Clamp selectedIndex to valid range.
    final validIndex = selectedIndex.clamp(0, sections.length - 1);
    final currentSection = sections[validIndex];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HelpTocSidebar(
          sections: sections,
          selectedIndex: validIndex,
          onSectionSelected: (index) {
            ref.read(selectedSectionIndexProvider.notifier).select(index);
          },
        ),
        Container(width: 1, color: tokens.border),
        Expanded(
          child: HelpSectionContent(
            key: ValueKey(currentSection.anchor),
            section: currentSection,
            onNavigateToSection: (anchor) {
              // Find the section with this anchor.
              final targetIndex =
                  sections.indexWhere((s) => s.anchor == anchor);
              if (targetIndex != -1) {
                ref
                    .read(selectedSectionIndexProvider.notifier)
                    .select(targetIndex);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _HelpHeader extends StatelessWidget {
  const _HelpHeader();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: tokens.panel),
      child: Row(
        children: [
          Icon(
            FluentIcons.question_circle_24_regular,
            size: 28,
            color: tokens.accent,
          ),
          const SizedBox(width: 12),
          Text(
            'Help',
            style: tokens.fontDisplay.copyWith(
              fontSize: 24,
              color: tokens.text,
              fontStyle: tokens.fontDisplayStyle,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'documentation',
            style: tokens.fontMono.copyWith(
              fontSize: 11,
              color: tokens.textDim,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpError extends StatelessWidget {
  const _HelpError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 48,
              color: tokens.err,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load documentation',
              style: tokens.fontDisplay.copyWith(
                fontSize: 16,
                color: tokens.err,
                fontStyle: tokens.fontDisplayStyle,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.textDim,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
