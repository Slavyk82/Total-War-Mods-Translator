import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/i_translation_orchestrator.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart' hide FluentIconButton;

/// Full-screen translation progress display
///
/// Replaces the editor screen during mass translation to provide
/// an immersive, focused experience for monitoring translation progress.
///
/// Features:
/// - Async batch preparation with loading indicator
/// - Real-time progress updates with stats
/// - LLM exchange logs
/// - Pause/Resume/Stop/Cancel controls
/// - Automatic return to editor on completion
///
/// Uses Fluent Design patterns throughout
class TranslationProgressScreen extends StatefulWidget {
  const TranslationProgressScreen({
    super.key,
    this.batchId,
    this.translationContext,
    required this.orchestrator,
    required this.onComplete,
    this.preparationCallback,
  });

  /// Optional: existing batch ID if already created
  final String? batchId;
  
  /// Optional: translation context if already built
  final TranslationContext? translationContext;
  
  final ITranslationOrchestrator orchestrator;
  final VoidCallback onComplete;
  
  /// Optional: callback to prepare batch and context if not provided
  final Future<({String batchId, TranslationContext context})?> Function()? preparationCallback;

  @override
  State<TranslationProgressScreen> createState() => _TranslationProgressScreenState();
}

class _TranslationProgressScreenState extends State<TranslationProgressScreen> {
  TranslationProgress? _currentProgress;
  bool _isPaused = false;
  bool _isCancelling = false;
  bool _isStopping = false;
  String? _errorMessage;
  final DateTime _startTime = DateTime.now();
  bool _showLlmLogs = true; // Show logs by default
  Stream<Result<TranslationProgress, TranslationOrchestrationException>>? _progressStream;
  
  bool _isPreparingBatch = false;
  String? _preparedBatchId;
  TranslationContext? _preparedContext;
  bool _hasAutoClosed = false; // Guard against multiple auto-close triggers

  @override
  void initState() {
    super.initState();
    _initializeTranslation();
  }
  
  Future<void> _initializeTranslation() async {
    // If batch and context are provided, start immediately
    if (widget.batchId != null && widget.translationContext != null) {
      _startTranslation(widget.batchId!, widget.translationContext!);
      return;
    }
    
    // Otherwise, prepare batch first
    if (widget.preparationCallback != null) {
      setState(() {
        _isPreparingBatch = true;
      });
      
      try {
        final result = await widget.preparationCallback!();
        if (result != null && mounted) {
          _preparedBatchId = result.batchId;
          _preparedContext = result.context;
          setState(() {
            _isPreparingBatch = false;
          });
          _startTranslation(result.batchId, result.context);
        } else if (mounted) {
          setState(() {
            _isPreparingBatch = false;
            _errorMessage = 'Failed to prepare translation batch';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isPreparingBatch = false;
            _errorMessage = 'Preparation error: $e';
          });
        }
      }
    }
  }
  
  void _startTranslation(String batchId, TranslationContext context) {
    _progressStream = widget.orchestrator.translateBatch(
      batchId: batchId,
      context: context,
    );
    if (mounted) {
      setState(() {});
    }
  }
  
  String get _effectiveBatchId => _preparedBatchId ?? widget.batchId ?? '';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (!didPop) {
          // Prevent accidental dismissal - require explicit cancel
          await _showCancelConfirmation();
        }
      },
      child: FluentScaffold(
        header: FluentHeader(
          title: 'Translation in Progress',
          leading: null, // No back button during translation
          actions: [
            _buildHeaderButton(
              label: _isPaused ? 'Resume' : 'Pause',
              icon: _isPaused
                  ? FluentIcons.play_24_regular
                  : FluentIcons.pause_24_regular,
              onPressed: (_isCancelling || _isStopping) ? null : _handlePauseResume,
            ),
            _buildHeaderButton(
              label: 'Stop',
              icon: FluentIcons.stop_24_regular,
              onPressed: (_isCancelling || _isStopping) ? null : _handleStop,
              isDestructive: true,
            ),
            _buildHeaderButton(
              label: 'Cancel',
              icon: FluentIcons.dismiss_24_regular,
              onPressed: (_isCancelling || _isStopping) ? null : _showCancelConfirmation,
              isDestructive: true,
            ),
          ],
        ),
        body: _isPreparingBatch
            ? _buildPreparationView()
            : StreamBuilder<Result<TranslationProgress, TranslationOrchestrationException>>(
                stream: _progressStream,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    final result = snapshot.data!;
                    result.when(
                      ok: (progress) {
                        print('[DEBUG] StreamBuilder received progress: ${progress.processedUnits}/${progress.totalUnits} units, ${progress.llmLogs.length} logs');
                        _currentProgress = progress;
                        _isPaused = progress.status == TranslationProgressStatus.paused;

                        // Auto-close on completion (with guard against multiple triggers)
                        if (!_hasAutoClosed &&
                            (progress.status == TranslationProgressStatus.completed ||
                            progress.status == TranslationProgressStatus.failed ||
                            progress.status == TranslationProgressStatus.cancelled)) {
                          _hasAutoClosed = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              widget.onComplete();
                              if (Navigator.canPop(context)) {
                                Navigator.of(context).pop();
                              }
                            }
                          });
                        }
                      },
                      err: (error) {
                        _errorMessage = error.toString();
                      },
                    );
                  }

                  return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 32),
                      _buildProgressSection(),
                      const SizedBox(height: 24),
                      _buildStatsSection(),
                      const SizedBox(height: 24),
                      _buildPhaseSection(),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 24),
                        _buildErrorSection(),
                      ],
                      const SizedBox(height: 24),
                      _buildLlmLogsSection(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
  
  Widget _buildPreparationView() {
    final theme = Theme.of(context);
    
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: FluentProgressRing(
                strokeWidth: 6,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Preparing Translation',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Creating batch and gathering context...',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      FluentIcons.error_circle_24_regular,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FluentButton(
                onPressed: () {
                  if (!_hasAutoClosed && Navigator.canPop(context)) {
                    _hasAutoClosed = true;
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('Close'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool isDestructive = false,
  }) {
    return FluentIconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      tooltip: label,
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    
    return Row(
      children: [
        Icon(
          FluentIcons.translate_24_regular,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mass Translation',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Batch ID: ${_effectiveBatchId.substring(0, 8)}...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progress',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${(percentage * 100).toStringAsFixed(1)}%',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FluentProgressBar(
            value: percentage,
            height: 12,
            color: _isPaused
                ? Colors.orange.shade700
                : theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 12),
          Text(
            '${progress?.processedUnits ?? 0} / ${progress?.totalUnits ?? 0} units',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    final progress = _currentProgress;
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: FluentIcons.checkmark_circle_24_regular,
            label: 'Success',
            value: progress?.successfulUnits.toString() ?? '0',
            color: Colors.green.shade700,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            icon: FluentIcons.dismiss_circle_24_regular,
            label: 'Failed',
            value: progress?.failedUnits.toString() ?? '0',
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            icon: FluentIcons.fast_forward_24_regular,
            label: 'Skipped',
            value: progress?.skippedUnits.toString() ?? '0',
            color: Colors.blue.shade700,
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
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseSection() {
    final progress = _currentProgress;
    final phase = progress?.currentPhase;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (_isPaused)
            Icon(
              FluentIcons.pause_circle_24_regular,
              size: 32,
              color: Colors.orange.shade700,
            )
          else
            SizedBox(
              width: 32,
              height: 32,
              child: FluentProgressRing(
                strokeWidth: 3,
                color: theme.colorScheme.primary,
              ),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Phase',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isPaused ? 'Paused' : _getPhaseDisplayName(phase),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                if (progress?.estimatedSecondsRemaining != null)
                  Text(
                    _getEstimatedTimeDisplay(progress!.estimatedSecondsRemaining!),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  )
                else
                  Text(
                    _getElapsedTimeDisplay(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: errorColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: errorColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            size: 32,
            color: errorColor,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Error',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: errorColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: errorColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLlmLogsSection() {
    final logs = _currentProgress?.llmLogs ?? [];
    final lastLogs = logs.length > 10 ? logs.sublist(logs.length - 10) : logs;
    final theme = Theme.of(context);

    // Debug: Print logs count
    print('[DEBUG] _buildLlmLogsSection: ${logs.length} logs');
    if (logs.isNotEmpty) {
      print('[DEBUG] Last log: ${logs.last.compactDisplay}');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _showLlmLogs = !_showLlmLogs;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _showLlmLogs
                        ? FluentIcons.chevron_down_24_regular
                        : FluentIcons.chevron_right_24_regular,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'LLM Exchange Logs (${logs.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    FluentIcons.info_24_regular,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_showLlmLogs) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
              ),
            ),
            constraints: const BoxConstraints(maxHeight: 400),
            child: SingleChildScrollView(
              child: lastLogs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'No LLM exchanges yet. Logs will appear as translation progresses.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final log in lastLogs)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  log.success
                                      ? FluentIcons.checkmark_circle_24_regular
                                      : FluentIcons.error_circle_24_regular,
                                  size: 16,
                                  color: log.success
                                      ? Colors.green.shade700
                                      : theme.colorScheme.error,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    log.compactDisplay,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontFamily: 'Consolas',
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ],
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
        batchId: _effectiveBatchId,
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
        batchId: _effectiveBatchId,
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

  Future<void> _handleStop() async {
    if (!mounted || _hasAutoClosed) return;

    setState(() {
      _isStopping = true;
    });

    final result = await widget.orchestrator.stopTranslation(
      batchId: _effectiveBatchId,
    );

    result.when(
      ok: (_) {
        if (_hasAutoClosed) return;
        _hasAutoClosed = true;
        
        // Call onComplete first
        widget.onComplete();
        
        // Delay navigation to avoid black screen
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted && Navigator.canPop(context)) {
              Navigator.of(context).pop();
            }
          });
        }
      },
      err: (error) {
        if (mounted) {
          setState(() {
            _isStopping = false;
            _errorMessage = 'Failed to stop: ${error.message}';
          });
        }
      },
    );
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

    if (shouldCancel == true && mounted && !_hasAutoClosed) {
      setState(() {
        _isCancelling = true;
      });

      final result = await widget.orchestrator.cancelTranslation(
        batchId: _effectiveBatchId,
      );

      result.when(
        ok: (_) {
          if (_hasAutoClosed) return;
          _hasAutoClosed = true;
          
          // Call onComplete first
          widget.onComplete();
          
          // Delay navigation to avoid black screen
          if (mounted) {
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted && Navigator.canPop(context)) {
                Navigator.of(context).pop();
              }
            });
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

