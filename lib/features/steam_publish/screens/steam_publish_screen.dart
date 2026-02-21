import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';

import '../../settings/providers/settings_providers.dart';
import '../../../services/settings/settings_service.dart';
import '../../../services/service_locator.dart';
import '../../../services/steam/models/workshop_publish_params.dart';
import '../../../services/steam/steamcmd_manager.dart';
import '../../../config/router/app_router.dart';
import '../providers/batch_workshop_publish_notifier.dart';
import '../providers/publish_staging_provider.dart';
import '../providers/steam_publish_providers.dart';
import '../widgets/pack_export_list.dart';
import '../widgets/steam_login_dialog.dart';
import '../widgets/steamcmd_install_dialog.dart';
import '../widgets/workshop_publish_settings_dialog.dart';

enum _SortMode { exportDate, name, publishDate }

enum _SelectionAction { all, unpublished, outdated, none }

enum _DisplayFilter { all, unpublished, outdated }

class SteamPublishScreen extends ConsumerStatefulWidget {
  const SteamPublishScreen({super.key});

  @override
  ConsumerState<SteamPublishScreen> createState() =>
      _SteamPublishScreenState();
}

class _SteamPublishScreenState extends ConsumerState<SteamPublishScreen> {
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.exportDate;
  bool _sortAscending = false;
  _DisplayFilter _displayFilter = _DisplayFilter.all;
  final TextEditingController _searchController = TextEditingController();
  Set<String> _selectedPaths = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PublishableItem> _filterAndSort(List<PublishableItem> items) {
    var result = items.toList();

    // Apply display filter
    switch (_displayFilter) {
      case _DisplayFilter.all:
        break;
      case _DisplayFilter.unpublished:
        result = result
            .where((e) =>
                e.publishedSteamId == null || e.publishedSteamId!.isEmpty)
            .toList();
      case _DisplayFilter.outdated:
        result = result
            .where((e) =>
                e.publishedAt != null && e.exportedAt > e.publishedAt!)
            .toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result
          .where((e) => e.displayName.toLowerCase().contains(query))
          .toList();
    }

    result.sort((a, b) {
      int cmp;
      switch (_sortMode) {
        case _SortMode.exportDate:
          cmp = a.exportedAt.compareTo(b.exportedAt);
        case _SortMode.name:
          cmp = a.displayName
              .toLowerCase()
              .compareTo(b.displayName.toLowerCase());
        case _SortMode.publishDate:
          final aPub = a.publishedAt;
          final bPub = b.publishedAt;
          // Unpublished mods always sort to the end, regardless of direction
          if (aPub == null && bPub == null) {
            return a.exportedAt.compareTo(b.exportedAt);
          }
          if (aPub == null) return 1;
          if (bPub == null) return -1;
          cmp = aPub.compareTo(bPub);
          if (cmp == 0) {
            cmp = a.exportedAt.compareTo(b.exportedAt);
          }
      }
      return _sortAscending ? cmp : -cmp;
    });

    return result;
  }

  String _applyTemplate(String template, String modName) {
    if (template.isEmpty) return '';
    return template.replaceAll('\$modName', modName);
  }

  Future<void> _startBatchPublish(List<PublishableItem> allItems) async {
    // Check steamcmd availability
    final isAvailable = await SteamCmdManager().isAvailable();
    if (!mounted) return;
    if (!isAvailable) {
      final installed = await SteamCmdInstallDialog.show(context);
      if (!installed || !mounted) return;
    }

    // Show login dialog (once for the whole batch)
    final credentials = await SteamLoginDialog.show(context);
    if (credentials == null || !mounted) return;
    final (username, password, steamGuardCode) = credentials;

    // Load templates
    final settingsService = ServiceLocator.get<SettingsService>();
    final titleTemplate =
        await settingsService.getString(SettingsKeys.workshopTitleTemplate);
    final descTemplate =
        await settingsService.getString(SettingsKeys.workshopDescriptionTemplate);
    final visibilityName =
        await settingsService.getString(SettingsKeys.workshopDefaultVisibility);

    final visibility = WorkshopVisibility.values
            .where((v) => v.name == visibilityName)
            .firstOrNull ??
        WorkshopVisibility.public_;

    // Build items from selected exports
    final selectedItems = allItems
        .where((e) => _selectedPaths.contains(e.outputPath))
        .toList();

    final items = <BatchPublishItemInfo>[];
    final skippedNoPreview = <String>[];

    for (final item in selectedItems) {
      final packPath = item.outputPath;
      final previewPath =
          '${packPath.substring(0, packPath.lastIndexOf('.'))}.png';

      if (!File(previewPath).existsSync()) {
        skippedNoPreview.add(item.displayName);
        continue;
      }

      final packDir = File(packPath).parent.path;
      final modName = item.displayName;

      final params = WorkshopPublishParams(
        appId: '1142710',
        publishedFileId: item.publishedSteamId ?? '0',
        contentFolder: packDir,
        previewFile: previewPath,
        title: titleTemplate.isNotEmpty
            ? _applyTemplate(titleTemplate, modName)
            : modName,
        description: descTemplate.isNotEmpty
            ? _applyTemplate(descTemplate, modName)
            : '',
        visibility: visibility,
      );

      // Determine project/compilation ID for saving after publish
      String? projectId;
      String? compilationId;
      if (item is ProjectPublishItem) {
        projectId = item.project.id;
      } else if (item is CompilationPublishItem) {
        compilationId = item.compilation.id;
      }

      items.add(BatchPublishItemInfo(
        name: modName,
        params: params,
        projectId: projectId,
        compilationId: compilationId,
      ));
    }

    if (!mounted) return;

    // Warn about skipped items
    if (skippedNoPreview.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Skipped ${skippedNoPreview.length} item(s) without preview image: ${skippedNoPreview.join(', ')}',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No items to publish (all missing preview images).'),
        ),
      );
      return;
    }

    // Navigate to batch publish screen
    ref.read(batchPublishStagingProvider.notifier).set(BatchPublishStagingData(
      items: items,
      username: username,
      password: password,
      steamGuardCode: steamGuardCode,
    ));
    if (mounted) {
      setState(() => _selectedPaths = {});
      context.goWorkshopPublishBatch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asyncItems = ref.watch(publishableItemsProvider);
    final allItems = asyncItems.asData?.value;
    final filteredItems =
        allItems != null ? _filterAndSort(allItems) : <PublishableItem>[];

    return FluentScaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      header: FluentHeader(
        title: 'Publish on Steam',
        actions: [
          // Active filter indicator
          if (_displayFilter != _DisplayFilter.all)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InputChip(
                label: Text(
                  _displayFilter == _DisplayFilter.unpublished
                      ? 'Unpublished'
                      : 'Outdated',
                  style: theme.textTheme.labelSmall,
                ),
                onDeleted: () {
                  setState(() {
                    _displayFilter = _DisplayFilter.all;
                    _selectedPaths = {};
                  });
                },
                deleteIconColor: theme.colorScheme.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
              ),
            ),
          // Quick selection menu
          PopupMenuButton<_SelectionAction>(
            icon: const Icon(FluentIcons.checkbox_checked_24_regular, size: 20),
            tooltip: 'Quick select',
            enabled: filteredItems.isNotEmpty,
            onSelected: (action) {
              setState(() {
                switch (action) {
                  case _SelectionAction.all:
                    _displayFilter = _DisplayFilter.all;
                    // Recompute filtered list with new display filter
                    final allFiltered = _filterAndSort(allItems!);
                    _selectedPaths =
                        allFiltered.map((e) => e.outputPath).toSet();
                  case _SelectionAction.unpublished:
                    _displayFilter = _DisplayFilter.unpublished;
                    final unpubFiltered = _filterAndSort(allItems!);
                    _selectedPaths =
                        unpubFiltered.map((e) => e.outputPath).toSet();
                  case _SelectionAction.outdated:
                    _displayFilter = _DisplayFilter.outdated;
                    final outdatedFiltered = _filterAndSort(allItems!);
                    _selectedPaths =
                        outdatedFiltered.map((e) => e.outputPath).toSet();
                  case _SelectionAction.none:
                    _displayFilter = _DisplayFilter.all;
                    _selectedPaths = {};
                }
              });
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _SelectionAction.all,
                child: Text('Select All'),
              ),
              const PopupMenuItem(
                value: _SelectionAction.unpublished,
                child: Text('Select Unpublished'),
              ),
              const PopupMenuItem(
                value: _SelectionAction.outdated,
                child: Text('Select Outdated'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _SelectionAction.none,
                child: Text('Deselect All'),
              ),
            ],
          ),
          // Publish Selection button
          FilledButton.icon(
            onPressed: _selectedPaths.isNotEmpty
                ? () {
                    final items = asyncItems.asData?.value;
                    if (items != null) _startBatchPublish(items);
                  }
                : null,
            icon: const Icon(FluentIcons.cloud_arrow_up_24_regular, size: 18),
            label: Text(
              _selectedPaths.isEmpty
                  ? 'Publish Selection'
                  : 'Publish (${_selectedPaths.length})',
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _searchController,
              style: theme.textTheme.bodySmall,
              decoration: InputDecoration(
                hintText: 'Search by name...',
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                prefixIcon:
                    const Icon(FluentIcons.search_24_regular, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(FluentIcons.dismiss_24_regular,
                            size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          PopupMenuButton<_SortMode>(
            icon: const Icon(FluentIcons.arrow_sort_24_regular, size: 20),
            tooltip: 'Sort by',
            onSelected: (mode) => setState(() => _sortMode = mode),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: _SortMode.exportDate,
                checked: _sortMode == _SortMode.exportDate,
                child: const Text('Export Date'),
              ),
              CheckedPopupMenuItem(
                value: _SortMode.publishDate,
                checked: _sortMode == _SortMode.publishDate,
                child: const Text('Publish Date'),
              ),
              CheckedPopupMenuItem(
                value: _SortMode.name,
                checked: _sortMode == _SortMode.name,
                child: const Text('Name'),
              ),
            ],
          ),
          Tooltip(
            message: _sortAscending ? 'Sort ascending' : 'Sort descending',
            child: IconButton(
              icon: Icon(
                _sortAscending
                    ? FluentIcons.arrow_sort_up_24_regular
                    : FluentIcons.arrow_sort_down_lines_24_regular,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _sortAscending = !_sortAscending),
            ),
          ),
          Tooltip(
            message: 'Refresh',
            child: IconButton(
              icon: const Icon(FluentIcons.arrow_sync_24_regular, size: 20),
              onPressed: () {
                ref.invalidate(publishableItemsProvider);
              },
            ),
          ),
          Tooltip(
            message: 'Publish settings',
            child: IconButton(
              icon: const Icon(FluentIcons.settings_24_regular, size: 20),
              onPressed: () => WorkshopPublishSettingsDialog.show(context),
            ),
          ),
        ],
      ),
      body: asyncItems.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
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
                'Failed to load publishable items',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  ref.invalidate(publishableItemsProvider);
                },
                icon: const Icon(FluentIcons.arrow_sync_24_regular, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    FluentIcons.box_24_regular,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No pack exports yet',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Export a project as .pack or generate a compilation to see it here.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            );
          }

          return PackExportList(
            items: filteredItems,
            selectedPaths: _selectedPaths,
            onToggleSelection: (path) {
              setState(() {
                if (_selectedPaths.contains(path)) {
                  _selectedPaths = Set.from(_selectedPaths)..remove(path);
                } else {
                  _selectedPaths = Set.from(_selectedPaths)..add(path);
                }
              });
            },
          );
        },
      ),
    );
  }
}
