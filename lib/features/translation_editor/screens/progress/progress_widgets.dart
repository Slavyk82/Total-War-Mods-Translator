import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Builds the preparation view shown while batch is being prepared
Widget buildPreparationView(
  BuildContext context, {
  String? errorMessage,
  VoidCallback? onClose,
}) {
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
          if (errorMessage != null) ...[
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
                      errorMessage,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(height: 24),
              FluentButton(
                onPressed: onClose,
                child: const Text('Close'),
              ),
            ],
          ],
        ],
      ),
    ),
  );
}

/// Builds the header with batch ID and icon
Widget buildProgressHeader(
  BuildContext context, {
  required String batchId,
}) {
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
              'Batch ID: ${batchId.length > 8 ? '${batchId.substring(0, 8)}...' : batchId}',
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

/// Builds the main progress bar section
Widget buildProgressSection(
  BuildContext context, {
  required TranslationProgress? progress,
  required bool isPaused,
  VoidCallback? onStop,
  bool isStopping = false,
  String? projectName,
}) {
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
            Expanded(
              child: Row(
                children: [
                  Text(
                    'Progress',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (projectName != null && projectName.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Text(
                      '—',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        projectName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Row(
              children: [
                if (onStop != null) ...[
                  _SmallStopButton(
                    onPressed: isStopping ? null : onStop,
                    isStopping: isStopping,
                  ),
                  const SizedBox(width: 16),
                ],
                Text(
                  '${(percentage * 100).toStringAsFixed(1)}%',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        FluentProgressBar(
          value: percentage,
          height: 12,
          color:
              isPaused ? Colors.orange.shade700 : theme.colorScheme.primary,
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

/// Small stop button for embedding in progress card
class _SmallStopButton extends StatefulWidget {
  const _SmallStopButton({
    required this.onPressed,
    this.isStopping = false,
  });

  final VoidCallback? onPressed;
  final bool isStopping;

  @override
  State<_SmallStopButton> createState() => _SmallStopButtonState();
}

class _SmallStopButtonState extends State<_SmallStopButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = widget.onPressed == null;
    final color = theme.colorScheme.error;

    return MouseRegion(
      cursor: isDisabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDisabled
                ? color.withValues(alpha: 0.3)
                : _isHovered
                    ? color.withValues(alpha: 0.9)
                    : color.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isStopping)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                const Icon(
                  FluentIcons.stop_16_filled,
                  color: Colors.white,
                  size: 14,
                ),
              const SizedBox(width: 6),
              Text(
                widget.isStopping ? 'Stopping...' : 'Stop',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
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

/// Builds a single stat card
Widget buildStatCard(
  BuildContext context, {
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

/// Builds the stats row (success, failed, skipped)
Widget buildStatsSection(
  BuildContext context, {
  required TranslationProgress? progress,
}) {
  final theme = Theme.of(context);

  return Row(
    children: [
      Expanded(
        child: buildStatCard(
          context,
          icon: FluentIcons.checkmark_circle_24_regular,
          label: 'Success',
          value: progress?.successfulUnits.toString() ?? '0',
          color: Colors.green.shade700,
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: buildStatCard(
          context,
          icon: FluentIcons.dismiss_circle_24_regular,
          label: 'Failed',
          value: progress?.failedUnits.toString() ?? '0',
          color: theme.colorScheme.error,
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: buildStatCard(
          context,
          icon: FluentIcons.fast_forward_24_regular,
          label: 'Skipped',
          value: progress?.skippedUnits.toString() ?? '0',
          color: Colors.blue.shade700,
        ),
      ),
    ],
  );
}

/// Builds the error section
Widget buildErrorSection(
  BuildContext context, {
  required String errorMessage,
}) {
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
                errorMessage,
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

/// A terminal-like widget that displays real-time logs.
///
/// Shows logs from [LoggingService] with auto-scrolling and level-based coloring.
class LogTerminal extends StatefulWidget {
  const LogTerminal({
    super.key,
    this.height,
    this.expand = false,
  });

  /// Height of the terminal. If null and expand is false, defaults to 150px.
  final double? height;

  /// If true, the terminal will expand to fill available space.
  final bool expand;

  @override
  State<LogTerminal> createState() => _LogTerminalState();
}

class _LogTerminalState extends State<LogTerminal> {
  final ScrollController _scrollController = ScrollController();
  final List<LogEntry> _logs = [];
  StreamSubscription<LogEntry>? _logSubscription;
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();

    // Load recent logs
    _logs.addAll(LoggingService.instance.recentLogs);

    // Subscribe to new logs
    _logSubscription = LoggingService.instance.logStream.listen(_onNewLog);

    // Scroll to bottom after initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onNewLog(LogEntry entry) {
    if (!mounted) return;

    setState(() {
      _logs.add(entry);
      // Keep only last 500 logs in UI
      if (_logs.length > 500) {
        _logs.removeAt(0);
      }
    });

    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const terminalBg = Color(0xFF1E1E1E);
    const headerBg = Color(0xFF2D2D2D);

    final terminalContent = Container(
      decoration: BoxDecoration(
        color: terminalBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: headerBg,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  FluentIcons.code_24_regular,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 8),
                Text(
                  'Logs',
                  style: TextStyle(
                    color: Colors.grey.shade300,
                    fontFamily: 'Consolas, monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                // Auto-scroll toggle
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _autoScroll = !_autoScroll);
                      if (_autoScroll) _scrollToBottom();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _autoScroll
                            ? Colors.green.withValues(alpha: 0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            FluentIcons.arrow_down_24_regular,
                            size: 12,
                            color: _autoScroll
                                ? Colors.green.shade400
                                : Colors.grey.shade500,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Auto-scroll',
                            style: TextStyle(
                              color: _autoScroll
                                  ? Colors.green.shade400
                                  : Colors.grey.shade500,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Clear button
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => setState(() => _logs.clear()),
                    child: Icon(
                      FluentIcons.delete_24_regular,
                      size: 14,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Terminal content
          widget.expand
              ? Expanded(child: _buildTerminalContent())
              : SizedBox(
                  height: widget.height ?? 150,
                  child: _buildTerminalContent(),
                ),
        ],
      ),
    );

    return terminalContent;
  }

  Widget _buildTerminalContent() {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: _logs.isEmpty
          ? Center(
              child: Text(
                'Waiting for logs...',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontFamily: 'Consolas, monospace',
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final entry = _logs[index];
                return _buildLogLine(entry);
              },
            ),
    );
  }

  Widget _buildLogLine(LogEntry entry) {
    // Format timestamp as HH:mm:ss.SSS
    final time = entry.timestamp;
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';

    final levelColor = Color(entry.levelColor);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectableText.rich(
        TextSpan(
          style: const TextStyle(
            fontFamily: 'Consolas, monospace',
            fontSize: 11,
            height: 1.4,
          ),
          children: [
            // Timestamp
            TextSpan(
              text: '[$timeStr] ',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            // Level
            TextSpan(
              text: '[${entry.level.padRight(5)}] ',
              style: TextStyle(
                color: levelColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            // Message
            TextSpan(
              text: entry.message,
              style: TextStyle(color: Colors.grey.shade300),
            ),
            // Data (if present)
            if (entry.data != null)
              TextSpan(
                text: ' | ${entry.data}',
                style: TextStyle(color: Colors.grey.shade500),
              ),
          ],
        ),
      ),
    );
  }
}
