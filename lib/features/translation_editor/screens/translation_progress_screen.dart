import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/i_translation_orchestrator.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart' hide FluentIconButton;
import 'progress/progress_widgets.dart';
import 'progress/progress_phase_widgets.dart';

/// Full-screen translation progress display
///
/// Replaces the editor screen during mass translation to provide
/// an immersive, focused experience for monitoring translation progress.
class TranslationProgressScreen extends StatefulWidget {
  const TranslationProgressScreen({
    super.key,
    this.batchId,
    this.translationContext,
    required this.orchestrator,
    required this.onComplete,
    this.preparationCallback,
  });

  final String? batchId;
  final TranslationContext? translationContext;
  final ITranslationOrchestrator orchestrator;
  final VoidCallback onComplete;
  final Future<({String batchId, TranslationContext context})?> Function()?
      preparationCallback;

  @override
  State<TranslationProgressScreen> createState() =>
      _TranslationProgressScreenState();
}

class _TranslationProgressScreenState extends State<TranslationProgressScreen> {
  TranslationProgress? _currentProgress;
  bool _isPaused = false;
  bool _isCancelling = false;
  bool _isStopping = false;
  String? _errorMessage;
  final DateTime _startTime = DateTime.now();
  Stream<Result<TranslationProgress, TranslationOrchestrationException>>?
      _progressStream;

  bool _isPreparingBatch = false;
  String? _preparedBatchId;
  bool _hasAutoClosed = false;

  String get _effectiveBatchId => _preparedBatchId ?? widget.batchId ?? '';

  @override
  void initState() {
    super.initState();
    _initializeTranslation();
  }

  Future<void> _initializeTranslation() async {
    if (widget.batchId != null && widget.translationContext != null) {
      _startTranslation(widget.batchId!, widget.translationContext!);
      return;
    }

    if (widget.preparationCallback != null) {
      setState(() => _isPreparingBatch = true);

      try {
        final result = await widget.preparationCallback!();
        if (result != null && mounted) {
          _preparedBatchId = result.batchId;
          setState(() => _isPreparingBatch = false);
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
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (!didPop) await _showCancelConfirmation();
      },
      child: FluentScaffold(
        header: _buildHeader(),
        body: _isPreparingBatch
            ? buildPreparationView(
                context,
                errorMessage: _errorMessage,
                onClose: _handleClose,
              )
            : _buildProgressBody(),
      ),
    );
  }

  FluentHeader _buildHeader() {
    return FluentHeader(
      title: 'Translation in Progress',
      leading: null,
      actions: [
        FluentIconButton(
          icon: Icon(_isPaused
              ? FluentIcons.play_24_regular
              : FluentIcons.pause_24_regular),
          onPressed:
              (_isCancelling || _isStopping) ? null : _handlePauseResume,
          tooltip: _isPaused ? 'Resume' : 'Pause',
        ),
        FluentIconButton(
          icon: const Icon(FluentIcons.stop_24_regular),
          onPressed: (_isCancelling || _isStopping) ? null : _handleStop,
          tooltip: 'Stop',
        ),
        FluentIconButton(
          icon: const Icon(FluentIcons.dismiss_24_regular),
          onPressed:
              (_isCancelling || _isStopping) ? null : _showCancelConfirmation,
          tooltip: 'Cancel',
        ),
      ],
    );
  }

  Widget _buildProgressBody() {
    return StreamBuilder<
        Result<TranslationProgress, TranslationOrchestrationException>>(
      stream: _progressStream,
      builder: (context, snapshot) {
        _handleStreamData(snapshot);

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildProgressHeader(context, batchId: _effectiveBatchId),
                  const SizedBox(height: 32),
                  buildProgressSection(
                    context,
                    progress: _currentProgress,
                    isPaused: _isPaused,
                  ),
                  const SizedBox(height: 24),
                  buildStatsSection(context, progress: _currentProgress),
                  const SizedBox(height: 24),
                  buildPhaseSection(
                    context,
                    progress: _currentProgress,
                    isPaused: _isPaused,
                    elapsedTimeDisplay: getElapsedTimeDisplay(_startTime),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 24),
                    buildErrorSection(context, errorMessage: _errorMessage!),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleStreamData(
    AsyncSnapshot<
            Result<TranslationProgress, TranslationOrchestrationException>>
        snapshot,
  ) {
    if (!snapshot.hasData) return;

    snapshot.data!.when(
      ok: (progress) {
        _currentProgress = progress;
        _isPaused = progress.status == TranslationProgressStatus.paused;

        if (!_hasAutoClosed && _isTerminalStatus(progress.status)) {
          _hasAutoClosed = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.onComplete();
              if (Navigator.canPop(context)) Navigator.of(context).pop();
            }
          });
        }
      },
      err: (error) => _errorMessage = error.toString(),
    );
  }

  bool _isTerminalStatus(TranslationProgressStatus status) {
    return status == TranslationProgressStatus.completed ||
        status == TranslationProgressStatus.failed ||
        status == TranslationProgressStatus.cancelled;
  }

  void _handleClose() {
    if (!_hasAutoClosed && Navigator.canPop(context)) {
      _hasAutoClosed = true;
      Navigator.of(context).pop();
    }
  }

  Future<void> _handlePauseResume() async {
    if (_isPaused) {
      final result = await widget.orchestrator.resumeTranslation(
        batchId: _effectiveBatchId,
      );
      result.when(
        ok: (_) {
          if (mounted) setState(() => _isPaused = false);
        },
        err: (error) {
          if (mounted) {
            setState(() => _errorMessage = 'Failed to resume: ${error.message}');
          }
        },
      );
    } else {
      final result = await widget.orchestrator.pauseTranslation(
        batchId: _effectiveBatchId,
      );
      result.when(
        ok: (_) {
          if (mounted) setState(() => _isPaused = true);
        },
        err: (error) {
          if (mounted) {
            setState(() => _errorMessage = 'Failed to pause: ${error.message}');
          }
        },
      );
    }
  }

  Future<void> _handleStop() async {
    if (!mounted || _hasAutoClosed) return;

    setState(() => _isStopping = true);

    final result = await widget.orchestrator.stopTranslation(
      batchId: _effectiveBatchId,
    );

    result.when(
      ok: (_) => _completeAndClose(),
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
            child: const Text('Cancel Batch', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldCancel == true && mounted && !_hasAutoClosed) {
      setState(() => _isCancelling = true);

      final result = await widget.orchestrator.cancelTranslation(
        batchId: _effectiveBatchId,
      );

      result.when(
        ok: (_) => _completeAndClose(),
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

  void _completeAndClose() {
    if (_hasAutoClosed) return;
    _hasAutoClosed = true;

    widget.onComplete();

    if (mounted) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
      });
    }
  }
}
