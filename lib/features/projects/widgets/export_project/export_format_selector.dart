import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../../models/domain/export_history.dart';

/// Fluent Design widget for selecting export format.
///
/// Displays available export formats (pack, CSV, Excel, TMX) with
/// descriptions and icons following Fluent Design patterns.
class ExportFormatSelector extends StatelessWidget {
  final ExportFormat selectedFormat;
  final ValueChanged<ExportFormat> onFormatChanged;

  const ExportFormatSelector({
    super.key,
    required this.selectedFormat,
    required this.onFormatChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        _buildFormatOption(
          ExportFormat.pack,
          'Total War .pack',
          'Creates .pack files with proper prefixing (!!!!!!!!!!_{LANG}_)',
          FluentIcons.box_24_regular,
          theme,
        ),
        const SizedBox(height: 8),
        _buildFormatOption(
          ExportFormat.csv,
          'CSV',
          'Export as CSV files for external review',
          FluentIcons.document_table_24_regular,
          theme,
        ),
        const SizedBox(height: 8),
        _buildFormatOption(
          ExportFormat.excel,
          'Excel',
          'Export as Excel files for external review',
          FluentIcons.document_table_24_regular,
          theme,
        ),
        const SizedBox(height: 8),
        _buildFormatOption(
          ExportFormat.tmx,
          'TMX',
          'Translation Memory eXchange format',
          FluentIcons.document_data_24_regular,
          theme,
        ),
      ],
    );
  }

  Widget _buildFormatOption(
    ExportFormat format,
    String title,
    String description,
    IconData icon,
    ThemeData theme,
  ) {
    final isSelected = selectedFormat == format;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onFormatChanged(format),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withValues(alpha: 0.3),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  FluentIcons.checkmark_circle_24_filled,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
