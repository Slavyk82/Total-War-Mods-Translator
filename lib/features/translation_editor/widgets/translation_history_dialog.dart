import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:intl/intl.dart';
import '../../../models/domain/translation_version.dart';
import '../../../models/domain/translation_version_history.dart';
import '../../../repositories/translation_version_history_repository.dart';
import '../../../services/service_locator.dart';

/// Dialog for viewing translation version history
///
/// Displays all historical changes to a translation version in reverse
/// chronological order with timestamps, changed text, and who made the change.
class TranslationHistoryDialog extends ConsumerStatefulWidget {
  final String versionId;
  final String unitKey;

  const TranslationHistoryDialog({
    super.key,
    required this.versionId,
    required this.unitKey,
  });

  @override
  ConsumerState<TranslationHistoryDialog> createState() =>
      _TranslationHistoryDialogState();
}

class _TranslationHistoryDialogState
    extends ConsumerState<TranslationHistoryDialog> {
  List<TranslationVersionHistory>? _history;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repository = ServiceLocator.get<TranslationVersionHistoryRepository>();
      final result = await repository.getByVersion(widget.versionId);

      result.when(
        ok: (history) {
          if (mounted) {
            setState(() {
              _history = history;
              _isLoading = false;
            });
          }
        },
        err: (error) {
          if (mounted) {
            setState(() {
              _error = error.toString();
              _isLoading = false;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 700,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Expanded(
              child: _buildContent(),
            ),
            const SizedBox(height: 16),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(
          FluentIcons.history_24_regular,
          size: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Translation History',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Key: ${widget.unitKey}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            ],
          ),
        ),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(8),
              child: const Icon(
                FluentIcons.dismiss_24_regular,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              FluentIcons.error_circle_24_regular,
              size: 48,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading history',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_history == null || _history!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              FluentIcons.history_24_regular,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              'No history available',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'This translation has no recorded history yet.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _history!.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = _history![index];
        return _buildHistoryEntry(entry);
      },
    );
  }

  Widget _buildHistoryEntry(TranslationVersionHistory entry) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final dateStr = dateFormat.format(entry.createdAtAsDateTime);

    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getStatusIcon(entry.status),
                  size: 16,
                  color: _getStatusColor(entry.status),
                ),
                const SizedBox(width: 8),
                Text(
                  entry.statusDisplay,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 16),
                const Icon(
                  FluentIcons.person_24_regular,
                  size: 14,
                  color: Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  entry.changedByDisplay,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const Spacer(),
                const Icon(
                  FluentIcons.clock_24_regular,
                  size: 14,
                  color: Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Colors.grey.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Text(
                entry.translatedText,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (entry.hasChangeReason) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    FluentIcons.info_24_regular,
                    size: 14,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Reason: ${entry.changeReason}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon(TranslationVersionStatus status) {
    switch (status) {
      case TranslationVersionStatus.pending:
        return FluentIcons.circle_24_regular;
      case TranslationVersionStatus.translated:
        return FluentIcons.checkmark_circle_24_regular;
      case TranslationVersionStatus.needsReview:
        return FluentIcons.warning_24_regular;
    }
  }

  Color _getStatusColor(TranslationVersionStatus status) {
    switch (status) {
      case TranslationVersionStatus.pending:
        return Colors.grey;
      case TranslationVersionStatus.translated:
        return Colors.green;
      case TranslationVersionStatus.needsReview:
        return Colors.orange;
    }
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Close',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
