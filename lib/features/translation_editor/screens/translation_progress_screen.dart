import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/i_translation_orchestrator.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart' hide FluentIconButton;
import '../providers/editor_providers.dart';
import 'progress/progress_widgets.dart';
import 'progress/progress_phase_widgets.dart';

/// Full-screen translation progress display
///
/// Replaces the editor screen during mass translation to provide
/// an immersive, focused experience for monitoring translation progress.
class TranslationProgressScreen extends ConsumerStatefulWidget {
  const TranslationProgressScreen({
    super.key,
    this.batchId,
    this.translationContext,
    required this.orchestrator,
    required this.onComplete,
    this.preparationCallback,
    this.projectName,
  });

  final String? batchId;
  final TranslationContext? translationContext;
  final ITranslationOrchestrator orchestrator;
  final VoidCallback onComplete;
  final Future<({String batchId, TranslationContext context})?> Function()?
      preparationCallback;
  final String? projectName;

  @override
  ConsumerState<TranslationProgressScreen> createState() =>
      _TranslationProgressScreenState();
}

class _TranslationProgressScreenState extends ConsumerState<TranslationProgressScreen> {
  TranslationProgress? _currentProgress;
  bool _isPaused = false;
  bool _isStopping = false;
  String? _errorMessage;
  final DateTime _startTime = DateTime.now();
  Stream<Result<TranslationProgress, TranslationOrchestrationException>>?
      _progressStream;

  bool _isPreparingBatch = false;
  String? _preparedBatchId;
  bool _hasAutoClosed = false;

  /// Whether the user can close this screen.
  /// Only true after clicking Stop or when translation completes/fails.
  bool _canClose = false;

  /// Captured notifier reference for safe disposal
  TranslationInProgress? _translationNotifier;

  /// Timer for updating elapsed time display every second
  Timer? _elapsedTimer;

  String get _effectiveBatchId => _preparedBatchId ?? widget.batchId ?? '';

  @override
  void initState() {
    super.initState();
    // Mark translation as in progress to block navigation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _translationNotifier = ref.read(translationInProgressProvider.notifier);
      _translationNotifier?.setInProgress(true);
    });
    _initializeTranslation();

    // Start timer to update elapsed time every second
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();

    // Defer provider modification to avoid "modifying during finalize" error
    // Use captured notifier reference (safe to use after unmount)
    final notifier = _translationNotifier;
    if (notifier != null) {
      Future.microtask(() { try { notifier.setInProgress(false); } catch (_) {} });
    }
    super.dispose();
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
      canPop: _canClose,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        // Show feedback when user tries to leave during active translation
        if (!didPop && !_canClose && mounted) {
          FluentToast.warning(
            context,
            'Translation in progress. Click "Stop" to exit safely.',
          );
        }
      },
      child: FluentScaffold(
        header: _buildHeader(),
        body: _isPreparingBatch
            ? buildPreparationView(
                context,
                errorMessage: _errorMessage,
                onClose: _canClose ? _handleClose : null,
              )
            : _buildProgressBody(),
      ),
    );
  }

  FluentHeader _buildHeader() {
    return FluentHeader(
      title: 'Translation in Progress',
      leading: null,
      actions: const [],
    );
  }

  Widget _buildProgressBody() {
    return StreamBuilder<
        Result<TranslationProgress, TranslationOrchestrationException>>(
      stream: _progressStream,
      builder: (context, snapshot) {
        _handleStreamData(snapshot);

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left side: Progress cards
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      buildProgressHeader(context, batchId: _effectiveBatchId),
                      const SizedBox(height: 24),
                      buildProgressSection(
                        context,
                        progress: _currentProgress,
                        isPaused: _isPaused,
                        onStop: _handleStop,
                        isStopping: _isStopping,
                        projectName: widget.projectName,
                      ),
                      const SizedBox(height: 20),
                      buildStatsSection(context, progress: _currentProgress),
                      const SizedBox(height: 20),
                      buildPhaseSection(
                        context,
                        progress: _currentProgress,
                        isPaused: _isPaused,
                        elapsedTimeDisplay: getElapsedTimeDisplay(_startTime),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 20),
                        buildErrorSection(context, errorMessage: _errorMessage!),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Right side: Log terminal (full height)
              const Expanded(
                flex: 2,
                child: LogTerminal(expand: true),
              ),
            ],
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

        // Allow closing when translation reaches terminal status
        if (_isTerminalStatus(progress.status)) {
          _canClose = true;
          // Release navigation lock - schedule after build to avoid provider modification during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _translationNotifier?.setInProgress(false);
          });
          if (!_hasAutoClosed) {
            _hasAutoClosed = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                widget.onComplete();
                if (Navigator.canPop(context)) Navigator.of(context).pop();
              }
            });
          }
        }
      },
      err: (error) {
        _errorMessage = error.toString();
        // Allow closing on error - schedule after build to avoid provider modification during build
        _canClose = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _translationNotifier?.setInProgress(false);
        });
      },
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

  void _completeAndClose() {
    if (_hasAutoClosed) return;
    _hasAutoClosed = true;
    _canClose = true;

    // Release navigation lock immediately using captured notifier
    _translationNotifier?.setInProgress(false);

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

