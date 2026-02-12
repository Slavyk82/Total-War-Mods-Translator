import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../providers/steam_publish_providers.dart';

/// Card displaying a recent pack export with project info and actions.
class PackExportCard extends ConsumerStatefulWidget {
  final RecentPackExport recentExport;

  const PackExportCard({super.key, required this.recentExport});

  @override
  ConsumerState<PackExportCard> createState() => _PackExportCardState();
}

class _PackExportCardState extends ConsumerState<PackExportCard> {
  bool _isHovered = false;
  bool _isPublishedIdUnlocked = false;
  late TextEditingController _publishedIdController;

  @override
  void initState() {
    super.initState();
    _publishedIdController = TextEditingController(
      text: widget.recentExport.publishedSteamId ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant PackExportCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recentExport.publishedSteamId !=
        widget.recentExport.publishedSteamId) {
      _publishedIdController.text =
          widget.recentExport.publishedSteamId ?? '';
    }
  }

  @override
  void dispose() {
    _publishedIdController.dispose();
    super.dispose();
  }

  void _savePublishedId() {
    final value = _publishedIdController.text.trim();
    final project = widget.recentExport.project;
    if (project == null) return;

    updatePublishedSteamId(
      ref,
      projectId: project.id,
      value: value.isEmpty ? null : value,
    );

    setState(() {
      _isPublishedIdUnlocked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final export = widget.recentExport.export;
    final mutedColor =
        theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6);

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
              // Project image
              _buildImage(context),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: project name + steam ID
                    _buildTopRow(context),
                    const SizedBox(height: 4),
                    // Row 2: languages
                    Text(
                      'Languages: ${export.languagesList.join(', ')}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: mutedColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Row 3: entries + size + time ago
                    _buildStatsRow(context),
                    const SizedBox(height: 4),
                    // Row 4: path + open folder button
                    _buildPathRow(context),
                    // Row 5: Published Steam ID (only if project exists)
                    if (widget.recentExport.project != null) ...[
                      const SizedBox(height: 4),
                      _buildPublishedIdRow(context),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    final theme = Theme.of(context);
    // Look for a .png image next to the exported .pack file
    final outputPath = widget.recentExport.export.outputPath;
    final packImagePath =
        '${outputPath.substring(0, outputPath.lastIndexOf('.'))}.png';
    final packImageFile = File(packImagePath);
    final imagePath =
        packImageFile.existsSync() ? packImagePath : widget.recentExport.projectImageUrl;

    Widget fallbackIcon() => Icon(
          FluentIcons.box_24_regular,
          size: 32,
          color: theme.colorScheme.onPrimaryContainer,
        );

    Widget imageWidget;
    if (imagePath != null && imagePath.isNotEmpty) {
      imageWidget = Image.file(
        File(imagePath),
        fit: BoxFit.cover,
        width: 118,
        height: 118,
        errorBuilder: (context, error, stackTrace) => fallbackIcon(),
      );
    } else {
      imageWidget = fallbackIcon();
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
    final steamId = widget.recentExport.steamWorkshopId;

    return Row(
      children: [
        Expanded(
          child: Text(
            widget.recentExport.projectDisplayName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (steamId != null) ...[
          const SizedBox(width: 8),
          Icon(FluentIcons.cloud_24_regular, size: 14, color: mutedColor),
          const SizedBox(width: 4),
          Text(
            'Steam ID: $steamId',
            style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
          ),
        ],
      ],
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    final theme = Theme.of(context);
    final export = widget.recentExport.export;
    final mutedColor =
        theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6);

    final entryCountStr = _formatEntryCount(export.entryCount);
    final timeAgoStr = timeago.format(export.exportDate);

    return Row(
      children: [
        Text(
          '$entryCountStr units',
          style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
        ),
        const SizedBox(width: 8),
        Text(
          '·',
          style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
        ),
        const SizedBox(width: 8),
        Text(
          export.fileSizeFormatted,
          style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
        ),
        const Spacer(),
        Icon(FluentIcons.clock_24_regular, size: 12, color: mutedColor),
        const SizedBox(width: 4),
        Text(
          timeAgoStr,
          style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
        ),
      ],
    );
  }

  Widget _buildPathRow(BuildContext context) {
    final theme = Theme.of(context);
    final export = widget.recentExport.export;
    final mutedColor =
        theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6);

    return Row(
      children: [
        Expanded(
          child: Text(
            export.outputPath,
            style: theme.textTheme.bodySmall?.copyWith(
              color: mutedColor,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        _buildOpenFolderButton(context),
      ],
    );
  }

  Widget _buildPublishedIdRow(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor =
        theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(FluentIcons.cloud_arrow_up_24_regular, size: 12, color: mutedColor),
        const SizedBox(width: 4),
        Text(
          'Published ID:',
          style: theme.textTheme.bodySmall?.copyWith(
            color: mutedColor,
            fontSize: 11,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 140,
          height: 22,
          child: TextField(
            controller: _publishedIdController,
            enabled: _isPublishedIdUnlocked,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 2,
              ),
              hintText: 'Steam Workshop ID',
              hintStyle: theme.textTheme.bodySmall?.copyWith(
                color: mutedColor,
                fontSize: 11,
              ),
              filled: true,
              fillColor: _isPublishedIdUnlocked
                  ? theme.colorScheme.surface
                  : theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.4),
                ),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.15),
                ),
              ),
            ),
            onSubmitted: (_) => _savePublishedId(),
          ),
        ),
        const SizedBox(width: 4),
        _buildLockButton(context),
      ],
    );
  }

  Widget _buildLockButton(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: _isPublishedIdUnlocked ? 'Lock' : 'Unlock to edit',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            if (_isPublishedIdUnlocked) {
              _savePublishedId();
            } else {
              setState(() {
                _isPublishedIdUnlocked = true;
              });
            }
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(2.0),
            child: Icon(
              _isPublishedIdUnlocked
                  ? FluentIcons.lock_open_24_regular
                  : FluentIcons.lock_closed_24_regular,
              size: 16,
              color: _isPublishedIdUnlocked
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOpenFolderButton(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: 'Open in Explorer',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            final outputPath = widget.recentExport.export.outputPath;
            Process.run('explorer.exe', ['/select,$outputPath']);
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
                  FluentIcons.folder_open_24_regular,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Open Folder',
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

  String _formatEntryCount(int count) {
    if (count < 1000) return count.toString();
    if (count < 1000000) {
      return '${(count / 1000).toStringAsFixed(count % 1000 == 0 ? 0 : 1)}K';
    }
    return '${(count / 1000000).toStringAsFixed(1)}M';
  }
}
