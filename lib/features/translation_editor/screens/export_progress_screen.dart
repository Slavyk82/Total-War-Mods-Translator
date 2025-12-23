import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/services/file/export_orchestrator_service.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart' hide FluentIconButton;
import 'progress/progress_widgets.dart';

/// Step labels for progress display
const _exportStepLabels = <String, String>{
  'preparingData': 'Preparing data...',
  'generatingLocFiles': 'Generating .loc files...',
  'creatingPack': 'Creating .pack file...',
  'generatingImage': 'Generating pack image...',
  'finalizing': 'Finalizing...',
  'completed': 'Pack generated!',
  'collectingData': 'Collecting translation data...',
  'writingFile': 'Writing output file...',
};

/// Full-screen export progress display
///
/// Shows real-time progress during export operations with
/// a terminal view for detailed logs.
class ExportProgressScreen extends ConsumerStatefulWidget {
  const ExportProgressScreen({
    super.key,
    required this.exportService,
    required this.projectId,
    required this.languageCodes,
    required this.onComplete,
    this.generatePackImage = true,
  });

  final ExportOrchestratorService exportService;
  final String projectId;
  final List<String> languageCodes;
  final void Function(ExportResult? result) onComplete;
  final bool generatePackImage;

  @override
  ConsumerState<ExportProgressScreen> createState() =>
      _ExportProgressScreenState();
}

class _ExportProgressScreenState extends ConsumerState<ExportProgressScreen> {
  String _currentStep = 'preparingData';
  double _progress = 0.0;
  String? _currentLanguage;
  int? _currentIndex;
  int? _total;
  String? _errorMessage;
  ExportResult? _result;
  bool _isComplete = false;
  final DateTime _startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _startExport();
  }

  Future<void> _startExport() async {
    try {
      final result = await widget.exportService.exportToPack(
        projectId: widget.projectId,
        languageCodes: widget.languageCodes,
        outputPath: 'exports',
        validatedOnly: false,
        generatePackImage: widget.generatePackImage,
        onProgress: _handleProgress,
      );

      if (!mounted) return;

      result.when(
        ok: (exportResult) {
          setState(() {
            _result = exportResult;
            _isComplete = true;
            _currentStep = 'completed';
            _progress = 1.0;
          });
        },
        err: (error) {
          setState(() {
            _errorMessage = error.message;
            _isComplete = true;
          });
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isComplete = true;
        });
      }
    }
  }

  void _handleProgress(
    String step,
    double progress, {
    String? currentLanguage,
    int? currentIndex,
    int? total,
  }) {
    if (!mounted) return;
    setState(() {
      _currentStep = step;
      _progress = progress;
      _currentLanguage = currentLanguage;
      _currentIndex = currentIndex;
      _total = total;
    });
  }

  void _handleClose() {
    widget.onComplete(_result);
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  String get _elapsedTime {
    final elapsed = DateTime.now().difference(_startTime);
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _isComplete,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop && !_isComplete && mounted) {
          FluentToast.warning(
            context,
            'Pack generation in progress. Wait for completion.',
          );
        }
      },
      child: FluentScaffold(
        header: _buildHeader(),
        body: _buildBody(),
      ),
    );
  }

  FluentHeader _buildHeader() {
    return FluentHeader(
      title: 'Generating Pack',
      leading: null,
      actions: const [],
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _buildProgressHeader(theme),
              const SizedBox(height: 32),

              // Progress section
              _buildProgressSection(theme),
              const SizedBox(height: 24),

              // Status info
              _buildStatusInfo(theme),
              const SizedBox(height: 24),

              // Control buttons
              if (_isComplete) _buildCloseButton(theme),
              const SizedBox(height: 24),

              // Terminal
              const LogTerminal(height: 200),

              // Error section
              if (_errorMessage != null) ...[
                const SizedBox(height: 24),
                buildErrorSection(context, errorMessage: _errorMessage!),
              ],

              // Success result
              if (_result != null && _errorMessage == null) ...[
                const SizedBox(height: 24),
                _buildSuccessSection(theme),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressHeader(ThemeData theme) {
    return Row(
      children: [
        Icon(
          FluentIcons.arrow_export_24_regular,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pack Generation',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Languages: ${widget.languageCodes.join(", ")}',
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

  Widget _buildProgressSection(ThemeData theme) {
    final stepLabel = _exportStepLabels[_currentStep] ?? _currentStep;

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
              Expanded(
                child: Text(
                  stepLabel,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${(_progress * 100).toStringAsFixed(1)}%',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _isComplete && _errorMessage != null
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FluentProgressBar(
            value: _progress,
            height: 12,
            color: _isComplete && _errorMessage != null
                ? theme.colorScheme.error
                : _isComplete
                    ? Colors.green.shade700
                    : theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
          ),
          if (_currentLanguage != null && _currentIndex != null && _total != null) ...[
            const SizedBox(height: 12),
            Text(
              'Processing: $_currentLanguage (${_currentIndex! + 1}/$_total)',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusInfo(ThemeData theme) {
    return Row(
      children: [
        _buildInfoCard(
          theme,
          icon: FluentIcons.timer_24_regular,
          label: 'Elapsed',
          value: _elapsedTime,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 16),
        _buildInfoCard(
          theme,
          icon: FluentIcons.status_24_regular,
          label: 'Status',
          value: _isComplete
              ? (_errorMessage != null ? 'Failed' : 'Completed')
              : 'In Progress',
          color: _isComplete
              ? (_errorMessage != null
                  ? theme.colorScheme.error
                  : Colors.green.shade700)
              : Colors.orange.shade700,
        ),
      ],
    );
  }

  Widget _buildInfoCard(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloseButton(ThemeData theme) {
    return Center(
      child: _ExportControlButton(
        icon: FluentIcons.checkmark_24_filled,
        label: 'Close',
        color: _errorMessage != null
            ? theme.colorScheme.error
            : Colors.green.shade700,
        onPressed: _handleClose,
      ),
    );
  }

  Widget _buildSuccessSection(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.checkmark_circle_24_regular,
                size: 32,
                color: Colors.green.shade700,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pack Generated',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_result!.entryCount} translations included',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  FluentIcons.folder_24_regular,
                  size: 20,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    _result!.outputPath,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'Consolas, monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Control button for export progress screen
class _ExportControlButton extends StatefulWidget {
  const _ExportControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  State<_ExportControlButton> createState() => _ExportControlButtonState();
}

class _ExportControlButtonState extends State<_ExportControlButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _isPressed
        ? widget.color.withValues(alpha: 0.9)
        : _isHovered
            ? widget.color.withValues(alpha: 0.85)
            : widget.color;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

