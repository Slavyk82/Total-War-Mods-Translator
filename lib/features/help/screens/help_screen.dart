import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../models/help_section.dart';
import '../providers/help_providers.dart';
import '../widgets/help_section_content.dart';
import '../widgets/help_toc_sidebar.dart';

/// Help screen that displays the README.md documentation.
///
/// The documentation is split by sections (H2 headers) for performance.
/// Only the selected section is rendered at a time.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sectionsAsync = ref.watch(helpSectionsProvider);
    final selectedIndex = ref.watch(selectedSectionIndexProvider);

    return FluentScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(theme),
          const Divider(height: 1),
          // Content
          Expanded(
            child: sectionsAsync.when(
              data: (sections) => _buildContent(
                context,
                ref,
                sections,
                selectedIndex,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => _buildError(theme, error.toString()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          Icon(
            FluentIcons.question_circle_24_regular,
            size: 32,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Text(
            'Help',
            style: theme.textTheme.headlineLarge,
          ),
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme, String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            size: 48,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load documentation: $error',
            style: theme.textTheme.bodyLarge,
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
    if (sections.isEmpty) {
      return const Center(
        child: Text('No documentation available.'),
      );
    }

    // Clamp selectedIndex to valid range
    final validIndex = selectedIndex.clamp(0, sections.length - 1);
    final currentSection = sections[validIndex];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // TOC Sidebar
        HelpTocSidebar(
          sections: sections,
          selectedIndex: validIndex,
          onSectionSelected: (index) {
            ref.read(selectedSectionIndexProvider.notifier).select(index);
          },
        ),
        // Vertical divider
        Container(
          width: 1,
          color: Theme.of(context).dividerColor,
        ),
        // Section content
        Expanded(
          child: HelpSectionContent(
            key: ValueKey(currentSection.anchor),
            section: currentSection,
            onNavigateToSection: (anchor) {
              // Find the section with this anchor
              final targetIndex = sections.indexWhere(
                (s) => s.anchor == anchor,
              );
              if (targetIndex != -1) {
                ref.read(selectedSectionIndexProvider.notifier).select(targetIndex);
              }
            },
          ),
        ),
      ],
    );
  }
}
