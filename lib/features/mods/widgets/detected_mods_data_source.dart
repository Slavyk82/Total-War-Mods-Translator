import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Data source for Syncfusion DataGrid displaying detected mods
class DetectedModsDataSource extends DataGridSource {
  DetectedModsDataSource({
    required List<DetectedMod> mods,
    required this.onRowTap,
  }) {
    _mods = mods;
    _buildDataGridRows();
  }

  List<DetectedMod> _mods = [];
  List<DataGridRow> _dataGridRows = [];
  final Function(String workshopId) onRowTap;

  @override
  List<DataGridRow> get rows => _dataGridRows;

  /// Update the data source with new mods
  void updateMods(List<DetectedMod> mods) {
    if (_mods == mods) return;
    _mods = mods;
    _buildDataGridRows();
    notifyListeners();
  }

  /// Build data grid rows from mods
  void _buildDataGridRows() {
    _dataGridRows = _mods.map<DataGridRow>((mod) {
      return DataGridRow(
        cells: [
          DataGridCell<String?>(
            columnName: 'image',
            value: mod.imageUrl,
          ),
          DataGridCell<String>(
            columnName: 'workshop_id',
            value: mod.workshopId,
          ),
          DataGridCell<String>(
            columnName: 'name',
            value: mod.name,
          ),
          DataGridCell<int>(
            columnName: 'subscribers',
            value: mod.metadata?.modSubscribers ?? 0,
          ),
          DataGridCell<bool>(
            columnName: 'imported',
            value: mod.isAlreadyImported,
          ),
        ],
      );
    }).toList();
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final imageUrl = row.getCells()[0].value as String?;
    final workshopId = row.getCells()[1].value.toString();
    final modName = row.getCells()[2].value.toString();
    final subscribers = row.getCells()[3].value as int;
    final isImported = row.getCells()[4].value as bool;

    return DataGridRowAdapter(
      cells: [
        // Mod Image
        RepaintBoundary(
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(4),
            child: _ModImage(imageUrl: imageUrl),
          ),
        ),
        // Workshop ID
        RepaintBoundary(
          child: _DataGridCell(
            text: workshopId,
            fontFamily: 'monospace',
          ),
        ),
        // Mod Name
        RepaintBoundary(
          child: _DataGridCell(
            text: modName,
            fontWeight: FontWeight.w600,
          ),
        ),
        // Subscribers
        RepaintBoundary(
          child: _DataGridCell(
            text: subscribers > 0 ? subscribers.toString() : '-',
          ),
        ),
        // Imported Status
        RepaintBoundary(
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(8),
            child: _ImportedBadge(isImported: isImported),
          ),
        ),
      ],
    );
  }
}

/// Performance-optimized DataGrid cell widget
class _DataGridCell extends StatelessWidget {
  final String text;
  final FontWeight? fontWeight;
  final String? fontFamily;

  const _DataGridCell({
    required this.text,
    this.fontWeight,
    this.fontFamily,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: fontWeight,
              fontFamily: fontFamily,
            ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Mod image widget for the DataGrid
class _ModImage extends StatelessWidget {
  final String? imageUrl;

  const _ModImage({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          FluentIcons.image_off_24_regular,
          size: 24,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    // Check if it's a local file path or a URL
    final isLocalFile = !imageUrl!.startsWith('http://') && 
                        !imageUrl!.startsWith('https://');

    if (isLocalFile) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(imageUrl!),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              FluentIcons.image_alt_text_24_regular,
              size: 24,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: 48,
          height: 48,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            FluentIcons.image_alt_text_24_regular,
            size: 24,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Imported status badge widget
class _ImportedBadge extends StatelessWidget {
  final bool isImported;

  const _ImportedBadge({required this.isImported});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!isImported) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Not Imported',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.checkmark_circle_24_regular,
            size: 14,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            'Imported',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

