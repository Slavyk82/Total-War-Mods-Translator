import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/features/mods/widgets/detected_mods_datagrid.dart';
import 'package:twmt/features/mods/widgets/mods_toolbar.dart';
import 'package:twmt/features/mods/utils/mods_screen_controller.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Mods screen displaying detected mods with filtering and project creation
///
/// This screen follows the single responsibility principle by delegating:
/// - Business logic orchestration to [ModsScreenController]
/// - Project creation to [ModsProjectService]
/// - Dialog workflows to [ModsDialogHelper]
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
    LoggingService.instance.debug('ModsScreen build() called');
    final theme = Theme.of(context);
    final filteredMods = ref.watch(filteredModsProvider);
    LoggingService.instance.debug('filteredMods count: ${filteredMods.length}');
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
    final pendingProjectsCountAsync = ref.watch(projectsWithPendingChangesCountProvider);

    return FluentScaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(theme),
            const SizedBox(height: 24),
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
                LoggingService.instance.debug('onShowHiddenChanged called with: $value');
                ref.read(showHiddenModsProvider.notifier).set(value);
                LoggingService.instance.debug('showHiddenModsProvider.set() done');
              },
              hiddenCount: hiddenCountAsync.value ?? 0,
              projectsWithPendingChanges: pendingProjectsCountAsync.value ?? 0,
              onNavigateToProjects: () => _controller.navigateToProjectsWithFilter(context),
              onImportLocalPack: () => _controller.handleImportLocalPack(context),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: modsError != null
                  ? _ModsErrorState(
                      error: modsError,
                      onRetry: () => _controller.handleRefresh(),
                    )
                  : DetectedModsDataGrid(
                      mods: filteredMods,
                      onRowTap: (workshopId) =>
                          _controller.handleModRowTap(context, filteredMods, workshopId),
                      onToggleHidden: (workshopId, hide) =>
                          _controller.handleToggleHidden(workshopId, hide),
                      onForceRedownload: (packFilePath) =>
                          _controller.handleForceRedownload(context, packFilePath),
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
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: [
        Icon(
          FluentIcons.cube_24_regular,
          size: 32,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Text(
          'Mods',
          style: theme.textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Error state widget for the mods screen
class _ModsErrorState extends StatelessWidget {
  const _ModsErrorState({
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            size: 64,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Error loading mods',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _RetryButton(onRetry: onRetry),
        ],
      ),
    );
  }
}

/// Retry button following Fluent Design principles
class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onRetry,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.arrow_sync_24_regular,
                color: theme.colorScheme.onPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                'Retry',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
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
