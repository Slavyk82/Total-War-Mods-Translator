import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:twmt/features/mods/models/scan_log_message.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/features/mods/widgets/scan_terminal_widget.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/mod_update_status.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/list_row.dart';
import 'package:twmt/widgets/lists/relative_date.dart';
import 'package:twmt/widgets/lists/status_pill.dart';

/// Column spec for the Mods list — mirrors the §7.1 filterable-list archetype
/// used by Projects. Columns: thumbnail, title+id, subscribers, last-updated,
/// status (imported/updated), changes, hide-toggle.
const List<ListRowColumn> modsColumns = [
  ListRowColumn.fixed(80),  // thumbnail
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
                // Null height → row grows to fit the 80px thumbnail. The
                // default 56px would crop the cover vertically.
                height: null,
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

class _ModsListHeader extends ConsumerWidget {
  const _ModsListHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final sort = ref.watch(modsSortProvider);
    final notifier = ref.read(modsSortProvider.notifier);

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          // thumbnail spacer (column 0)
          const SizedBox(width: 80),
          Expanded(
            flex: 3,
            child: _SortableHeaderCell(
              label: 'Mod',
              field: ModsSortField.name,
              sort: sort,
              onTap: () => notifier.toggle(ModsSortField.name),
            ),
          ),
          SizedBox(
            width: 100,
            child: _SortableHeaderCell(
              label: 'Subs',
              field: ModsSortField.subscribers,
              sort: sort,
              onTap: () => notifier.toggle(ModsSortField.subscribers),
            ),
          ),
          SizedBox(
            width: 140,
            child: _SortableHeaderCell(
              label: 'Updated',
              field: ModsSortField.updated,
              sort: sort,
              onTap: () => notifier.toggle(ModsSortField.updated),
            ),
          ),
          SizedBox(width: 160, child: _PlainHeaderText('Status')),
          SizedBox(width: 200, child: _PlainHeaderText('Changes')),
          // hide toggle column (no label)
          const SizedBox(width: 56),
        ],
      ),
    );
  }
}

/// Static header cell for non-sortable columns. Mirrors the look of
/// [ListRowHeader] (mono 11px caps, textDim).
class _PlainHeaderText extends StatelessWidget {
  final String label;
  const _PlainHeaderText(this.label);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Text(
      label.toUpperCase(),
      style: tokens.fontMono.copyWith(
        fontSize: 11,
        color: tokens.textDim,
        letterSpacing: 0.8,
      ),
    );
  }
}

/// Clickable header cell with a sort indicator arrow when active.
class _SortableHeaderCell extends StatelessWidget {
  final String label;
  final ModsSortField field;
  final ModsSortState sort;
  final VoidCallback onTap;

  const _SortableHeaderCell({
    required this.label,
    required this.field,
    required this.sort,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isActive = sort.field == field;
    final color = isActive ? tokens.accent : tokens.textDim;
    final icon = isActive
        ? (sort.ascending
            ? FluentIcons.arrow_up_16_filled
            : FluentIcons.arrow_down_16_filled)
        : null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: tokens.fontMono.copyWith(
                fontSize: 11,
                color: color,
                letterSpacing: 0.8,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 4),
              Icon(icon, size: 12, color: color),
            ],
          ],
        ),
      ),
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
          size: 44,
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
          width: 80,
          height: 80,
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
          width: 80,
          height: 80,
          cacheWidth: 160,
          cacheHeight: 160,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback(),
        );
      }
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

class _UpdatedCell extends ConsumerWidget {
  final DetectedMod mod;
  const _UpdatedCell({required this.mod});

  String _buildTooltip() {
    final lines = <String>[];
    if (mod.timeUpdated != null && mod.timeUpdated! > 0) {
      lines.add(
        'Steam Workshop: ${formatAbsoluteDate(DateTime.fromMillisecondsSinceEpoch(mod.timeUpdated! * 1000))}',
      );
    }
    if (mod.localFileLastModified != null && mod.localFileLastModified! > 0) {
      lines.add(
        'Local file: ${formatAbsoluteDate(DateTime.fromMillisecondsSinceEpoch(mod.localFileLastModified! * 1000))}',
      );
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final now = ref.watch(clockProvider)();
    final steamDate =
        DateTime.fromMillisecondsSinceEpoch(mod.timeUpdated! * 1000);
    final label = formatRelativeSince(steamDate, now: now)!;
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
        child: StatusPill(
          label: imported ? 'Imported' : 'Not Imported',
          foreground: fg,
          background: bg,
          icon: imported ? FluentIcons.checkmark_circle_24_regular : null,
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
        child: StatusPill(
          label: 'Download required',
          foreground: tokens.err,
          background: tokens.errBg,
          icon: FluentIcons.arrow_download_24_filled,
          tooltip: 'Click to delete local file and force redownload',
          onTap: enabled ? () => onTap!(packFilePath) : null,
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
        child: StatusPill(
          label: analysis.summary,
          foreground: tokens.err,
          background: tokens.errBg,
          icon: FluentIcons.warning_24_filled,
          tooltip: lines.join('\n'),
        ),
      ),
    );
  }
}

class _HideCell extends StatefulWidget {
  final DetectedMod mod;
  final bool showingHidden;
  final void Function(String workshopId, bool hide)? onToggleHidden;

  const _HideCell({
    required this.mod,
    required this.showingHidden,
    required this.onToggleHidden,
  });

  @override
  State<_HideCell> createState() => _HideCellState();
}

class _HideCellState extends State<_HideCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isHidden = widget.mod.isHidden;
    // The icon advertises the action that will run on click:
    // - hidden mod → "show" (eye)
    // - visible mod → "hide" (eye_off)
    final icon = isHidden
        ? FluentIcons.eye_24_regular
        : FluentIcons.eye_off_24_regular;
    final tooltip = isHidden
        ? 'Show this mod in the main list'
        : 'Hide this mod from the main list';
    final fg = _hovered ? tokens.accent : tokens.textDim;

    return Center(
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              widget.onToggleHidden?.call(widget.mod.workshopId, !isHidden);
            },
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _hovered ? tokens.accentBg : Colors.transparent,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
              child: Icon(icon, size: 18, color: fg),
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
              fontStyle: tokens.fontDisplayStyle,
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
