import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/config/tooltip_strings.dart';
import '../providers/editor_providers.dart';
import 'editor_toolbar_model_selector.dart';
import 'editor_toolbar_skip_tm.dart';
import 'editor_toolbar_mod_rule.dart';

/// Top toolbar for the translation editor
///
/// Contains LLM model selector, action buttons, and search
class EditorToolbar extends ConsumerStatefulWidget {
  final String projectId;
  final String languageId;
  final VoidCallback onTranslationSettings;
  final VoidCallback onTranslateAll;
  final VoidCallback onTranslateSelected;
  final VoidCallback onValidate;
  final VoidCallback onRescanValidation;
  final VoidCallback onExport;
  final VoidCallback onImportPack;

  const EditorToolbar({
    super.key,
    required this.projectId,
    required this.languageId,
    required this.onTranslationSettings,
    required this.onTranslateAll,
    required this.onTranslateSelected,
    required this.onValidate,
    required this.onRescanValidation,
    required this.onExport,
    required this.onImportPack,
  });

  @override
  ConsumerState<EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends ConsumerState<EditorToolbar> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectionState = ref.watch(editorSelectionProvider);

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Responsive breakpoints - adjusted for minimum window size of 800px
          final isCompact = constraints.maxWidth < 1200;
          final isVeryCompact = constraints.maxWidth < 1000;
          final searchMinWidth = 125.0;
          final searchMaxWidth = 172.0;

          return Row(
            children: [
              const SizedBox(width: 16),

              // LLM Model selector - hide label in very compact mode
              EditorToolbarModelSelector(compact: isVeryCompact),
              SizedBox(width: isCompact ? 8 : 16),

              // Skip TM checkbox - icon only in compact mode
              EditorToolbarSkipTm(compact: isCompact),
              SizedBox(width: isCompact ? 8 : 16),

              // Action buttons - use Expanded to fill available space
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Translation Settings button
                      _buildActionButton(
                        icon: FluentIcons.settings_24_regular,
                        label: 'Settings',
                        tooltip: TooltipStrings.editorSettings,
                        onPressed: widget.onTranslationSettings,
                        compact: isCompact,
                      ),
                      SizedBox(width: isCompact ? 4 : 8),

                      // Mod Rule button
                      EditorToolbarModRule(
                        compact: isCompact,
                        projectId: widget.projectId,
                      ),
                      SizedBox(width: isCompact ? 8 : 16),

                      // Action buttons
                      _buildActionButton(
                        icon: FluentIcons.translate_24_regular,
                        label: 'Translate All',
                        tooltip: TooltipStrings.editorTranslateAll,
                        onPressed: widget.onTranslateAll,
                        compact: isCompact,
                      ),
                      SizedBox(width: isCompact ? 4 : 8),
                      _buildActionButton(
                        icon: FluentIcons.translate_24_filled,
                        label: 'Translate Selected',
                        tooltip: TooltipStrings.editorTranslateSelected,
                        onPressed: selectionState.hasSelection
                          ? widget.onTranslateSelected
                          : null,
                        compact: isCompact,
                      ),
                      SizedBox(width: isCompact ? 4 : 8),
                      _buildActionButton(
                        icon: FluentIcons.checkmark_circle_24_regular,
                        label: 'Validate',
                        tooltip: TooltipStrings.editorValidate,
                        onPressed: widget.onValidate,
                        compact: isCompact,
                      ),
                      SizedBox(width: isCompact ? 4 : 8),
                      _buildActionButton(
                        icon: FluentIcons.arrow_sync_24_regular,
                        label: 'Rescan',
                        tooltip: TooltipStrings.editorRescanValidation,
                        onPressed: widget.onRescanValidation,
                        compact: isCompact,
                      ),
                      SizedBox(width: isCompact ? 4 : 8),
                      _buildActionButton(
                        icon: FluentIcons.arrow_import_24_regular,
                        label: 'Import pack',
                        tooltip: TooltipStrings.editorImportPack,
                        onPressed: widget.onImportPack,
                        color: Colors.blue.shade700,
                        compact: isCompact,
                      ),
                      SizedBox(width: isCompact ? 4 : 8),
                      _buildActionButton(
                        icon: FluentIcons.arrow_export_24_regular,
                        label: 'Generate pack',
                        tooltip: TooltipStrings.editorExport,
                        onPressed: widget.onExport,
                        color: Colors.green.shade700,
                        compact: isCompact,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: isCompact ? 8 : 16),

              // Search field - responsive with smaller constraints
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: searchMinWidth,
                  maxWidth: searchMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: isVeryCompact ? 'Search...' : 'Search translations...',
                      prefixIcon: const Icon(
                        FluentIcons.search_24_regular,
                        size: 18,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                        ? FluentIconButton(
                            icon: const Icon(FluentIcons.dismiss_24_regular, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              ref.read(editorFilterProvider.notifier)
                                .setSearchQuery('');
                            },
                            tooltip: 'Clear search',
                            size: 28,
                            iconSize: 16,
                          )
                        : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (value) {
                      ref.read(editorFilterProvider.notifier)
                        .setSearchQuery(value);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    String? tooltip,
    Color? color,
    bool compact = false,
  }) {
    final isEnabled = onPressed != null;
    final buttonColor = color ?? Theme.of(context).colorScheme.primary;

    Widget button = MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: isEnabled
              ? buttonColor.withValues(alpha: 0.1)
              : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isEnabled
                ? buttonColor
                : Colors.grey.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isEnabled
                  ? buttonColor
                  : Colors.grey,
              ),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isEnabled
                      ? buttonColor
                      : Colors.grey,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    // In compact mode, always show tooltip since label is hidden
    final effectiveTooltip = compact ? (tooltip ?? label) : tooltip;
    if (effectiveTooltip != null) {
      return Tooltip(
        message: effectiveTooltip,
        waitDuration: const Duration(milliseconds: 500),
        child: button,
      );
    }

    return button;
  }
}
