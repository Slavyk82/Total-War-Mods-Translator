import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/list_row.dart';
import 'package:twmt/widgets/lists/relative_date.dart';
import 'package:twmt/widgets/lists/status_pill.dart';

import '../providers/published_subs_cache_provider.dart';
import '../providers/steam_publish_providers.dart';

/// Column spec for the Steam Publish list (§7.1 filterable list archetype).
/// Columns (fixed widths selected to match the checkbox + cover + action
/// density of the sibling Mods list):
///
/// 1. checkbox (batch-selection toggle)
/// 2. cover (pack preview)
/// 3. title + pack filename mono (flex)
/// 4. steam id + edit pencil
/// 5. subs (Workshop subscriber count)
/// 6. publish state badge
/// 7. last published / exported (mono)
/// 8. inline action
const List<ListRowColumn> steamPublishColumns = [
  ListRowColumn.fixed(40),  // checkbox
  ListRowColumn.fixed(80),  // cover
  ListRowColumn.flex(3),    // title + filename
  ListRowColumn.fixed(180), // steam id (new)
  ListRowColumn.fixed(100), // subs
  ListRowColumn.fixed(160), // status
  ListRowColumn.fixed(180), // last published — fits "Outdated · 12 months"
  ListRowColumn.fixed(180), // action
];

// =============================================================================
// Selection checkbox
// =============================================================================

/// Batch-selection checkbox rendered in column 1.
class SteamSelectionCheckbox extends StatelessWidget {
  final bool selected;
  final VoidCallback onToggle;

  const SteamSelectionCheckbox({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: selected ? tokens.accent : tokens.panel,
              borderRadius: BorderRadius.circular(tokens.radiusXs),
              border: Border.all(
                color: selected ? tokens.accent : tokens.border,
                width: 1.5,
              ),
            ),
            child: selected
                ? Icon(
                    FluentIcons.checkmark_16_filled,
                    size: 14,
                    color: tokens.accentFg,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Cover (pack preview image or fallback icon)
// =============================================================================

/// Pack preview image (or fallback icon) rendered in column 2.
class SteamCoverCell extends StatelessWidget {
  final PublishableItem item;

  const SteamCoverCell({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasPack = item.hasPack;
    final outputPath = item.outputPath;

    Widget fallback() => Icon(
          item.isCompilation
              ? FluentIcons.stack_24_regular
              : FluentIcons.box_24_regular,
          size: 44,
          color: tokens.textFaint,
        );

    Widget inner = fallback();
    String? imagePath;
    if (hasPack && outputPath.isNotEmpty) {
      final packImagePath =
          '${outputPath.substring(0, outputPath.lastIndexOf('.'))}.png';
      if (File(packImagePath).existsSync()) {
        imagePath = packImagePath;
      } else if (item.imageUrl != null && item.imageUrl!.isNotEmpty) {
        imagePath = item.imageUrl;
      }
    } else if (item.imageUrl != null && item.imageUrl!.isNotEmpty) {
      imagePath = item.imageUrl;
    }

    if (imagePath != null) {
      // `Image.file` decodes off the main isolate and hands bytes to the engine
      // cache. `cacheWidth`/`cacheHeight` cap the decoded bitmap to the render
      // size (2× for HiDPI). `filterQuality.medium` keeps the cover crisp.
      inner = Image.file(
        File(imagePath),
        fit: BoxFit.cover,
        width: 80,
        height: 80,
        cacheWidth: 160,
        cacheHeight: 160,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => fallback(),
      );
    }

    return Center(
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: tokens.panel,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: inner,
      ),
    );
  }
}

// =============================================================================
// Title + pack filename mono
// =============================================================================

/// Title block rendered in column 3 — display name + pack filename mono line.
class SteamTitleBlock extends StatelessWidget {
  final PublishableItem item;

  const SteamTitleBlock({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final outputPath = item.outputPath;
    final String subtitle;
    if (outputPath.isNotEmpty) {
      subtitle = p.basename(outputPath);
    } else if (item.isCompilation) {
      subtitle = t.steamPublish.cells.subtitleCompilation;
    } else {
      subtitle = t.steamPublish.cells.subtitleProject;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              if (item.isCompilation) ...[
                Icon(
                  FluentIcons.stack_24_regular,
                  size: 12,
                  color: tokens.textDim,
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  item.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: tokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.fontMono.copyWith(
              fontSize: 11,
              color: tokens.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Publish state pill
// =============================================================================

/// Renders a publish-state badge in column 6. Three mutually-exclusive states:
/// `NO PACK` (no pack on disk), `PUBLISHED` (pack + Workshop id) or
/// `UNPUBLISHED` (pack but no Workshop id).
class SteamStateCell extends StatelessWidget {
  final PublishableItem item;

  const SteamStateCell({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasPack = item.hasPack;
    final publishedId = item.publishedSteamId;
    final hasPublished = publishedId != null && publishedId.isNotEmpty;

    final String label;
    final Color fg;
    final Color bg;
    final IconData? icon;
    final String tooltip;
    if (!hasPack) {
      label = t.steamPublish.cells.status.noPack;
      fg = tokens.warn;
      bg = tokens.warnBg;
      icon = FluentIcons.box_dismiss_24_regular;
      tooltip = hasPublished
          ? t.steamPublish.cells.tooltips.workshopNoPack(id: publishedId)
          : t.steamPublish.cells.tooltips.noPackOnDisk;
    } else if (hasPublished) {
      label = t.steamPublish.cells.status.published;
      fg = tokens.ok;
      bg = tokens.okBg;
      icon = FluentIcons.cloud_checkmark_24_regular;
      tooltip = t.steamPublish.cells.tooltips.workshopItem(id: publishedId);
    } else {
      label = t.steamPublish.cells.status.unpublished;
      fg = tokens.textDim;
      bg = tokens.panel;
      icon = FluentIcons.cloud_dismiss_24_regular;
      tooltip = t.steamPublish.cells.tooltips.packReadyNoId;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: StatusPill(
          label: label,
          foreground: fg,
          background: bg,
          icon: icon,
          tooltip: tooltip,
        ),
      ),
    );
  }
}

// =============================================================================
// Last published / exported date (mono, relative)
// =============================================================================

/// Renders the most recent publish timestamp (or last export) relative to the
/// ambient [clockProvider] in column 7.
class SteamLastPublishedCell extends ConsumerWidget {
  final PublishableItem item;

  const SteamLastPublishedCell({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final publishedAt = item.publishedAt;
    final exportedAt = item.exportedAt;

    final now = ref.watch(clockProvider)();

    // Prefer publish date when available. Fall back to export date; '-' when
    // both are unset (fresh item).
    final int? timestamp = publishedAt ?? (exportedAt > 0 ? exportedAt : null);
    if (timestamp == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          '-',
          style: tokens.fontMono.copyWith(
            fontSize: 11.5,
            color: tokens.textFaint,
          ),
        ),
      );
    }

    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final label = formatRelativeSince(date, now: now)!;

    final bool isOutdated =
        publishedAt != null && exportedAt > publishedAt;
    Color fg;
    IconData? icon;
    String prefix;
    if (publishedAt == null) {
      // Export-only row (never published).
      fg = tokens.textMid;
      icon = null;
      prefix = '';
    } else if (isOutdated) {
      fg = tokens.err;
      icon = FluentIcons.warning_24_filled;
      prefix = 'Outdated · ';
    } else {
      fg = tokens.ok;
      icon = FluentIcons.checkmark_circle_24_regular;
      prefix = '';
    }
    final tooltip = publishedAt != null
        ? t.steamPublish.cells.tooltips.lastPublished(date: formatAbsoluteDate(date) ?? '')
        : t.steamPublish.cells.tooltips.lastExported(date: formatAbsoluteDate(date) ?? '');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: fg),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                '$prefix$label',
                overflow: TextOverflow.ellipsis,
                style: tokens.fontMono.copyWith(
                  fontSize: 11.5,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Subs cell
// =============================================================================

/// Renders the Workshop subscriber count for the published translation mod.
/// Reads from [publishedSubsCacheProvider]; shows `-` for unpublished items
/// and for cache misses (e.g. before the boot-time refresh has resolved, or
/// when the API skipped the id).
class SteamSubsCell extends ConsumerWidget {
  final PublishableItem item;

  const SteamSubsCell({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final id = item.publishedSteamId;
    final cache = ref.watch(publishedSubsCacheProvider);

    final int? subs = (id != null && id.isNotEmpty) ? cache[id] : null;

    final String label = subs == null
        ? '-'
        : NumberFormat('#,###', 'en_US').format(subs).replaceAll(',', ' ');

    final tooltipMessage = (id == null || id.isEmpty)
        ? t.steamPublish.cells.tooltips.notPublishedYet
        : t.steamPublish.cells.tooltips.subscribers;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message: tooltipMessage,
        waitDuration: const Duration(milliseconds: 400),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: tokens.fontMono.copyWith(
              fontSize: 11.5,
              color: subs == null ? tokens.textFaint : tokens.textMid,
            ),
          ),
        ),
      ),
    );
  }
}
