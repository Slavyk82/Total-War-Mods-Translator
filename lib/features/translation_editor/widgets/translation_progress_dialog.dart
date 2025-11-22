import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/i_translation_orchestrator.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Modal progress dialog for batch translation
///
/// Displays real-time progress updates during translation:
/// - Progress bar
/// - Current phase
/// - Completed/failed counts
/// - Estimated time remaining
/// - Pause/Resume/Cancel controls
///
/// Uses Fluent Design patterns (no Material ripple effects)
class TranslationProgressDialog extends StatefulWidget {
  const TranslationProgressDialog({
    super.key,
    required this.batchId,
    required this.progressStream,
    required this.orchestrator,
    required this.onComplete,
  });

  final String batchId;
  final Stream<Result<TranslationProgress, TranslationOrchestrationException>> progressStream;
  final ITranslationOrchestrator orchestrator;
  final VoidCallback onComplete;

  @override
  State<TranslationProgressDialog> createState() => _TranslationProgressDialogState();
}

class _TranslationProgressDialogState extends State<TranslationProgressDialog> {
  TranslationProgress? _currentProgress;
  bool _isPaused = false;
  bool _isCancelling = false;
  String? _errorMessage;
  final DateTime _startTime = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (!didPop) {
          // Prevent accidental dismissal
          await _showCancelConfirmation();
        }
      },
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          child: StreamBuilder<Result<TranslationProgress, TranslationOrchestrationException>>(
            stream: widget.progressStream,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final result = snapshot.data!;
                result.when(
                  ok: (progress) {
                    _currentProgress = progress;
                    _isPaused = progress.status == TranslationProgressStatus.paused;

                    // Auto-close on completion
                    if (progress.status == TranslationProgressStatus.completed ||
                        progress.status == TranslationProgressStatus.failed ||
                        progress.status == TranslationProgressStatus.cancelled) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          widget.onComplete();
                          Navigator.of(context).pop();
                        }
                      });
                    }
                  },
                  err: (error) {
                    _errorMessage = error.toString();
                  },
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildProgressSection(),
                  const SizedBox(height: 16),
                  _buildStatsSection(),
                  const SizedBox(height: 16),
                  _buildPhaseSection(),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    _buildErrorSection(),
                  ],
                  const SizedBox(height: 24),
                  _buildActions(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(
          FluentIcons.translate_24_regular,
          size: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Translating',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Batch ID: ${widget.batchId.substring(0, 8)}...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressSection() {
    final progress = _currentProgress;
    final percentage = progress?.progressPercentage ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progress',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${(percentage * 100).toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage,
            minHeight: 8,
            backgroundColor: Colors.grey.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(
              _isPaused
                ? Colors.orange
                : Theme.of(context).primaryColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${progress?.processedUnits ?? 0} / ${progress?.totalUnits ?? 0} units',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsSection() {
    final progress = _currentProgress;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: FluentIcons.checkmark_circle_24_regular,
            label: 'Success',
            value: progress?.successfulUnits.toString() ?? '0',
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: FluentIcons.dismiss_circle_24_regular,
            label: 'Failed',
            value: progress?.failedUnits.toString() ?? '0',
            color: Colors.red,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: FluentIcons.fast_forward_24_regular,
            label: 'Skipped',
            value: progress?.skippedUnits.toString() ?? '0',
            color: Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseSection() {
    final progress = _currentProgress;
    final phase = progress?.currentPhase;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (_isPaused)
            const Icon(
              FluentIcons.pause_circle_24_regular,
              size: 20,
              color: Colors.orange,
            )
          else
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).primaryColor,
                ),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isPaused ? 'Paused' : _getPhaseDisplayName(phase),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (progress?.estimatedSecondsRemaining != null)
                  Text(
                    _getEstimatedTimeDisplay(progress!.estimatedSecondsRemaining!),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  )
                else
                  Text(
                    _getElapsedTimeDisplay(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            FluentIcons.error_circle_24_regular,
            size: 20,
            color: Colors.red,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.red.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildActionButton(
          label: _isPaused ? 'Resume' : 'Pause',
          icon: _isPaused
            ? FluentIcons.play_24_regular
            : FluentIcons.pause_24_regular,
          onPressed: _isCancelling ? null : _handlePauseResume,
        ),
        const SizedBox(width: 12),
        _buildActionButton(
          label: 'Cancel',
          icon: FluentIcons.dismiss_24_regular,
          onPressed: _isCancelling ? null : _showCancelConfirmation,
          isDestructive: true,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool isDestructive = false,
  }) {
    return MouseRegion(
      cursor: onPressed != null
        ? SystemMouseCursors.click
        : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: onPressed == null
              ? Colors.grey.withValues(alpha: 0.1)
              : (isDestructive
                ? Colors.red.withValues(alpha: 0.1)
                : Theme.of(context).primaryColor.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: onPressed == null
                  ? Colors.grey
                  : (isDestructive ? Colors.red : Theme.of(context).primaryColor),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: onPressed == null
                    ? Colors.grey
                    : (isDestructive ? Colors.red : Theme.of(context).primaryColor),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getPhaseDisplayName(TranslationPhase? phase) {
    if (phase == null) return 'Initializing...';

    switch (phase) {
      case TranslationPhase.initializing:
        return 'Initializing...';
      case TranslationPhase.tmExactLookup:
        return 'Checking Translation Memory (Exact)';
      case TranslationPhase.tmFuzzyLookup:
        return 'Checking Translation Memory (Fuzzy)';
      case TranslationPhase.buildingPrompt:
        return 'Building Translation Prompt';
      case TranslationPhase.llmTranslation:
        return 'Translating with LLM';
      case TranslationPhase.validating:
        return 'Validating Translations';
      case TranslationPhase.saving:
        return 'Saving Translations';
      case TranslationPhase.updatingTm:
        return 'Updating Translation Memory';
      case TranslationPhase.finalizing:
        return 'Finalizing Batch';
      case TranslationPhase.completed:
        return 'Completed';
    }
  }

  String _getEstimatedTimeDisplay(int seconds) {
    if (seconds < 60) {
      return 'About $seconds seconds remaining';
    } else {
      final minutes = (seconds / 60).ceil();
      return 'About $minutes minute${minutes > 1 ? 's' : ''} remaining';
    }
  }

  String _getElapsedTimeDisplay() {
    final elapsed = DateTime.now().difference(_startTime);
    final seconds = elapsed.inSeconds;

    if (seconds < 60) {
      return 'Elapsed: $seconds seconds';
    } else {
      final minutes = (seconds / 60).floor();
      final remainingSeconds = seconds % 60;
      return 'Elapsed: $minutes:${remainingSeconds.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _handlePauseResume() async {
    if (_isPaused) {
      final result = await widget.orchestrator.resumeTranslation(
        batchId: widget.batchId,
      );
      result.when(
        ok: (_) {
          if (mounted) {
            setState(() {
              _isPaused = false;
            });
          }
        },
        err: (error) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Failed to resume: ${error.message}';
            });
          }
        },
      );
    } else {
      final result = await widget.orchestrator.pauseTranslation(
        batchId: widget.batchId,
      );
      result.when(
        ok: (_) {
          if (mounted) {
            setState(() {
              _isPaused = true;
            });
          }
        },
        err: (error) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Failed to pause: ${error.message}';
            });
          }
        },
      );
    }
  }

  Future<void> _showCancelConfirmation() async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(FluentIcons.warning_24_regular, color: Colors.orange),
            SizedBox(width: 8),
            Text('Cancel Translation?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to cancel this translation batch? '
          'Progress will be saved, but remaining units will not be translated.',
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continue'),
          ),
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Cancel Batch',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (shouldCancel == true && mounted) {
      setState(() {
        _isCancelling = true;
      });

      final result = await widget.orchestrator.cancelTranslation(
        batchId: widget.batchId,
      );

      result.when(
        ok: (_) {
          if (mounted) {
            widget.onComplete();
            Navigator.of(context).pop();
          }
        },
        err: (error) {
          if (mounted) {
            setState(() {
              _isCancelling = false;
              _errorMessage = 'Failed to cancel: ${error.message}';
            });
          }
        },
      );
    }
  }
}
