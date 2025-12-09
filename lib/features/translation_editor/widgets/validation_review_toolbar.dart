import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// Severity filter options for validation review.
enum ValidationSeverityFilter { all, errorsOnly, warningsOnly }

/// Toolbar for validation review with filters, search, and bulk actions.
class ValidationReviewToolbar extends StatelessWidget {
  const ValidationReviewToolbar({
    super.key,
    required this.severityFilter,
    required this.selectedCount,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onBulkAccept,
    required this.onBulkReject,
  });

  final ValidationSeverityFilter severityFilter;
  final int selectedCount;
  final void Function(ValidationSeverityFilter) onFilterChanged;
  final void Function(String) onSearchChanged;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;
  final VoidCallback onBulkAccept;
  final VoidCallback onBulkReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelection = selectedCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          // Filter chips
          _FilterChip(
            label: 'All',
            icon: null,
            isActive: severityFilter == ValidationSeverityFilter.all,
            onTap: () => onFilterChanged(ValidationSeverityFilter.all),
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Errors',
            icon: FluentIcons.error_circle_24_regular,
            isActive: severityFilter == ValidationSeverityFilter.errorsOnly,
            onTap: () => onFilterChanged(ValidationSeverityFilter.errorsOnly),
            color: Colors.red[700]!,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Warnings',
            icon: FluentIcons.warning_24_regular,
            isActive: severityFilter == ValidationSeverityFilter.warningsOnly,
            onTap: () => onFilterChanged(ValidationSeverityFilter.warningsOnly),
            color: Colors.orange[700]!,
          ),

          const SizedBox(width: 24),

          // Search
          SizedBox(
            width: 300,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by key, text, or description...',
                prefixIcon: const Icon(FluentIcons.search_24_regular, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
              ),
              onChanged: onSearchChanged,
            ),
          ),

          const Spacer(),

          // Selection info and bulk actions
          if (hasSelection) ...[
            Text(
              '$selectedCount selected',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 16),
            _ActionButton(
              label: 'Accept All',
              icon: FluentIcons.checkmark_24_regular,
              color: Colors.green[700]!,
              onPressed: onBulkAccept,
            ),
            const SizedBox(width: 8),
            _ActionButton(
              label: 'Reject All',
              icon: FluentIcons.dismiss_24_regular,
              color: Colors.red[700]!,
              onPressed: onBulkReject,
            ),
            const SizedBox(width: 8),
            _TextButton(
              label: 'Deselect',
              onTap: onDeselectAll,
            ),
          ] else ...[
            _SelectAllButton(onTap: onSelectAll),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
    required this.color,
  });

  final String label;
  final IconData? icon;
  final bool isActive;
  final VoidCallback onTap;
  final Color color;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isActive
                ? widget.color.withValues(alpha: 0.1)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.isActive ? widget.color : theme.dividerColor,
              width: widget.isActive ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 16,
                  color: widget.isActive
                      ? widget.color
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color:
                      widget.isActive ? widget.color : theme.colorScheme.onSurface,
                  fontWeight:
                      widget.isActive ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: widget.color),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: widget.color),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  color: widget.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class _SelectAllButton extends StatelessWidget {
  const _SelectAllButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.checkbox_checked_24_regular,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              const Text('Select All'),
            ],
          ),
        ),
      ),
    );
  }
}
