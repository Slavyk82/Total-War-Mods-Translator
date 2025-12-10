import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/mods/models/scan_log_message.dart';

/// A terminal-like widget that displays scan progress logs
class ScanTerminalWidget extends StatefulWidget {
  final Stream<ScanLogMessage> logStream;
  final String title;

  const ScanTerminalWidget({
    super.key,
    required this.logStream,
    this.title = 'Scanning Workshop...',
  });

  @override
  State<ScanTerminalWidget> createState() => _ScanTerminalWidgetState();
}

class _ScanTerminalWidgetState extends State<ScanTerminalWidget> {
  final List<ScanLogMessage> _logs = [];
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<ScanLogMessage>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.logStream.listen(_onLogMessage);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogMessage(ScanLogMessage message) {
    if (mounted) {
      setState(() {
        _logs.add(message);
      });
      // Auto-scroll to bottom
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Theme-aware colors
    final backgroundColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);
    final headerColor = isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE8E8E8);
    final titleColor = isDark ? Colors.white : Colors.black87;
    final iconColor = isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black54;

    return Center(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 400),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Terminal header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              ),
              child: Row(
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
                    widget.title,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    FluentIcons.window_console_20_regular,
                    size: 18,
                    color: iconColor,
                  ),
                ],
              ),
            ),
            // Terminal content
            Flexible(
              child: Container(
                constraints: const BoxConstraints(minHeight: 150),
                child: _logs.isEmpty
                    ? Center(
                        child: Text(
                          'Initializing...',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontFamily: 'Consolas',
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        shrinkWrap: true,
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          return _buildLogLine(_logs[index], isDark);
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogLine(ScanLogMessage log, bool isDark) {
    Color textColor;
    String prefix;

    switch (log.level) {
      case ScanLogLevel.error:
        textColor = isDark ? const Color(0xFFF14C4C) : const Color(0xFFD32F2F);
        prefix = '✕';
        break;
      case ScanLogLevel.warning:
        textColor = isDark ? const Color(0xFFCCA700) : const Color(0xFFB8860B);
        prefix = '⚠';
        break;
      case ScanLogLevel.debug:
        textColor = isDark ? const Color(0xFF808080) : const Color(0xFF9E9E9E);
        prefix = '·';
        break;
      case ScanLogLevel.info:
        textColor = isDark ? const Color(0xFFCCCCCC) : const Color(0xFF424242);
        prefix = '›';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$prefix ',
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontFamily: 'Consolas',
              height: 1.4,
            ),
          ),
          Expanded(
            child: Text(
              log.message,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontFamily: 'Consolas',
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

