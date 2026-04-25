import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:path/path.dart' as path;

import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/steam/models/workshop_publish_params.dart';
import 'package:twmt/services/steam/steamcmd_manager.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/fluent/fluent_toast.dart';

import '../../settings/providers/settings_providers.dart'
    hide settingsServiceProvider;
import '../providers/batch_workshop_publish_notifier.dart';
import '../providers/publish_staging_provider.dart';
import '../providers/steam_publish_providers.dart';
import '../widgets/steam_login_dialog.dart';
import '../widgets/steam_publish_list.dart';
import '../widgets/steam_publish_toolbar.dart';
import '../widgets/steamcmd_install_dialog.dart';
import '../widgets/workshop_onboarding_card.dart';
import '../widgets/workshop_publish_settings_dialog.dart';

import 'package:twmt/widgets/detail/home_back_toolbar.dart';

/// Steam Publish screen — filterable list archetype per UI spec §7.1.
///
/// Migrated from the legacy `FluentScaffold` + card-list layout to the shared
/// [FilterToolbar] + [ListRow] primitives introduced in Plan 5a. Selection is
/// kept in the Riverpod [steamPublishSelectionProvider]; filter / search /
/// sort state is likewise provider-backed so the widget tree stays stateless.
class SteamPublishScreen extends ConsumerStatefulWidget {
  const SteamPublishScreen({super.key});

  @override
  ConsumerState<SteamPublishScreen> createState() =>
      _SteamPublishScreenState();
}

class _SteamPublishScreenState extends ConsumerState<SteamPublishScreen> {
  @override
  void initState() {
    super.initState();
    // Reset transient screen state (selection + filter + search) on entry so
    // stale selection from a previous visit doesn't leak across navigations.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(steamPublishSelectionProvider.notifier).state = {};
      ref.read(steamPublishSearchQueryProvider.notifier).state = '';
      ref.read(steamPublishDisplayFilterProvider.notifier).state =
          SteamPublishDisplayFilter.all;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final asyncItems = ref.watch(publishableItemsProvider);
    final allItems = asyncItems.asData?.value ?? const <PublishableItem>[];
    final filteredItems = ref.watch(filteredPublishableItemsProvider);
    final selection = ref.watch(steamPublishSelectionProvider);
    final searchQuery = ref.watch(steamPublishSearchQueryProvider);
    final currentFilter = ref.watch(steamPublishDisplayFilterProvider);
    final outdatedCount = ref.watch(outdatedPublishableItemsCountProvider);
    final noPackCount = ref.watch(noPackPublishableItemsCountProvider);
    final compilationsCount =
        ref.watch(compilationsPublishableItemsCountProvider);
    final subsTotal = ref.watch(filteredPublishableItemsSubsTotalProvider);

    final publishableSelected = allItems
        .where((e) => selection.contains(e.itemId))
        .where(_isPublishable)
        .toList(growable: false);
    final canPublish = publishableSelected.isNotEmpty;
    final disabledTooltip = !canPublish && selection.isNotEmpty
        ? 'No selected item has both a generated pack and a Workshop id'
        : null;
    final allSelected = filteredItems.isNotEmpty &&
        filteredItems.every((e) => selection.contains(e.itemId));

    return Material(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeBackToolbar(
            leading: SteamPublishToolbarLeading(
              totalItems: allItems.length,
              filteredItems: filteredItems.length,
              selectedCount: selection.length,
              searchActive: searchQuery.isNotEmpty,
              subsTotal: subsTotal,
            ),
          ),
          const WorkshopOnboardingCard(),
          SteamPublishToolbar(
            totalItems: allItems.length,
            outdatedCount: outdatedCount,
            noPackCount: noPackCount,
            compilationsCount: compilationsCount,
            searchQuery: searchQuery,
            onSearchChanged: (query) {
              ref.read(steamPublishSearchQueryProvider.notifier).state = query;
            },
            currentFilter: currentFilter,
            onFilterChanged: (filter) {
              ref.read(steamPublishDisplayFilterProvider.notifier).state =
                  filter;
            },
            onSelectAll: () => _selectAll(filteredItems),
            allSelected: allSelected,
            onDeselectAll:
                selection.isNotEmpty ? _deselectAll : null,
            onPublishSelection:
                canPublish ? () => _startBatchPublish(allItems) : null,
            publishDisabledTooltip: disabledTooltip,
            selectedCount: selection.length,
            publishableSelectedCount: publishableSelected.length,
            onRefresh: () {
              ref.invalidate(publishableItemsProvider);
            },
            onOpenSettings: () =>
                WorkshopPublishSettingsDialog.show(context),
          ),
          Expanded(
            child: asyncItems.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorState(error: error),
              data: (items) {
                if (items.isEmpty) {
                  return const SteamPublishEmptyState();
                }
                if (filteredItems.isEmpty) {
                  return const SteamPublishNoMatchesState();
                }
                return SteamPublishList(items: filteredItems);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Batch selection helpers
  // ---------------------------------------------------------------------------

  void _selectAll(List<PublishableItem> currentFiltered) {
    ref.read(steamPublishSelectionProvider.notifier).state =
        currentFiltered.map((e) => e.itemId).toSet();
  }

  void _deselectAll() {
    ref.read(steamPublishSelectionProvider.notifier).state = {};
  }

  // ---------------------------------------------------------------------------
  // Publish gate — items lacking either a generated pack or a Workshop id are
  // silently skipped during the batch publish flow.
  // ---------------------------------------------------------------------------

  static bool _isPublishable(PublishableItem item) {
    final id = item.publishedSteamId;
    return item.hasPack && id != null && id.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Batch publish flow (unchanged from the legacy screen).
  // ---------------------------------------------------------------------------

  String _applyTemplate(String template, String modName) {
    if (template.isEmpty) return '';
    return template.replaceAll(r'$modName', modName);
  }

  Future<void> _startBatchPublish(List<PublishableItem> allItems) async {
    final selection = ref.read(steamPublishSelectionProvider);
    final selectedItems = allItems
        .where((e) => selection.contains(e.itemId))
        .where(_isPublishable)
        .toList();

    if (selectedItems.isEmpty) {
      FluentToast.warning(
        context,
        'No selected item has both a generated pack and a Workshop id.',
      );
      return;
    }

    // Check steamcmd availability.
    final isAvailable = await SteamCmdManager().isAvailable();
    if (!mounted) return;
    if (!isAvailable) {
      final installed = await SteamCmdInstallDialog.show(context);
      if (!installed || !mounted) return;
    }

    // Use saved credentials if available, otherwise show login dialog.
    var credentials = await SteamLoginDialog.getSavedCredentials();
    if (credentials == null) {
      if (!mounted) return;
      credentials = await SteamLoginDialog.show(context);
    }
    if (credentials == null || !mounted) return;
    final (username, password, steamGuardCode) = credentials;

    // Load templates.
    final settingsService = ref.read(settingsServiceProvider);
    final titleTemplate =
        await settingsService.getString(SettingsKeys.workshopTitleTemplate);
    final descTemplate = await settingsService
        .getString(SettingsKeys.workshopDescriptionTemplate);
    final visibilityName = await settingsService
        .getString(SettingsKeys.workshopDefaultVisibility);

    final visibility = WorkshopVisibility.values
            .where((v) => v.name == visibilityName)
            .firstOrNull ??
        WorkshopVisibility.public_;

    final items = <BatchPublishItemInfo>[];
    final skippedNoPreview = <String>[];
    final imageGenerator = ref.read(packImageGeneratorServiceProvider);

    for (final item in selectedItems) {
      final packPath = item.outputPath;
      final previewPath =
          '${packPath.substring(0, packPath.lastIndexOf('.'))}.png';

      // Regenerate preview image if missing.
      if (!File(previewPath).existsSync()) {
        final packFileName = path.basename(packPath);
        final gameDataPath = File(packPath).parent.path;

        String languageCode = 'en';
        String? modImageUrl;
        bool useAppIcon = true;

        if (item is ProjectPublishItem) {
          final langs = item.languagesList;
          if (langs.isNotEmpty) languageCode = langs.first;
          modImageUrl = item.project.imageUrl;
          useAppIcon = item.project.isGameTranslation;
        } else if (item is CompilationPublishItem) {
          languageCode = item.languageCode ?? 'en';
        }

        await imageGenerator.ensurePackImage(
          packFileName: packFileName,
          gameDataPath: gameDataPath,
          languageCode: languageCode,
          modImageUrl: modImageUrl,
          generateImage: true,
          useAppIcon: useAppIcon,
        );

        if (!File(previewPath).existsSync()) {
          skippedNoPreview.add(item.displayName);
          continue;
        }
      }

      final packDir = File(packPath).parent.path;
      final modName = item.displayName;

      final params = WorkshopPublishParams(
        appId: '1142710',
        publishedFileId: item.publishedSteamId!,
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

    if (skippedNoPreview.isNotEmpty) {
      FluentToast.warning(
        context,
        'Skipped ${skippedNoPreview.length} item(s) without preview image: '
        '${skippedNoPreview.join(', ')}',
      );
    }

    if (items.isEmpty) {
      FluentToast.warning(
        context,
        'No items to publish (all missing preview images).',
      );
      return;
    }

    ref.read(batchPublishStagingProvider.notifier).set(BatchPublishStagingData(
          items: items,
          username: username,
          password: password,
          steamGuardCode: steamGuardCode,
        ));
    if (mounted) {
      ref.read(steamPublishSelectionProvider.notifier).state = {};
      context.goWorkshopPublishBatch();
    }
  }
}

// =============================================================================
// Error state
// =============================================================================

class _ErrorState extends ConsumerWidget {
  final Object error;

  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              'Failed to load publishable items',
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
            const SizedBox(height: 16),
            _RetryButton(onRetry: () {
              ref.invalidate(publishableItemsProvider);
            }),
          ],
        ),
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  final VoidCallback onRetry;

  const _RetryButton({required this.onRetry});

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
