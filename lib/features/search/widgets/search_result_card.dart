import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../services/search/models/search_result.dart';
import 'fluent_buttons.dart';

/// Individual search result card with highlighting
///
/// Displays a single search result with:
/// - Result number and navigation button
/// - Key (monospace)
/// - Source and target text with highlighting
/// - Metadata (project, status, file)
class SearchResultCard extends StatelessWidget {
  final SearchResult result;
  final int index;
  final int total;
  final VoidCallback? onNavigate;

  const SearchResultCard({
    super.key,
    required this.result,
    required this.index,
    required this.total,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onNavigate,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(
              color: Theme.of(context).dividerColor,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Result number and Go To button
              Row(
                children: [
                  Text(
                    'Result $index of $total',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  FluentOutlinedButton(
                    icon: FluentIcons.arrow_right_24_regular,
                    label: 'Go to',
                    onPressed: onNavigate ?? () {},
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Key (monospace)
              if (result.key != null) ...[
                Text(
                  'Key: ${result.key}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Source text with highlighting
              if (result.sourceText != null) ...[
                const Text(
                  'Source:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                _buildHighlightedText(
                  context,
                  result.sourceText!,
                  result.matchedField == 'source_text'
                      ? result.highlightedText
                      : null,
                ),
                const SizedBox(height: 8),
              ],

              // Target text with highlighting
              if (result.translatedText != null) ...[
                const Text(
                  'Target:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                _buildHighlightedText(
                  context,
                  result.translatedText!,
                  result.matchedField == 'translated_text'
                      ? result.highlightedText
                      : null,
                ),
                const SizedBox(height: 8),
              ],

              // Metadata
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  if (result.projectName != null)
                    _buildMetadataChip(
                      context,
                      FluentIcons.folder_24_regular,
                      result.projectName!,
                    ),
                  if (result.status != null)
                    _buildStatusBadge(context, result.status!),
                  if (result.fileName != null)
                    _buildMetadataChip(
                      context,
                      FluentIcons.document_24_regular,
                      result.fileName!,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedText(
    BuildContext context,
    String text,
    String? highlightedHtml,
  ) {
    // If we have highlighted HTML, parse and display it
    if (highlightedHtml != null && highlightedHtml.contains('<mark>')) {
      return _buildHighlightedFromHtml(context, highlightedHtml);
    }

    // Otherwise, just show plain text
    return Text(
      text,
      style: const TextStyle(fontSize: 13),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildHighlightedFromHtml(BuildContext context, String html) {
    // Parse HTML with <mark> tags and create TextSpan
    final spans = <TextSpan>[];
    final parts = html.split(RegExp(r'</?mark>'));

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty) continue;

      // Odd indices are inside <mark> tags (highlighted)
      final isHighlighted = i % 2 == 1;

      spans.add(
        TextSpan(
          text: part,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
            color: isHighlighted
                ? Theme.of(context).colorScheme.primary
                : null,
            backgroundColor: isHighlighted
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                : null,
          ),
        ),
      );
    }

    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: spans,
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildMetadataChip(BuildContext context, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).textTheme.bodySmall?.color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(BuildContext context, String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'pending':
        color = Colors.orange;
        break;
      case 'translated':
        color = Colors.blue;
        break;
      case 'validated':
        color = Colors.green;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
