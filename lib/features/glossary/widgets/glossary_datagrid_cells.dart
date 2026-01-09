import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/domain/glossary_entry.dart';

/// Performance-optimized cell widgets for GlossaryDataGrid

/// Text cell widget for glossary entries
class GlossaryTextCell extends StatelessWidget {
  final String text;

  const GlossaryTextCell({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Case sensitive indicator cell
class CaseSensitiveCell extends StatelessWidget {
  final bool isCaseSensitive;

  const CaseSensitiveCell({super.key, required this.isCaseSensitive});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8.0),
      child: Icon(
        isCaseSensitive
            ? FluentIcons.checkmark_24_regular
            : FluentIcons.dismiss_24_regular,
        size: 16,
        color: isCaseSensitive
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    );
  }
}

/// Actions cell with edit and delete buttons
class GlossaryActionsCell extends StatelessWidget {
  final GlossaryEntry entry;
  final void Function(GlossaryEntry) onEdit;
  final void Function(GlossaryEntry) onDelete;

  const GlossaryActionsCell({
    super.key,
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Edit button
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onEdit(entry),
              child: Icon(
                FluentIcons.edit_24_regular,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Delete button
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onDelete(entry),
              child: Icon(
                FluentIcons.delete_24_regular,
                size: 20,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
