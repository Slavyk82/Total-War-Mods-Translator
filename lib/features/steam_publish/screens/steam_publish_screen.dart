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
import '../providers/batch_workshop_publish_notifier.dart';
import '../providers/steam_publish_providers.dart';
import '../widgets/batch_workshop_publish_dialog.dart';
import '../widgets/pack_export_list.dart';
import '../widgets/steam_login_dialog.dart';
import '../widgets/steamcmd_install_dialog.dart';

enum _SortMode { exportDate, name, published }

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
  final TextEditingController _searchController = TextEditingController();
  Set<String> _selectedPaths = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RecentPackExport> _filterAndSort(List<RecentPackExport> exports) {
    var result = exports.toList();

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result
          .where((e) => e.projectDisplayName.toLowerCase().contains(query))
          .toList();
    }

    result.sort((a, b) {
      int cmp;
      switch (_sortMode) {
        case _SortMode.exportDate:
          cmp = a.export.exportedAt.compareTo(b.export.exportedAt);
        case _SortMode.name:
          cmp = a.projectDisplayName
              .toLowerCase()
              .compareTo(b.projectDisplayName.toLowerCase());
        case _SortMode.published:
          final aPub = a.publishedSteamId != null ? 0 : 1;
          final bPub = b.publishedSteamId != null ? 0 : 1;
          cmp = aPub.compareTo(bPub);
          if (cmp == 0) {
            cmp = a.export.exportedAt.compareTo(b.export.exportedAt);
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

  Future<void> _startBatchPublish(List<RecentPackExport> allExports) async {
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
    final (username, password) = credentials;

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
    final selectedExports = allExports
        .where((e) => _selectedPaths.contains(e.export.outputPath))
        .toList();

    final items = <BatchPublishItemInfo>[];
    final skippedNoPreview = <String>[];

    for (final export in selectedExports) {
      final packPath = export.export.outputPath;
      final previewPath =
          '${packPath.substring(0, packPath.lastIndexOf('.'))}.png';

      if (!File(previewPath).existsSync()) {
        skippedNoPreview.add(export.projectDisplayName);
        continue;
      }

      final packDir = File(packPath).parent.path;
      final modName = export.projectDisplayName;

      final params = WorkshopPublishParams(
        appId: '1142710',
        publishedFileId: export.publishedSteamId ?? '0',
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

      items.add(BatchPublishItemInfo(
        name: modName,
        params: params,
        projectId: export.project?.id,
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

    // Open batch publish dialog
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BatchWorkshopPublishDialog(
        items: items,
        username: username,
        password: password,
      ),
    );

    // Clear selection and refresh
    if (mounted) {
      setState(() => _selectedPaths = {});
      ref.invalidate(recentPackExportsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asyncExports = ref.watch(recentPackExportsProvider);

    return FluentScaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      header: FluentHeader(
        title: 'Publish on Steam',
        actions: [
          // Publish Selection button
          FilledButton.icon(
            onPressed: _selectedPaths.isNotEmpty
                ? () {
                    final exports = asyncExports.asData?.value;
                    if (exports != null) _startBatchPublish(exports);
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
                child: const Text('Date'),
              ),
              CheckedPopupMenuItem(
                value: _SortMode.name,
                checked: _sortMode == _SortMode.name,
                child: const Text('Name'),
              ),
              CheckedPopupMenuItem(
                value: _SortMode.published,
                checked: _sortMode == _SortMode.published,
                child: const Text('Published'),
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
                ref.invalidate(recentPackExportsProvider);
              },
            ),
          ),
        ],
      ),
      body: asyncExports.when(
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
                'Failed to load recent exports',
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
                  ref.invalidate(recentPackExportsProvider);
                },
                icon: const Icon(FluentIcons.arrow_sync_24_regular, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (exports) {
          if (exports.isEmpty) {
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
                    'Export a project as .pack to see it here.',
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
            exports: _filterAndSort(exports),
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
