import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../services/projects/i_project_initialization_service.dart';
import '../../../widgets/fluent/fluent_widgets.dart';

/// Simplified project initialization dialog showing only extraction and import logs.
///
/// This dialog displays real-time progress and logs during:
/// - Pack file extraction (.pack to .loc files)
/// - Translation units import to database
class ProjectInitializationDialog extends StatefulWidget {
  final String projectName;
  final Stream<InitializationLogMessage> logStream;
  final Future<int> Function() onInitialize;

  const ProjectInitializationDialog({
    super.key,
    required this.projectName,
    required this.logStream,
    required this.onInitialize,
  });

  @override
  State<ProjectInitializationDialog> createState() =>
      _ProjectInitializationDialogState();
}

class _ProjectInitializationDialogState
    extends State<ProjectInitializationDialog> {
  final List<InitializationLogMessage> _logs = [];
  final ScrollController _scrollController = ScrollController();
  bool _isInitializing = true;
  String? _errorMessage;
  int? _unitsImported;

  @override
  void initState() {
    super.initState();
    _listenToLogs();
    _initialize();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _listenToLogs() {
    widget.logStream.listen((logMessage) {
      if (mounted) {
        setState(() {
          _logs.add(logMessage);
        });
        // Auto-scroll to bottom
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && _scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      }
    });
  }

  Future<void> _initialize() async {
    try {
      final unitsCount = await widget.onInitialize();
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _unitsImported = unitsCount;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_isInitializing,
      child: AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(
              _isInitializing
                  ? FluentIcons.arrow_sync_24_regular
                  : (_errorMessage != null
                      ? FluentIcons.error_circle_24_regular
                      : FluentIcons.checkmark_circle_24_regular),
              color: _errorMessage != null
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isInitializing
                    ? 'Initializing Project'
                    : (_errorMessage != null
                        ? 'Initialization Failed'
                        : 'Initialization Complete'),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Project name
              Text(
                widget.projectName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              // Status message
              if (_isInitializing)
                Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Extracting and importing localization files...',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                )
              else if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        FluentIcons.error_circle_24_regular,
                        color: theme.colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        FluentIcons.checkmark_circle_24_regular,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Successfully imported $_unitsImported translation units',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Logs section
              Text(
                'Logs',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              // Logs list
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: _logs.isEmpty
                      ? Center(
                          child: Text(
                            'No logs yet...',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(8),
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            final log = _logs[index];
                            return _buildLogEntry(log, theme);
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!_isInitializing)
            FluentDialogButton(
              icon: FluentIcons.checkmark_24_regular,
              label: 'Close',
              isPrimary: true,
              onTap: () => Navigator.of(context).pop(_errorMessage == null),
            ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(InitializationLogMessage log, ThemeData theme) {
    Color? logColor;
    IconData? logIcon;

    if (log.level == InitializationLogLevel.warning) {
      logColor = Colors.orange;
      logIcon = FluentIcons.warning_24_regular;
    } else if (log.level == InitializationLogLevel.error) {
      logColor = theme.colorScheme.error;
      logIcon = FluentIcons.error_circle_24_regular;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (logIcon != null) ...[
            Icon(
              logIcon,
              size: 14,
              color: logColor,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              log.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: log.level == InitializationLogLevel.error
                    ? theme.colorScheme.error
                    : (log.level == InitializationLogLevel.warning
                        ? Colors.orange
                        : theme.colorScheme.onSurface.withValues(alpha: 0.8)),
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
