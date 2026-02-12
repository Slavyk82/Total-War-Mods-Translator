import 'package:flutter/material.dart';

import '../providers/steam_publish_providers.dart';
import 'pack_export_card.dart';

/// Scrollable list of recent pack export cards.
class PackExportList extends StatelessWidget {
  final List<RecentPackExport> exports;

  const PackExportList({super.key, required this.exports});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: exports.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return PackExportCard(recentExport: exports[index]);
      },
    );
  }
}
