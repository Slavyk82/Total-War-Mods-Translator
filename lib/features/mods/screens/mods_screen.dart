import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/features/mods/utils/mods_screen_controller.dart';
import 'package:twmt/features/mods/widgets/mods_list.dart';
import 'package:twmt/features/mods/widgets/mods_toolbar.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Mods screen — filterable list archetype per UI spec §7.1.
///
/// Migrated from [SfDataGrid] to the shared [FilterToolbar] + [ListRow]
/// primitives introduced in Plan 5a. Existing behaviour (search, state
/// filter pills, hidden toggle, refresh, import-local-pack, tap-to-open)
/// is preserved.
class ModsScreen extends ConsumerStatefulWidget {
  const ModsScreen({super.key});

  @override
  ConsumerState<ModsScreen> createState() => _ModsScreenState();
}

class _ModsScreenState extends ConsumerState<ModsScreen> {
  late final ModsScreenController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ModsScreenController(ref);
  }

  @override
  Widget build(BuildContext context) {
    final logger = ref.read(loggingServiceProvider);
    logger.debug('ModsScreen build() called');
    final tokens = context.tokens;
    final filteredMods = ref.watch(filteredModsProvider);
    final isInitialLoading = ref.watch(modsIsLoadingProvider);
    final modsError = ref.watch(modsErrorProvider);
    final searchQuery = ref.watch(modsSearchQueryProvider);
    final isRefreshing = ref.watch(modsLoadingStateProvider);
    final currentFilter = ref.watch(modsFilterStateProvider);
    final totalModsAsync = ref.watch(totalModsCountProvider);
    final notImportedCountAsync = ref.watch(notImportedModsCountProvider);
    final needsUpdateCountAsync = ref.watch(needsUpdateModsCountProvider);
    final showHidden = ref.watch(showHiddenModsProvider);
    final hiddenCountAsync = ref.watch(hiddenModsCountProvider);
    final pendingProjectsCountAsync =
        ref.watch(projectsWithPendingChangesCountProvider);

    return Material(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ModsToolbar(
            searchQuery: searchQuery,
            onSearchChanged: (query) {
              ref.read(modsSearchQueryProvider.notifier).setQuery(query);
            },
            onRefresh: () => _controller.handleRefresh(),
            isRefreshing: isRefreshing || isInitialLoading,
            totalMods: totalModsAsync.value ?? 0,
            filteredMods: filteredMods.length,
            currentFilter: currentFilter,
            onFilterChanged: (filter) {
              ref.read(modsFilterStateProvider.notifier).setFilter(filter);
            },
            notImportedCount: notImportedCountAsync.value ?? 0,
            needsUpdateCount: needsUpdateCountAsync.value ?? 0,
            showHidden: showHidden,
            onShowHiddenChanged: (value) {
              logger.debug('onShowHiddenChanged called with: $value');
              ref.read(showHiddenModsProvider.notifier).set(value);
            },
            hiddenCount: hiddenCountAsync.value ?? 0,
            projectsWithPendingChanges: pendingProjectsCountAsync.value ?? 0,
            onNavigateToProjects: () =>
                _controller.navigateToProjectsWithFilter(context),
            onImportLocalPack: () =>
                _controller.handleImportLocalPack(context),
          ),
          Expanded(
            child: modsError != null
                ? _ModsErrorState(
                    error: modsError,
                    onRetry: () => _controller.handleRefresh(),
                  )
                : ModsList(
                    mods: filteredMods,
                    onRowTap: (workshopId) => _controller.handleModRowTap(
                      context,
                      filteredMods,
                      workshopId,
                    ),
                    onToggleHidden: (workshopId, hide) =>
                        _controller.handleToggleHidden(workshopId, hide),
                    onForceRedownload: (packFilePath) => _controller
                        .handleForceRedownload(context, packFilePath),
                    isLoading: isInitialLoading,
                    isScanning: isRefreshing,
                    showingHidden: showHidden,
                    scanLogStream: (isRefreshing || isInitialLoading)
                        ? ref.watch(scanLogStreamProvider)
                        : null,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Error state widget for the mods screen.
class _ModsErrorState extends StatelessWidget {
  const _ModsErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 48,
              color: tokens.err,
            ),
            const SizedBox(height: 12),
            Text(
              'Failed to load mods',
              style: tokens.fontDisplay.copyWith(
                fontSize: 16,
                color: tokens.err,
                fontStyle: tokens.fontDisplayItalic
                    ? FontStyle.italic
                    : FontStyle.normal,
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
            const SizedBox(height: 16),
            _RetryButton(onRetry: onRetry),
          ],
        ),
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onRetry,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: tokens.accent,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.arrow_sync_24_regular,
                size: 14,
                color: tokens.accentFg,
              ),
              const SizedBox(width: 6),
              Text(
                'Retry',
                style: tokens.fontBody.copyWith(
                  fontSize: 12.5,
                  color: tokens.accentFg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
