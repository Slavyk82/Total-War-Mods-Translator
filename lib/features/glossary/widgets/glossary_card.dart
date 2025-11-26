import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:twmt/services/glossary/models/glossary.dart';

/// A card displaying glossary information in Fluent Design style.
///
/// Shows glossary name, type (universal/game-specific), entry count,
/// description, and last modified time.
class GlossaryCard extends StatefulWidget {
  final Glossary glossary;
  final String? gameName;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const GlossaryCard({
    super.key,
    required this.glossary,
    this.gameName,
    this.onTap,
    this.onDelete,
  });

  @override
  State<GlossaryCard> createState() => _GlossaryCardState();
}

class _GlossaryCardState extends State<GlossaryCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _isHovered
                ? theme.colorScheme.surface.withValues(alpha: 0.8)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered
                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                  : theme.colorScheme.outline.withValues(alpha: 0.2),
              width: 1,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: theme.shadowColor.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                if (widget.glossary.description != null &&
                    widget.glossary.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildDescription(context),
                ],
                const SizedBox(height: 12),
                _buildFooter(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final glossary = widget.glossary;
    final isUniversal = glossary.isGlobal;

    return Row(
      children: [
        // Type icon
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isUniversal
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isUniversal
                ? FluentIcons.globe_24_regular
                : FluentIcons.games_24_regular,
            size: 20,
            color: isUniversal
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSecondaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        // Name and type badge
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                glossary.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              _buildTypeBadge(context),
            ],
          ),
        ),
        // Entry count badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.text_field_24_regular,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '${glossary.entryCount}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        // Delete button
        if (widget.onDelete != null) ...[
          const SizedBox(width: 8),
          _buildDeleteButton(context),
        ],
      ],
    );
  }

  Widget _buildTypeBadge(BuildContext context) {
    final theme = Theme.of(context);
    final isUniversal = widget.glossary.isGlobal;
    final label = isUniversal ? 'Universal' : widget.gameName ?? 'Game-specific';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isUniversal
            ? theme.colorScheme.primary.withValues(alpha: 0.1)
            : theme.colorScheme.secondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUniversal
                ? FluentIcons.globe_24_regular
                : FluentIcons.games_24_regular,
            size: 12,
            color: isUniversal
                ? theme.colorScheme.primary
                : theme.colorScheme.secondary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isUniversal
                  ? theme.colorScheme.primary
                  : theme.colorScheme.secondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      widget.glossary.description!,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    final lastModified = DateTime.fromMillisecondsSinceEpoch(
      widget.glossary.updatedAt,
    );
    final mutedColor = theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5);

    return Row(
      children: [
        Icon(
          FluentIcons.clock_24_regular,
          size: 14,
          color: mutedColor,
        ),
        const SizedBox(width: 4),
        Text(
          'Updated ${timeago.format(lastModified)}',
          style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
        ),
        const Spacer(),
        Icon(
          FluentIcons.chevron_right_24_regular,
          size: 16,
          color: _isHovered
              ? theme.colorScheme.primary
              : theme.colorScheme.outline.withValues(alpha: 0.5),
        ),
      ],
    );
  }

  Widget _buildDeleteButton(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          // Absorb event to prevent card tap
        },
        onTap: widget.onDelete,
        child: Tooltip(
          message: 'Delete Glossary',
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.error.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              FluentIcons.delete_24_regular,
              size: 18,
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ),
    );
  }
}

