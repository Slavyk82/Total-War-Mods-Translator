import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import '../providers/steam_publish_providers.dart';
import 'workshop_publish_dialog.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                    // Row 1: name + steam ID
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
                    const SizedBox(height: 4),
                    // Row 3: stats
                    _buildStatsRow(context),
                    const SizedBox(height: 4),
                    // Row 4: path
                    _buildPathRow(context),
                    // Row 5: Publish button
                    const SizedBox(height: 4),
                    _buildPublishButton(context),
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
        return 'Languages: ${item.languagesList.join(', ')}';
      case CompilationPublishItem():
        if (item.languageCode != null) {
          return 'Language: ${item.languageCode}';
        }
        return 'Language: —';
    }
  }

  Widget _buildImage(BuildContext context) {
    final theme = Theme.of(context);
    final outputPath = widget.item.outputPath;
    final packImagePath =
        '${outputPath.substring(0, outputPath.lastIndexOf('.'))}.png';
    final packImageFile = File(packImagePath);
    final imagePath =
        packImageFile.existsSync() ? packImagePath : widget.item.imageUrl;

    Widget fallbackIcon() => Icon(
          widget.item.isCompilation
              ? FluentIcons.stack_24_regular
              : FluentIcons.box_24_regular,
          size: 32,
          color: theme.colorScheme.onPrimaryContainer,
        );

    Widget imageWidget;
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
        stats.add('${_formatEntryCount(item.entryCount)} units');
        stats.add(item.fileSizeFormatted);
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

  Widget _buildPublishButton(BuildContext context) {
    final theme = Theme.of(context);
    final hasPublishedId = widget.item.publishedSteamId != null &&
        widget.item.publishedSteamId!.isNotEmpty;

    return Row(
      children: [
        Tooltip(
          message: hasPublishedId
              ? 'Update existing Workshop item'
              : 'Publish to Steam Workshop',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                WorkshopPublishDialog.show(
                  context,
                  item: widget.item,
                );
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
                      hasPublishedId ? 'Update' : 'Publish',
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
        if (hasPublishedId) ...[
          const SizedBox(width: 8),
          _buildOpenInSteamButton(context),
        ],
        if (hasPublishedId && widget.item.publishedAt != null) ...[
          const SizedBox(width: 8),
          _buildPublishedAtLabel(context),
        ],
      ],
    );
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
