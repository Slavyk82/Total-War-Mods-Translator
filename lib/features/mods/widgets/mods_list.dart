import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:twmt/features/mods/models/scan_log_message.dart';
import 'package:twmt/features/mods/widgets/scan_terminal_widget.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/mod_update_status.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/list_row.dart';

/// Column spec for the Mods list — mirrors the §7.1 filterable-list archetype
/// used by Projects. Columns: thumbnail, title+id, subscribers, last-updated,
/// status (imported/updated), changes, hide-toggle.
const List<ListRowColumn> modsColumns = [
  ListRowColumn.fixed(56),  // thumbnail
  ListRowColumn.flex(3),    // title + workshop id mono
  ListRowColumn.fixed(100), // subscribers
  ListRowColumn.fixed(140), // last update (relative)
  ListRowColumn.fixed(160), // imported state badge
  ListRowColumn.fixed(200), // changes cell / action
  ListRowColumn.fixed(56),  // hide toggle
];

/// Header + scrollable list of detected mods rendered with [ListRow].
///
/// Replaces the legacy [SfDataGrid]-based widget. All visual styling is drawn
/// from the active [TwmtThemeTokens] via `context.tokens`.
class ModsList extends StatelessWidget {
  final List<DetectedMod> mods;
  final void Function(String workshopId) onRowTap;
  final void Function(String workshopId, bool hide)? onToggleHidden;
  final void Function(String packFilePath)? onForceRedownload;
  final bool isLoading;
  final bool isScanning;
  final bool showingHidden;
  final Stream<ScanLogMessage>? scanLogStream;

  const ModsList({
    super.key,
    required this.mods,
    required this.onRowTap,
    this.onToggleHidden,
    this.onForceRedownload,
    this.isLoading = false,
    this.isScanning = false,
    this.showingHidden = false,
    this.scanLogStream,
  });

  @override
  Widget build(BuildContext context) {
    // Initial loading — terminal if we have the stream, else spinner.
    if (isLoading) {
      if (scanLogStream != null) {
        return ScanTerminalWidget(
          logStream: scanLogStream!,
          title: 'Scanning Workshop...',
        );
      }
      return _LoadingIndicator(message: 'Scanning Workshop folder...');
    }

    if (mods.isEmpty) {
      if (isScanning && scanLogStream != null) {
        return ScanTerminalWidget(
          logStream: scanLogStream!,
          title: 'Scanning Workshop...',
        );
      }
      return _EmptyState(showingHidden: showingHidden);
    }

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ModsListHeader(),
        Expanded(
          child: ListView.builder(
            itemCount: mods.length,
            itemBuilder: (ctx, i) {
              final mod = mods[i];
              return ListRow(
                columns: modsColumns,
                onTap: () => onRowTap(mod.workshopId),
                children: [
                  _Thumbnail(imageUrl: mod.imageUrl),
                  _TitleBlock(mod: mod),
                  _SubscribersCell(mod: mod),
                  _UpdatedCell(mod: mod),
                  _ImportedCell(mod: mod),
                  _ChangesCell(
                    mod: mod,
                    onForceRedownload: onForceRedownload,
                  ),
                  _HideCell(
                    mod: mod,
                    showingHidden: showingHidden,
                    onToggleHidden: onToggleHidden,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );

    if (isScanning && scanLogStream != null) {
      // Terminal overlay while refreshing.
      return Stack(
        children: [
          Opacity(opacity: 0.4, child: list),
          ScanTerminalWidget(
            logStream: scanLogStream!,
            title: 'Refreshing...',
          ),
        ],
      );
    }
    return list;
  }
}

// =============================================================================
// Header
// =============================================================================

class _ModsListHeader extends StatelessWidget {
  const _ModsListHeader();

  @override
  Widget build(BuildContext context) {
    return ListRowHeader(
      columns: modsColumns,
      labels: const ['', 'Mod', 'Subs', 'Updated', 'Status', 'Changes', ''],
    );
  }
}

// =============================================================================
// Cells
// =============================================================================

class _Thumbnail extends StatelessWidget {
  final String? imageUrl;
  const _Thumbnail({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    Widget fallback() => Icon(
          FluentIcons.image_off_24_regular,
          size: 20,
          color: tokens.textFaint,
        );

    Widget inner;
    if (imageUrl == null || imageUrl!.isEmpty) {
      inner = fallback();
    } else {
      final url = imageUrl!;
      final isRemote = url.startsWith('http://') || url.startsWith('https://');
      if (isRemote) {
        inner = CachedNetworkImage(
          imageUrl: url,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          placeholder: (_, _) => SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: tokens.accent,
            ),
          ),
          errorWidget: (_, _, _) => fallback(),
        );
      } else {
        inner = Image.file(
          File(url),
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback(),
        );
      }
    }
    return Center(
      child: Container(
        width: 40,
        height: 40,
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

class _TitleBlock extends StatelessWidget {
  final DetectedMod mod;
  const _TitleBlock({required this.mod});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            mod.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(
                FluentIcons.number_symbol_24_regular,
                size: 12,
                color: tokens.textDim,
              ),
              const SizedBox(width: 4),
              Text(
                mod.workshopId,
                style: tokens.fontMono.copyWith(
                  fontSize: 11,
                  color: tokens.textDim,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubscribersCell extends StatelessWidget {
  final DetectedMod mod;
  const _SubscribersCell({required this.mod});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final subs = mod.metadata?.modSubscribers ?? 0;
    final label = subs > 0
        ? NumberFormat('#,###', 'en_US').format(subs).replaceAll(',', ' ')
        : '-';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        label,
        style: tokens.fontMono.copyWith(
          fontSize: 11.5,
          color: tokens.textMid,
        ),
      ),
    );
  }
}

class _UpdatedCell extends StatelessWidget {
  final DetectedMod mod;
  const _UpdatedCell({required this.mod});

  static String _formatSince(DateTime date) {
    final diff = DateTime.now().difference(date);
    final days = diff.inDays;
    if (days == 0) {
      final hours = diff.inHours;
      return hours == 0 ? '< 1h' : '${hours}h';
    }
    if (days == 1) return '1 day';
    if (days < 30) return '$days days';
    if (days < 365) {
      final months = (days / 30).floor();
      return months == 1 ? '1 month' : '$months months';
    }
    final years = (days / 365).floor();
    return years == 1 ? '1 year' : '$years years';
  }

  static String _formatAbsolute(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _buildTooltip() {
    final lines = <String>[];
    if (mod.timeUpdated != null && mod.timeUpdated! > 0) {
      lines.add(
        'Steam Workshop: ${_formatAbsolute(DateTime.fromMillisecondsSinceEpoch(mod.timeUpdated! * 1000))}',
      );
    }
    if (mod.localFileLastModified != null && mod.localFileLastModified! > 0) {
      lines.add(
        'Local file: ${_formatAbsolute(DateTime.fromMillisecondsSinceEpoch(mod.localFileLastModified! * 1000))}',
      );
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (mod.timeUpdated == null || mod.timeUpdated == 0) {
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
    final steamDate =
        DateTime.fromMillisecondsSinceEpoch(mod.timeUpdated! * 1000);
    final label = _formatSince(steamDate);
    final status = mod.updateStatus;

    IconData? icon;
    Color fg = tokens.textMid;
    FontWeight weight = FontWeight.w500;
    List<String> tooltipLines = [_buildTooltip()];
    if (status == ModUpdateStatus.needsDownload) {
      icon = FluentIcons.arrow_download_24_filled;
      fg = tokens.err;
      weight = FontWeight.w600;
      tooltipLines = [
        'Steam version is newer than local file.',
        'Launch the game to download the update.',
        '',
        _buildTooltip(),
      ];
    } else if (status == ModUpdateStatus.hasChanges) {
      icon = FluentIcons.arrow_sync_24_filled;
      fg = tokens.warn;
      weight = FontWeight.w600;
      tooltipLines = [
        'Translation differences detected between source and project.',
        'Review changes to synchronize your translations.',
        '',
        _buildTooltip(),
      ];
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            style: tokens.fontMono.copyWith(
              fontSize: 11.5,
              color: fg,
              fontWeight: weight,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message: tooltipLines.join('\n'),
        child: row,
      ),
    );
  }
}

class _ImportedCell extends StatelessWidget {
  final DetectedMod mod;
  const _ImportedCell({required this.mod});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final imported = mod.isAlreadyImported;
    final fg = imported ? tokens.ok : tokens.textDim;
    final bg = imported ? tokens.okBg : tokens.panel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(tokens.radiusPill),
            border: Border.all(color: fg.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (imported) ...[
                Icon(
                  FluentIcons.checkmark_circle_24_regular,
                  size: 12,
                  color: fg,
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  imported ? 'Imported' : 'Not Imported',
                  style: tokens.fontBody.copyWith(
                    fontSize: 11.5,
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangesCell extends StatelessWidget {
  final DetectedMod mod;
  final void Function(String packFilePath)? onForceRedownload;
  const _ChangesCell({
    required this.mod,
    required this.onForceRedownload,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final status = mod.updateStatus;
    final analysis = mod.updateAnalysis;
    final imported = mod.isAlreadyImported;

    // Not imported — no analysis needed.
    if (!imported) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          '-',
          style: tokens.fontBody.copyWith(
            fontSize: 12,
            color: tokens.textFaint,
          ),
        ),
      );
    }

    if (status == ModUpdateStatus.needsDownload) {
      return _NeedsDownloadBadge(
        packFilePath: mod.packFilePath,
        onTap: onForceRedownload,
      );
    }

    if (status == ModUpdateStatus.upToDate) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.checkmark_circle_24_regular,
              size: 14,
              color: tokens.ok,
            ),
            const SizedBox(width: 6),
            Text(
              'Up to date',
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.ok,
              ),
            ),
          ],
        ),
      );
    }

    if (status == ModUpdateStatus.hasChanges && analysis != null) {
      return _HasChangesBadge(analysis: analysis);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '-',
        style: tokens.fontBody.copyWith(
          fontSize: 12,
          color: tokens.textFaint,
        ),
      ),
    );
  }
}

class _NeedsDownloadBadge extends StatelessWidget {
  final String packFilePath;
  final void Function(String packFilePath)? onTap;
  const _NeedsDownloadBadge({required this.packFilePath, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: 'Click to delete local file and force redownload',
          waitDuration: const Duration(milliseconds: 400),
          child: MouseRegion(
            cursor: enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: GestureDetector(
              onTap: enabled ? () => onTap!(packFilePath) : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.errBg,
                  borderRadius: BorderRadius.circular(tokens.radiusPill),
                  border: Border.all(color: tokens.err.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FluentIcons.arrow_download_24_filled,
                      size: 12,
                      color: tokens.err,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Download required',
                        style: tokens.fontBody.copyWith(
                          fontSize: 11.5,
                          color: tokens.err,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HasChangesBadge extends StatelessWidget {
  final ModUpdateAnalysis analysis;
  const _HasChangesBadge({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final lines = <String>[];
    if (analysis.hasNewUnits) {
      lines.add('+${analysis.newUnitsCount} new translations to add');
    }
    if (analysis.hasRemovedUnits) {
      lines.add('-${analysis.removedUnitsCount} translations removed');
    }
    if (analysis.hasModifiedUnits) {
      lines.add('~${analysis.modifiedUnitsCount} source texts changed');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: lines.join('\n'),
          waitDuration: const Duration(milliseconds: 400),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: tokens.errBg,
              borderRadius: BorderRadius.circular(tokens.radiusPill),
              border: Border.all(color: tokens.err.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.warning_24_filled,
                  size: 12,
                  color: tokens.err,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    analysis.summary,
                    style: tokens.fontBody.copyWith(
                      fontSize: 11.5,
                      color: tokens.err,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HideCell extends StatelessWidget {
  final DetectedMod mod;
  final bool showingHidden;
  final void Function(String workshopId, bool hide)? onToggleHidden;

  const _HideCell({
    required this.mod,
    required this.showingHidden,
    required this.onToggleHidden,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isChecked = mod.isHidden;
    return Center(
      child: Tooltip(
        message: showingHidden
            ? 'Uncheck to show this mod in the main list'
            : 'Check to hide this mod from the main list',
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (onToggleHidden != null) {
                onToggleHidden!(mod.workshopId, !mod.isHidden);
              }
            },
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isChecked ? tokens.accent : tokens.panel,
                borderRadius: BorderRadius.circular(tokens.radiusXs),
                border: Border.all(
                  color: isChecked ? tokens.accent : tokens.border,
                  width: 1.5,
                ),
              ),
              child: isChecked
                  ? Icon(
                      FluentIcons.checkmark_16_filled,
                      size: 14,
                      color: tokens.accentFg,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Empty + loading helpers
// =============================================================================

class _EmptyState extends StatelessWidget {
  final bool showingHidden;
  const _EmptyState({required this.showingHidden});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            showingHidden
                ? FluentIcons.eye_off_24_regular
                : FluentIcons.cube_24_regular,
            size: 56,
            color: tokens.textFaint,
          ),
          const SizedBox(height: 16),
          Text(
            showingHidden ? 'No hidden mods' : 'No mods found',
            style: tokens.fontDisplay.copyWith(
              fontSize: 18,
              color: tokens.text,
              fontStyle: tokens.fontDisplayItalic
                  ? FontStyle.italic
                  : FontStyle.normal,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            showingHidden
                ? 'Use the checkbox to hide mods from the list'
                : 'Subscribe to mods on Steam Workshop or download them manually',
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.textDim,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  final String message;
  const _LoadingIndicator({required this.message});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: tokens.accent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.textDim,
            ),
          ),
        ],
      ),
    );
  }
}
