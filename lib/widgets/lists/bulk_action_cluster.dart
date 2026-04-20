import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';

/// Compact Accept/Reject/Deselect cluster rendered in the FilterToolbar
/// trailing slot whenever at least one selected row has open validation
/// issues. Matches the editor toolbar's tokenised mini-action rail.
class BulkActionCluster extends StatelessWidget {
  const BulkActionCluster({
    super.key,
    required this.selectedCount,
    required this.onAccept,
    required this.onReject,
    required this.onDeselect,
  });

  final int selectedCount;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onDeselect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$selectedCount selected',
          style: tokens.fontMono.copyWith(
            fontSize: 12,
            color: tokens.textDim,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 10),
        SmallIconButton(
          icon: FluentIcons.checkmark_24_regular,
          tooltip: 'Accept selected',
          size: 32,
          iconSize: 16,
          foreground: tokens.accent,
          onTap: onAccept,
        ),
        const SizedBox(width: 6),
        SmallIconButton(
          icon: FluentIcons.dismiss_24_regular,
          tooltip: 'Reject selected',
          size: 32,
          iconSize: 16,
          foreground: tokens.err,
          onTap: onReject,
        ),
        const SizedBox(width: 6),
        SmallIconButton(
          icon: FluentIcons.dismiss_circle_24_regular,
          tooltip: 'Deselect all',
          size: 32,
          iconSize: 16,
          onTap: onDeselect,
        ),
      ],
    );
  }
}
