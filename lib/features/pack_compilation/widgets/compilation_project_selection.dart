import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/list_row.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/project_cover_thumbnail.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../../../models/domain/game_installation.dart';
import '../../../widgets/common/fluent_spinner.dart' hide FluentProgressBar;
import '../providers/pack_compilation_providers.dart';

/// Section for selecting projects to include in compilation.
class CompilationProjectSelectionSection extends ConsumerWidget {
  const CompilationProjectSelectionSection({
    super.key,
    required this.state,
    required this.currentGameAsync,
    required this.onToggle,
    required this.onSelectAll,
    required this.onDeselectAll,
  });

  final CompilationEditorState state;
  final AsyncValue<GameInstallation?> currentGameAsync;
  final void Function(String) onToggle;
  final void Function(List<String>) onSelectAll;
  final VoidCallback onDeselectAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final gameInstallation = currentGameAsync.asData?.value;
    final filterParams = ProjectFilterParams(
      gameInstallationId: gameInstallation?.id,
      languageId: state.selectedLanguageId,
    );

    final projectsAsync = ref.watch(filteredProjectsProvider(filterParams));
    final filter = ref.watch(projectFilterProvider);

    return Container(
      decoration: BoxDecoration(
        color: tokens.panel,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - uses Wrap for responsive layout
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FluentIcons.folder_24_regular,
                      color: tokens.accent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Select Projects',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: tokens.accentBg,
                        borderRadius: BorderRadius.circular(tokens.radiusPill),
                      ),
                      child: Text(
                        '${state.selectedProjectIds.length} selected',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                // Filter field
                ListSearchField(
                  width: 200,
                  hintText: 'Search projects...',
                  value: filter,
                  onChanged: (value) => ref
                      .read(projectFilterProvider.notifier)
                      .setFilter(value),
                  onClear: () =>
                      ref.read(projectFilterProvider.notifier).clear(),
                ),
                projectsAsync.whenData((projects) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SmallTextButton(
                        label: 'Select all',
                        onTap: () =>
                            onSelectAll(projects.map((p) => p.id).toList()),
                      ),
                      const SizedBox(width: 8),
                      SmallTextButton(
                        label: 'Deselect all',
                        onTap: onDeselectAll,
                      ),
                    ],
                  );
                }).value ?? const SizedBox.shrink(),
              ],
            ),
          ),
          const Divider(height: 1),
          // Project list
          Expanded(
            child: gameInstallation == null
                ? _buildSelectGameMessage(theme, tokens)
                : state.selectedLanguageId == null
                    ? _buildSelectLanguageMessage(theme, tokens)
                    : projectsAsync.when(
                        data: (projects) {
                        if (projects.isEmpty) {
                          if (filter.isNotEmpty) {
                            return _buildNoFilterResults(theme, tokens);
                          }
                          return _buildNoProjectsMessage(theme, tokens);
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: projects.length,
                          itemBuilder: (context, index) {
                            final projectInfo = projects[index];
                            final isSelected = state.selectedProjectIds
                                .contains(projectInfo.id);
                            return ListRow(
                              selected: isSelected,
                              onTap: () => onToggle(projectInfo.id),
                              columns: const [
                                ListRowColumn.fixed(80),
                                ListRowColumn.flex(3),
                                ListRowColumn.fixed(48),
                              ],
                              children: [
                                ProjectCoverThumbnail(
                                  imageUrl: projectInfo.imageUrl,
                                  isGameTranslation:
                                      projectInfo.project.isGameTranslation,
                                  gameCode: gameInstallation.gameCode,
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        projectInfo.displayName,
                                        style: TextStyle(
                                          color: tokens.text,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${projectInfo.translatedUnits}/'
                                        '${projectInfo.totalUnits} translated'
                                        ' · '
                                        '${projectInfo.progressPercent.toStringAsFixed(0)}%',
                                        style: tokens.fontMono.copyWith(
                                          fontSize: 12,
                                          color: tokens.textDim,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Checkbox(
                                  value: isSelected,
                                  onChanged: (_) => onToggle(projectInfo.id),
                                ),
                              ],
                            );
                          },
                        );
                      },
                        loading: () => const Center(
                          child: FluentSpinner(),
                        ),
                        error: (error, _) => Center(
                          child: Text(
                            'Failed to load projects',
                            style: TextStyle(color: tokens.err),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoFilterResults(ThemeData theme, TwmtThemeTokens tokens) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.search_24_regular,
            size: 48,
            color: tokens.textFaint,
          ),
          const SizedBox(height: 12),
          Text(
            'No projects found',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: tokens.textMid,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try a different search term',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectGameMessage(ThemeData theme, TwmtThemeTokens tokens) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.games_24_regular,
            size: 48,
            color: tokens.textFaint,
          ),
          const SizedBox(height: 12),
          Text(
            'Select a game in the sidebar first',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: tokens.textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectLanguageMessage(ThemeData theme, TwmtThemeTokens tokens) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.translate_24_regular,
            size: 48,
            color: tokens.textFaint,
          ),
          const SizedBox(height: 12),
          Text(
            'Select a language first',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: tokens.textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoProjectsMessage(ThemeData theme, TwmtThemeTokens tokens) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.folder_24_regular,
            size: 48,
            color: tokens.textFaint,
          ),
          const SizedBox(height: 12),
          Text(
            'No projects with translations in this language',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: tokens.textDim,
            ),
          ),
        ],
      ),
    );
  }
}
