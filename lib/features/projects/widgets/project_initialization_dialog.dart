import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../../../services/projects/i_project_initialization_service.dart';

/// Token-themed popup showing real-time progress during project initialization
/// (pack extraction + translation-unit import).
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
        setState(() => _logs.add(logMessage));
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
    final tokens = context.tokens;

    final icon = _isInitializing
        ? FluentIcons.arrow_sync_24_regular
        : (_errorMessage != null
            ? FluentIcons.error_circle_24_regular
            : FluentIcons.checkmark_circle_24_regular);
    final iconColor = _errorMessage != null
        ? tokens.err
        : (_isInitializing ? tokens.accent : tokens.ok);
    final title = _isInitializing
        ? 'Initializing Project'
        : (_errorMessage != null
            ? 'Initialization Failed'
            : 'Initialization Complete');

    return PopScope(
      canPop: !_isInitializing,
      child: TokenDialog(
        icon: icon,
        iconColor: iconColor,
        title: title,
        subtitle: widget.projectName,
        width: 640,
        body: SizedBox(
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isInitializing)
                Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tokens.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Extracting and importing localization files...',
                      style: tokens.fontBody.copyWith(
                        fontSize: 13,
                        color: tokens.textDim,
                      ),
                    ),
                  ],
                )
              else if (_errorMessage != null)
                _buildErrorBanner(tokens)
              else
                _buildSuccessBanner(tokens),
              const SizedBox(height: 14),
              Divider(height: 1, color: tokens.border),
              const SizedBox(height: 10),
              Text(
                'Logs',
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: tokens.panel2,
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(color: tokens.border),
                  ),
                  child: _logs.isEmpty
                      ? Center(
                          child: Text(
                            'No logs yet...',
                            style: tokens.fontBody.copyWith(
                              fontSize: 12,
                              color: tokens.textFaint,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(10),
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            return _buildLogEntry(tokens, _logs[index]);
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
        actions: _isInitializing
            ? const []
            : [
                SmallTextButton(
                  label: 'Close',
                  icon: FluentIcons.checkmark_24_regular,
                  filled: true,
                  onTap: () =>
                      Navigator.of(context).pop(_errorMessage == null),
                ),
              ],
      ),
    );
  }

  Widget _buildErrorBanner(TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.errBg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.err.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            color: tokens.err,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: tokens.fontBody.copyWith(
                fontSize: 12.5,
                color: tokens.err,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessBanner(TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.okBg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.ok.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.checkmark_circle_24_regular,
            color: tokens.ok,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Successfully imported $_unitsImported translation units',
              style: tokens.fontBody.copyWith(
                fontSize: 12.5,
                color: tokens.ok,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(
    TwmtThemeTokens tokens,
    InitializationLogMessage log,
  ) {
    Color color;
    IconData? icon;

    switch (log.level) {
      case InitializationLogLevel.warning:
        color = tokens.warn;
        icon = FluentIcons.warning_24_regular;
        break;
      case InitializationLogLevel.error:
        color = tokens.err;
        icon = FluentIcons.error_circle_24_regular;
        break;
      default:
        color = tokens.textDim;
        icon = null;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              log.message,
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: color,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
