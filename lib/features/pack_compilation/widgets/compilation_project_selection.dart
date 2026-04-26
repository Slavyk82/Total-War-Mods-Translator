import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/list_row.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/project_cover_thumbnail.dart';
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
    required this.onDeselectAll,
  });

  final CompilationEditorState state;
  final AsyncValue<GameInstallation?> currentGameAsync;
  final void Function(String) onToggle;
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
    final onlySelected = ref.watch(showOnlySelectedProjectsProvider);

    return Container(
      decoration: BoxDecoration(
        color: tokens.panel,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - title + pills on the left, responsive search field
          // stretching to fill the remaining width on the right.
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  FluentIcons.folder_24_regular,
                  color: tokens.accent,
                ),
                const SizedBox(width: 8),
                Text(
                  t.packCompilation.labels.selectProjects,
                  style: tokens.fontDisplay.copyWith(
                    fontSize: 18,
                    color: tokens.text,
                    fontStyle: tokens.fontDisplayItalic
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
                const SizedBox(width: 8),
                _SelectionCountPill(
                  count: state.selectedProjectIds.length,
                  onClear: onDeselectAll,
                ),
                const SizedBox(width: 8),
                FilterPill(
                  label: t.packCompilation.hints.showOnlySelected,
                  selected: onlySelected,
                  count: onlySelected
                      ? state.selectedProjectIds.length
                      : null,
                  tooltip: t.packCompilation.hints.showOnlySelectedTooltip,
                  onToggle: () => ref
                      .read(showOnlySelectedProjectsProvider.notifier)
                      .update((v) => !v),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ListSearchField(
                    width: double.infinity,
                    hintText: t.packCompilation.hints.searchProjects,
                    value: filter,
                    onChanged: (value) => ref
                        .read(projectFilterProvider.notifier)
                        .setFilter(value),
                    onClear: () =>
                        ref.read(projectFilterProvider.notifier).clear(),
                  ),
                ),
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
                          if (filter.isNotEmpty || onlySelected) {
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
                              height: null,
                              columns: const [
                                ListRowColumn.fixed(80),
                                ListRowColumn.flex(3),
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
                                        style: tokens.fontBody.copyWith(
                                          color: tokens.text,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${projectInfo.translatedUnits}/'
                                        '${projectInfo.totalUnits} · '
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
                            t.packCompilation.hints.failedToLoadProjects,
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
            t.packCompilation.hints.noProjectsFound,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: tokens.textMid,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t.packCompilation.hints.tryDifferentSearch,
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
            t.packCompilation.hints.selectGameFirst,
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
            t.packCompilation.hints.selectLanguageFirst,
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
            t.packCompilation.hints.noProjectsWithLanguage,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: tokens.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

/// Accent-filled badge showing the current count of selected projects.
///
/// Sized to match the filter pills used in the translation editor (12 px
/// horizontal / 5 px vertical padding, `tokens.radiusPill`, 12 pt label).
/// When at least one project is selected, a trailing close icon makes the
/// entire pill tappable to clear the selection.
class _SelectionCountPill extends StatelessWidget {
  final int count;
  final VoidCallback onClear;

  const _SelectionCountPill({
    required this.count,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final canClear = count > 0;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.accent,
        borderRadius: BorderRadius.circular(tokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t.packCompilation.hints.selectedCount(count: count),
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: tokens.accentFg,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (canClear) ...[
            const SizedBox(width: 6),
            Icon(Icons.close, size: 12, color: tokens.accentFg),
          ],
        ],
      ),
    );
    if (!canClear) return pill;
    return Tooltip(
      message: t.packCompilation.hints.clearSelection,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onClear, child: pill),
      ),
    );
  }
}
