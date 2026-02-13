import 'package:flutter/material.dart';

import '../providers/steam_publish_providers.dart';
import 'pack_export_card.dart';

/// Scrollable list of publishable item cards.
class PackExportList extends StatelessWidget {
  final List<PublishableItem> items;
  final Set<String> selectedPaths;
  final ValueChanged<String>? onToggleSelection;

  const PackExportList({
    super.key,
    required this.items,
    this.selectedPaths = const {},
    this.onToggleSelection,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return PackExportCard(
          item: item,
          isSelected: selectedPaths.contains(item.outputPath),
          onSelectionChanged: onToggleSelection != null
              ? (_) => onToggleSelection!(item.outputPath)
              : null,
        );
      },
    );
  }
}
