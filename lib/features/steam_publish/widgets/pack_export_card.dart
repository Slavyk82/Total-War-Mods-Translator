import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import '../../../config/router/app_router.dart';
import '../../../providers/shared/repository_providers.dart';
import '../../../providers/shared/service_providers.dart';
import '../../../widgets/fluent/fluent_toast.dart';
import '../providers/publish_staging_provider.dart';
import '../providers/steam_publish_providers.dart';
import 'pack_language_dialog.dart';

/// Card displaying a publishable item (project export or compilation).
class PackExportCard extends ConsumerStatefulWidget {
  final PublishableItem item;
  final bool isSelected;
  final ValueChanged<bool>? onSelectionChanged;

  const PackExportCard({
    super.key,
    required this.item,
    this.isSelected = false,
    this.onSelectionChanged,
  });

  @override
  ConsumerState<PackExportCard> createState() => _PackExportCardState();
}

class _PackExportCardState extends ConsumerState<PackExportCard> {
  bool _isHovered = false;
  final TextEditingController _steamIdController = TextEditingController();
  bool _isSavingSteamId = false;
  bool _isEditingSteamId = false;
  bool _isGenerating = false;
  double _generateProgress = 0.0;
  String? _generateStep;

  @override
  void dispose() {
    _steamIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor =
        theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    final hasPack = widget.item.hasPack;

    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _isHovered
              ? theme.colorScheme.surface.withValues(alpha: 0.8)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isHovered
                ? theme.colorScheme.primary.withValues(alpha: 0.3)
                : theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: theme.shadowColor.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Selection checkbox
              if (widget.onSelectionChanged != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 2),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: widget.isSelected,
                      onChanged: (value) =>
                          widget.onSelectionChanged!(value ?? false),
                    ),
                  ),
                ),
              // Image
              _buildImage(context),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: name + steam ID / status
                    _buildTopRow(context),
                    const SizedBox(height: 4),
                    // Row 2: languages
                    Text(
                      _buildLanguagesText(),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: mutedColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasPack) ...[
                      const SizedBox(height: 4),
                      // Row 3: stats (only when pack exists)
                      _buildStatsRow(context),
                      const SizedBox(height: 4),
                      // Row 4: path (only when pack exists)
                      _buildPathRow(context),
                    ] else if (widget.item.exportedAt > 0 ||
                        widget.item.publishedAt != null) ...[
                      const SizedBox(height: 4),
                      // Row 3 (no pack): dates only
                      _buildDatesOnlyRow(context),
                    ],
                    // Row 5: Action row
                    const SizedBox(height: 4),
                    _buildActionRow(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildLanguagesText() {
    final item = widget.item;
    switch (item) {
      case ProjectPublishItem():
        final langs = item.languagesList;
        if (langs.isEmpty) return 'Languages: —';
        return 'Languages: ${langs.join(', ')}';
      case CompilationPublishItem():
        if (item.languageCode != null) {
          return 'Language: ${item.languageCode}';
        }
        return 'Language: —';
    }
  }

  Widget _buildImage(BuildContext context) {
    final theme = Theme.of(context);
    final hasPack = widget.item.hasPack;
    final outputPath = widget.item.outputPath;

    Widget fallbackIcon() => Icon(
          widget.item.isCompilation
              ? FluentIcons.stack_24_regular
              : FluentIcons.box_24_regular,
          size: 32,
          color: theme.colorScheme.onPrimaryContainer,
        );

    Widget imageWidget;
    if (hasPack && outputPath.isNotEmpty) {
      final packImagePath =
          '${outputPath.substring(0, outputPath.lastIndexOf('.'))}.png';
      final packImageFile = File(packImagePath);
      final imagePath =
          packImageFile.existsSync() ? packImagePath : widget.item.imageUrl;

      if (imagePath != null && imagePath.isNotEmpty) {
        try {
          final bytes = File(imagePath).readAsBytesSync();
          imageWidget = Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: 118,
            height: 118,
            errorBuilder: (context, error, stackTrace) => fallbackIcon(),
          );
        } catch (_) {
          imageWidget = fallbackIcon();
        }
      } else {
        imageWidget = fallbackIcon();
      }
    } else {
      // No pack — try project image directly
      final imagePath = widget.item.imageUrl;
      if (imagePath != null && imagePath.isNotEmpty) {
        try {
          final bytes = File(imagePath).readAsBytesSync();
          imageWidget = Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: 118,
            height: 118,
            errorBuilder: (context, error, stackTrace) => fallbackIcon(),
          );
        } catch (_) {
          imageWidget = fallbackIcon();
        }
      } else {
        imageWidget = fallbackIcon();
      }
    }

    return Container(
      width: 118,
      height: 118,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(child: imageWidget),
    );
  }

  Widget _buildTopRow(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor =
        theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    final hasPack = widget.item.hasPack;
    final publishedId = widget.item.publishedSteamId;
    final hasPublished = publishedId != null && publishedId.isNotEmpty;

    return Row(
      children: [
        // Compilation badge
        if (widget.item.isCompilation) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Compilation',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            widget.item.displayName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        if (!hasPack) ...[
          if (hasPublished) ...[
            Icon(
              FluentIcons.cloud_checkmark_24_regular,
              size: 14,
              color: Colors.green.shade600,
            ),
            const SizedBox(width: 4),
            Text(
              'Workshop #$publishedId',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.green.shade600,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Icon(
            FluentIcons.box_dismiss_24_regular,
            size: 14,
            color: Colors.orange.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            'No pack',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.orange.shade700,
            ),
          ),
        ] else ...[
          Icon(
            hasPublished
                ? FluentIcons.cloud_checkmark_24_regular
                : FluentIcons.cloud_dismiss_24_regular,
            size: 14,
            color: hasPublished ? Colors.green.shade600 : mutedColor,
          ),
          const SizedBox(width: 4),
          Text(
            hasPublished ? 'Workshop #$publishedId' : 'Unpublished',
            style: theme.textTheme.bodySmall?.copyWith(
              color: hasPublished ? Colors.green.shade600 : mutedColor,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final mutedColor =
        theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6);

    final timeAgoStr = timeago.format(
      DateTime.fromMillisecondsSinceEpoch(item.exportedAt * 1000),
    );

    final List<String> stats = [];
    switch (item) {
      case ProjectPublishItem():
        if (item.entryCount > 0) {
          stats.add('${_formatEntryCount(item.entryCount)} units');
        }
        if (item.fileSizeFormatted.isNotEmpty) {
          stats.add(item.fileSizeFormatted);
        }
      case CompilationPublishItem():
        stats.add('${item.projectCount} projects');
        stats.add(item.fileSizeFormatted);
    }
    stats.add('Local file modified $timeAgoStr');

    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(width: 8),
            Text('·',
                style:
                    theme.textTheme.bodySmall?.copyWith(color: mutedColor)),
            const SizedBox(width: 8),
          ],
          Text(
            stats[i],
            style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
          ),
        ],
      ],
    );
  }

  /// Builds a row showing last modification and/or publication dates
  /// when the pack file has been deleted but historical dates exist.
  Widget _buildDatesOnlyRow(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final mutedColor =
        theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6);

    final List<Widget> children = [];

    if (item.exportedAt > 0) {
      final timeAgoStr = timeago.format(
        DateTime.fromMillisecondsSinceEpoch(item.exportedAt * 1000),
      );
      children.add(
        Text(
          'Last exported $timeAgoStr',
          style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
        ),
      );
    }

    if (item.publishedAt != null) {
      if (children.isNotEmpty) {
        children.addAll([
          const SizedBox(width: 8),
          Text('·',
              style: theme.textTheme.bodySmall?.copyWith(color: mutedColor)),
          const SizedBox(width: 8),
        ]);
      }
      final publishedDate =
          DateTime.fromMillisecondsSinceEpoch(item.publishedAt! * 1000);
      final timeAgoStr = timeago.format(publishedDate);
      final color = Colors.green.shade600;
      children.addAll([
        Icon(
          FluentIcons.checkmark_circle_24_regular,
          size: 12,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          'Published $timeAgoStr',
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontSize: 11,
          ),
        ),
      ]);
    }

    return Row(children: children);
  }

  Widget _buildPathRow(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor =
        theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6);

    return Text(
      widget.item.outputPath,
      style: theme.textTheme.bodySmall?.copyWith(
        color: mutedColor,
        fontSize: 11,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Build the action row based on the item's state:
  /// - State A: No pack → "Generate Pack" button
  /// - State B: Pack exists, no Workshop ID → Steam ID input
  /// - State C: Pack + Workshop ID → Update + Open in Steam
  Widget _buildActionRow(BuildContext context) {
    final hasPack = widget.item.hasPack;
    final hasPublishedId = widget.item.publishedSteamId != null &&
        widget.item.publishedSteamId!.isNotEmpty;

    // State A: No pack
    if (!hasPack) {
      if (_isGenerating) {
        return _buildGenerateProgress(context);
      }
      return Row(
        children: [
          _buildGeneratePackButton(context),
          if (hasPublishedId) ...[
            const SizedBox(width: 8),
            _buildOpenInSteamButton(context),
          ],
        ],
      );
    }

    // State B: Pack, no Workshop ID — or editing existing ID
    if (!hasPublishedId || _isEditingSteamId) {
      return _buildSteamIdInput(context);
    }

    // State C: Pack + Workshop ID
    return _buildPublishButton(context);
  }

  Widget _buildGeneratePackButton(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;

    return Tooltip(
      message: item.isCompilation
          ? 'Open compilation editor to generate'
          : 'Generate .pack file',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _handleGeneratePack(context),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item.isCompilation
                      ? FluentIcons.open_24_regular
                      : FluentIcons.box_arrow_up_24_regular,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  item.isCompilation
                      ? 'Open Compilation'
                      : 'Generate Pack',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGenerateProgress(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (_generateProgress * 100).toStringAsFixed(0);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _generateStep ?? 'Generating...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: Colors.orange.shade800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$percent%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _generateProgress,
                  minHeight: 4,
                  backgroundColor: Colors.orange.shade100,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.orange.shade700),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleGeneratePack(BuildContext context) async {
    final item = widget.item;

    if (item is CompilationPublishItem) {
      // Navigate to compilation editor screen
      context.goPackCompilation();
      return;
    }

    if (item is ProjectPublishItem) {
      final languages = item.languageCodes;
      if (languages.isEmpty) {
        FluentToast.warning(
          context,
          'No languages configured for this project.',
        );
        return;
      }

      List<String> selectedLanguages;
      if (languages.length > 1) {
        final result = await PackLanguageDialog.show(
          context,
          availableLanguages: languages,
        );
        if (result == null) return; // Cancelled
        selectedLanguages = result;
      } else {
        selectedLanguages = languages;
      }

      await _generatePackForProject(item, selectedLanguages);
    }
  }

  Future<void> _generatePackForProject(
    ProjectPublishItem item,
    List<String> languageCodes,
  ) async {
    if (!mounted) return;
    setState(() {
      _isGenerating = true;
      _generateProgress = 0.0;
      _generateStep = 'Preparing...';
    });

    try {
      final orchestrator = ref.read(exportOrchestratorServiceProvider);

      // Determine the output path using the orchestrator's convention
      final result = await orchestrator.exportToPack(
        projectId: item.project.id,
        languageCodes: languageCodes,
        outputPath: '', // auto-determined by the service
        validatedOnly: false,
        onProgress: (step, progress, {currentLanguage, currentIndex, total}) {
          if (mounted) {
            setState(() {
              _generateProgress = progress;
              _generateStep = _humanizeStep(step, currentLanguage);
            });
          }
        },
      );

      if (!mounted) return;

      if (result.isOk) {
        FluentToast.success(
          context,
          'Pack generated: ${result.value.entryCount} entries',
        );
        ref.invalidate(publishableItemsProvider);
      } else {
        FluentToast.error(
          context,
          'Failed to generate pack: ${result.error}',
        );
      }
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, 'Error generating pack: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generateProgress = 0.0;
          _generateStep = null;
        });
      }
    }
  }

  String _humanizeStep(String step, String? language) {
    final langSuffix = language != null ? ' ($language)' : '';
    switch (step) {
      case 'preparingData':
        return 'Preparing data...';
      case 'generatingLocFiles':
        return 'Generating .loc files$langSuffix';
      case 'creatingPack':
        return 'Creating .pack$langSuffix';
      case 'generatingImage':
        return 'Generating preview image...';
      case 'finalizing':
        return 'Finalizing...';
      case 'completed':
        return 'Completed';
      default:
        return step;
    }
  }

  Widget _buildPublishButton(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Tooltip(
          message: 'Update existing Workshop item',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                ref.read(singlePublishStagingProvider.notifier).set(widget.item);
                context.goWorkshopPublishSingle();
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FluentIcons.cloud_arrow_up_24_regular,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Update',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildOpenInSteamButton(context),
        const SizedBox(width: 8),
        _buildEditSteamIdButton(context),
        if (widget.item.publishedAt != null) ...[
          const SizedBox(width: 8),
          _buildPublishedAtLabel(context),
        ],
      ],
    );
  }

  Widget _buildEditSteamIdButton(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: 'Edit Workshop ID',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            _steamIdController.text = widget.item.publishedSteamId ?? '';
            setState(() => _isEditingSteamId = true);
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              FluentIcons.edit_24_regular,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSteamIdInput(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        SizedBox(
          width: 180,
          height: 28,
          child: TextField(
            controller: _steamIdController,
            enabled: !_isSavingSteamId,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
            decoration: InputDecoration(
              hintText: 'Enter Workshop ID...',
              hintStyle: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _saveSteamId(),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: 'Save Workshop ID',
          child: MouseRegion(
            cursor:
                _isSavingSteamId ? SystemMouseCursors.basic : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _isSavingSteamId ? null : _saveSteamId,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: _isSavingSteamId
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : Icon(
                        FluentIcons.save_24_regular,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
              ),
            ),
          ),
        ),
        if (_isEditingSteamId) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: 'Cancel',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  _steamIdController.clear();
                  setState(() => _isEditingSteamId = false);
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(
                    FluentIcons.dismiss_24_regular,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _saveSteamId() async {
    final steamId = _steamIdController.text.trim();
    if (steamId.isEmpty) return;

    setState(() => _isSavingSteamId = true);

    try {
      final item = widget.item;
      if (item is ProjectPublishItem) {
        final projectRepo = ref.read(projectRepositoryProvider);
        final projectResult = await projectRepo.getById(item.project.id);
        if (projectResult.isOk) {
          final updated = projectResult.value.copyWith(
            publishedSteamId: steamId,
            updatedAt: projectResult.value.updatedAt,
          );
          await projectRepo.update(updated);
        }
      } else if (item is CompilationPublishItem) {
        final compilationRepo = ref.read(compilationRepositoryProvider);
        await compilationRepo.updateAfterPublish(
          item.compilation.id,
          steamId,
          item.publishedAt ?? 0,
        );
      }
      if (mounted) {
        _isEditingSteamId = false;
        ref.invalidate(publishableItemsProvider);
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingSteamId = false);
      }
    }
  }

  Widget _buildOpenInSteamButton(BuildContext context) {
    final theme = Theme.of(context);
    final workshopId = widget.item.publishedSteamId!;
    final url =
        'https://steamcommunity.com/sharedfiles/filedetails/?id=$workshopId';

    return Tooltip(
      message: url,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => launchUrl(Uri.parse(url)),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.open_24_regular,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'Open in Steam',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPublishedAtLabel(BuildContext context) {
    final theme = Theme.of(context);
    final publishedAt = widget.item.publishedAt!;
    final exportedAt = widget.item.exportedAt;
    final isUpToDate = publishedAt >= exportedAt;
    final color = isUpToDate ? Colors.green.shade600 : Colors.red.shade600;
    final publishedDate = DateTime.fromMillisecondsSinceEpoch(publishedAt * 1000);
    final timeAgoStr = timeago.format(publishedDate);

    return Tooltip(
      message: 'Last published: ${publishedDate.toLocal().toString().substring(0, 16)}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUpToDate
                ? FluentIcons.checkmark_circle_24_regular
                : FluentIcons.warning_24_regular,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            'Published $timeAgoStr',
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _formatEntryCount(int count) {
    if (count < 1000) return count.toString();
    if (count < 1000000) {
      return '${(count / 1000).toStringAsFixed(count % 1000 == 0 ? 0 : 1)}K';
    }
    return '${(count / 1000000).toStringAsFixed(1)}M';
  }
}
