import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// Detailed change report showing what changed between mod versions
class ModChangeReport extends StatefulWidget {
  final int unitsAdded;
  final int unitsModified;
  final int unitsDeleted;
  final List<String>? addedUnitKeys;
  final List<String>? modifiedUnitKeys;
  final List<String>? deletedUnitKeys;

  const ModChangeReport({
    super.key,
    required this.unitsAdded,
    required this.unitsModified,
    required this.unitsDeleted,
    this.addedUnitKeys,
    this.modifiedUnitKeys,
    this.deletedUnitKeys,
  });

  @override
  State<ModChangeReport> createState() => _ModChangeReportState();
}

class _ModChangeReportState extends State<ModChangeReport> {
  bool _addedExpanded = true;
  bool _modifiedExpanded = true;
  bool _deletedExpanded = true;
  String _searchFilter = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary header
        _buildSummaryHeader(theme),
        const SizedBox(height: 16),

        // Search filter
        if (_hasAnyChanges)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildSearchField(theme),
          ),

        // Change sections
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.unitsAdded > 0)
                  _buildChangeSection(
                    theme: theme,
                    title: 'Added Units',
                    icon: FluentIcons.add_24_regular,
                    color: const Color(0xFF107C10),
                    backgroundColor: const Color(0xFFDFF6DD),
                    count: widget.unitsAdded,
                    keys: widget.addedUnitKeys ?? [],
                    isExpanded: _addedExpanded,
                    onToggle: () => setState(() => _addedExpanded = !_addedExpanded),
                  ),
                if (widget.unitsModified > 0) ...[
                  if (widget.unitsAdded > 0) const SizedBox(height: 12),
                  _buildChangeSection(
                    theme: theme,
                    title: 'Modified Units',
                    icon: FluentIcons.edit_24_regular,
                    color: const Color(0xFFF7630C),
                    backgroundColor: const Color(0xFFFFF4CE),
                    count: widget.unitsModified,
                    keys: widget.modifiedUnitKeys ?? [],
                    isExpanded: _modifiedExpanded,
                    onToggle: () => setState(() => _modifiedExpanded = !_modifiedExpanded),
                  ),
                ],
                if (widget.unitsDeleted > 0) ...[
                  if (widget.unitsAdded > 0 || widget.unitsModified > 0)
                    const SizedBox(height: 12),
                  _buildChangeSection(
                    theme: theme,
                    title: 'Deleted Units',
                    icon: FluentIcons.delete_24_regular,
                    color: const Color(0xFFD13438),
                    backgroundColor: const Color(0xFFFDE7E9),
                    count: widget.unitsDeleted,
                    keys: widget.deletedUnitKeys ?? [],
                    isExpanded: _deletedExpanded,
                    onToggle: () => setState(() => _deletedExpanded = !_deletedExpanded),
                  ),
                ],
                if (!_hasAnyChanges)
                  _buildEmptyState(theme),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryHeader(ThemeData theme) {
    final totalChanges = widget.unitsAdded + widget.unitsModified + widget.unitsDeleted;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.history_24_regular,
            color: theme.colorScheme.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Change Summary',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$totalChanges total changes',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
          if (widget.unitsAdded > 0)
            _buildSummaryBadge(
              '+${widget.unitsAdded}',
              const Color(0xFF107C10),
            ),
          if (widget.unitsModified > 0) ...[
            const SizedBox(width: 8),
            _buildSummaryBadge(
              '~${widget.unitsModified}',
              const Color(0xFFF7630C),
            ),
          ],
          if (widget.unitsDeleted > 0) ...[
            const SizedBox(width: 8),
            _buildSummaryBadge(
              '-${widget.unitsDeleted}',
              const Color(0xFFD13438),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Filter by key...',
        prefixIcon: const Icon(FluentIcons.search_24_regular),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onChanged: (value) => setState(() => _searchFilter = value.toLowerCase()),
    );
  }

  Widget _buildChangeSection({
    required ThemeData theme,
    required String title,
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required int count,
    required List<String> keys,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    final filteredKeys = _searchFilter.isEmpty
        ? keys
        : keys.where((key) => key.toLowerCase().contains(_searchFilter)).toList();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          _buildSectionHeader(
            theme: theme,
            title: title,
            icon: icon,
            color: color,
            backgroundColor: backgroundColor,
            count: filteredKeys.length,
            isExpanded: isExpanded,
            onToggle: onToggle,
          ),
          if (isExpanded)
            _buildKeyList(
              theme: theme,
              keys: filteredKeys,
              color: color,
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required ThemeData theme,
    required String title,
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required int count,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: isExpanded
                ? const BorderRadius.only(
                    topLeft: Radius.circular(7),
                    topRight: Radius.circular(7),
                  )
                : BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isExpanded
                    ? FluentIcons.chevron_up_24_regular
                    : FluentIcons.chevron_down_24_regular,
                color: color,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeyList({
    required ThemeData theme,
    required List<String> keys,
    required Color color,
  }) {
    if (keys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'No matching keys',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.all(8),
        itemCount: keys.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          return _KeyListItem(
            keyName: keys[index],
            color: color,
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.checkmark_circle_24_regular,
              size: 48,
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No Changes',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This version has no changes',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasAnyChanges =>
      widget.unitsAdded > 0 || widget.unitsModified > 0 || widget.unitsDeleted > 0;
}

class _KeyListItem extends StatefulWidget {
  final String keyName;
  final Color color;

  const _KeyListItem({
    required this.keyName,
    required this.color,
  });

  @override
  State<_KeyListItem> createState() => _KeyListItemState();
}

class _KeyListItemState extends State<_KeyListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _isHovered
              ? widget.color.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.keyName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
