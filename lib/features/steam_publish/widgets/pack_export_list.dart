import 'package:flutter/material.dart';

import '../providers/steam_publish_providers.dart';
import 'pack_export_card.dart';

/// Scrollable list of recent pack export cards.
class PackExportList extends StatelessWidget {
  final List<RecentPackExport> exports;
  final Set<String> selectedPaths;
  final ValueChanged<String>? onToggleSelection;

  const PackExportList({
    super.key,
    required this.exports,
    this.selectedPaths = const {},
    this.onToggleSelection,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: exports.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final export = exports[index];
        return PackExportCard(
          recentExport: export,
          isSelected: selectedPaths.contains(export.export.outputPath),
          onSelectionChanged: onToggleSelection != null
              ? (_) => onToggleSelection!(export.export.outputPath)
              : null,
        );
      },
    );
  }
}
