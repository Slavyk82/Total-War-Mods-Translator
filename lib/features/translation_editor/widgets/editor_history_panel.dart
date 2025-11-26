import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/domain/translation_version_history.dart';
import 'package:twmt/models/domain/translation_version.dart';
import '../../../services/toast_notification_service.dart';
import '../providers/editor_providers.dart';

/// History panel showing translation modification history
///
/// Displays who changed what and when, with ability to revert changes
class EditorHistoryPanel extends ConsumerStatefulWidget {
  final String? selectedVersionId;
  final Function(String translatedText, String reason)? onRevert;

  const EditorHistoryPanel({
    super.key,
    this.selectedVersionId,
    this.onRevert,
  });

  @override
  ConsumerState<EditorHistoryPanel> createState() =>
      _EditorHistoryPanelState();
}

class _EditorHistoryPanelState extends ConsumerState<EditorHistoryPanel> {
  String? _expandedEntryId;
  String? _hoveredEntryId;

  @override
  Widget build(BuildContext context) {
    if (widget.selectedVersionId == null) {
      return _buildEmptyState(
        icon: FluentIcons.history_24_regular,
        message: 'Select a translation unit to view edit history',
      );
    }

    // Watch history entries from provider
    final historyAsync = ref.watch(
      historyForVersionProvider(widget.selectedVersionId!),
    );

    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildEmptyState(
        icon: FluentIcons.error_circle_24_regular,
        message: 'Error loading edit history',
      ),
      data: (entries) => _buildHistoryList(entries),
    );
  }

  Widget _buildHistoryList(List<TranslationVersionHistory> entries) {
    if (entries.isEmpty) {
      return _buildEmptyState(
        icon: FluentIcons.history_24_regular,
        message: 'No edit history available for this translation',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16.0),
      itemCount: entries.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final previousEntry = index < entries.length - 1 ? entries[index + 1] : null;
        return _buildHistoryCard(entry, previousEntry);
      },
    );
  }

  Widget _buildHistoryCard(
    TranslationVersionHistory entry,
    TranslationVersionHistory? previousEntry,
  ) {
    final changeType = _getChangeType(entry, previousEntry);
    final color = _getChangeTypeColor(changeType);
    final isExpanded = _expandedEntryId == entry.id;
    final isHovered = _hoveredEntryId == entry.id;
    final hasChanges = previousEntry != null &&
        previousEntry.translatedText != entry.translatedText;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredEntryId = entry.id),
      onExit: (_) => setState(() => _hoveredEntryId = null),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isHovered
              ? color.withValues(alpha: 0.1)
              : color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isHovered
                ? color.withValues(alpha: 0.5)
                : color.withValues(alpha: 0.3),
            width: isHovered ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _expandedEntryId = isExpanded ? null : entry.id;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                  children: [
                    // Change type badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _getChangeTypeLabel(changeType),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Time and author
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getRelativeTime(entry),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                _getSourceIcon(entry),
                                size: 12,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                entry.changedByDisplay,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              if (entry.confidenceScore != null) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  FluentIcons.star_24_regular,
                                  size: 12,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${(entry.confidenceScore! * 100).round()}%',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Expand icon
                    Icon(
                      isExpanded
                          ? FluentIcons.chevron_up_24_regular
                          : FluentIcons.chevron_down_24_regular,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
            ),

            // Expanded content
            if (isExpanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Show change if applicable
                    if (hasChanges) ...[
                      _buildTextComparison(
                        'From',
                        previousEntry.translatedText,
                        Colors.red.withValues(alpha: 0.1),
                      ),
                      const SizedBox(height: 8),
                      _buildTextComparison(
                        'To',
                        entry.translatedText,
                        Colors.green.withValues(alpha: 0.1),
                      ),
                    ] else ...[
                      // Show current value
                      _buildTextDisplay(entry.translatedText),
                    ],

                    // Change reason if available
                    if (entry.changeReason != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              FluentIcons.info_24_regular,
                              size: 14,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                entry.changeReason ?? '',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Revert button (only for non-latest entries)
                    if (previousEntry != null) ...[
                      const SizedBox(height: 12),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => _handleRevert(entry),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  FluentIcons.arrow_undo_24_regular,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Revert to this version',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTextComparison(String label, String text, Color bgColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            text,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildTextDisplay(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  void _handleRevert(TranslationVersionHistory entry) {
    if (widget.onRevert != null) {
      final timestamp = _getRelativeTime(entry);
      widget.onRevert!(
        entry.translatedText,
        'Reverted to version from $timestamp',
      );

      ToastNotificationService.showSuccess(
        context,
        'Reverted to version from $timestamp',
      );
    }
  }

  Color _getChangeTypeColor(TranslationChangeType type) {
    switch (type) {
      case TranslationChangeType.created:
        return Colors.blue;
      case TranslationChangeType.modified:
        return Colors.orange;
      case TranslationChangeType.validated:
        return Colors.green;
      case TranslationChangeType.cleared:
        return Colors.red;
      case TranslationChangeType.reverted:
        return Colors.purple;
    }
  }

  String _getChangeTypeLabel(TranslationChangeType type) {
    switch (type) {
      case TranslationChangeType.created:
        return 'Created';
      case TranslationChangeType.modified:
        return 'Modified';
      case TranslationChangeType.validated:
        return 'Validated';
      case TranslationChangeType.cleared:
        return 'Cleared';
      case TranslationChangeType.reverted:
        return 'Reverted';
    }
  }

  IconData _getSourceIcon(TranslationVersionHistory entry) {
    if (entry.isUserChange) {
      return FluentIcons.person_24_regular;
    } else if (entry.isProviderChange) {
      return FluentIcons.brain_circuit_24_regular;
    } else {
      return FluentIcons.settings_24_regular;
    }
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 48,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  /// Helper: Get change type based on status and context
  TranslationChangeType _getChangeType(
    TranslationVersionHistory entry,
    TranslationVersionHistory? previous,
  ) {
    if (previous == null) return TranslationChangeType.created;

    // Validated when going from needsReview/pending to translated
    if (entry.status == TranslationVersionStatus.translated &&
        (previous.status == TranslationVersionStatus.needsReview ||
         previous.status == TranslationVersionStatus.pending)) {
      return TranslationChangeType.validated;
    }

    if (entry.translatedText.isEmpty && previous.translatedText.isNotEmpty) {
      return TranslationChangeType.cleared;
    }

    if (entry.changeReason?.contains('Revert') ?? false) {
      return TranslationChangeType.reverted;
    }

    return TranslationChangeType.modified;
  }

  /// Helper: Get relative time string
  String _getRelativeTime(TranslationVersionHistory entry) {
    final changedAt = entry.createdAtAsDateTime;
    final now = DateTime.now();
    final difference = now.difference(changedAt);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days ${days == 1 ? 'day' : 'days'} ago';
    } else {
      return changedAt.toString().split('.')[0];
    }
  }
}

/// Type of change made to a translation
enum TranslationChangeType {
  created,
  modified,
  validated,
  cleared,
  reverted,
}
