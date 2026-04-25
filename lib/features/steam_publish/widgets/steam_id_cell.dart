import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/theme/twmt_theme_tokens.dart';

import '../providers/steam_publish_providers.dart';

/// Cell rendered in the Steam Publish list's Steam ID column.
///
/// Three modes selected from `(hasPack, hasPublishedId, _isEditing)`:
///   - Read (id present)  → mono ID + pencil
///   - Read (no id)       → em dash + pencil
///   - Edit               → TextField + Save + Cancel (added in later tasks)
class SteamIdCell extends ConsumerStatefulWidget {
  final PublishableItem item;

  const SteamIdCell({super.key, required this.item});

  @override
  ConsumerState<SteamIdCell> createState() => _SteamIdCellState();
}

class _SteamIdCellState extends ConsumerState<SteamIdCell> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final id = widget.item.publishedSteamId;
    final hasId = id != null && id.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              hasId ? id : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.fontMono.copyWith(
                fontSize: 12,
                color: hasId ? tokens.textMid : tokens.textFaint,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _iconButton(
            context: context,
            icon: FluentIcons.edit_24_regular,
            tooltip: hasId ? 'Edit Workshop id' : 'Set Workshop id',
            onTap: () {
              // Filled in by Task 3.
            },
          ),
        ],
      ),
    );
  }

  /// Square 28×28 icon button — same shape as the action cell's `_iconButton`.
  Widget _iconButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    final tokens = context.tokens;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.panel2,
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: Icon(icon, size: 14, color: tokens.textMid),
          ),
        ),
      ),
    );
  }
}
