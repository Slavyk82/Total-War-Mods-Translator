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

    return Center(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 400),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
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
              decoration: const BoxDecoration(
                color: Color(0xFF2D2D2D),
                borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF3794FF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    FluentIcons.window_console_20_regular,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
            // Terminal content
            Flexible(
              child: Container(
                constraints: const BoxConstraints(minHeight: 150),
                child: _logs.isEmpty
                    ? const Center(
                        child: Text(
                          'Initializing...',
                          style: TextStyle(
                            color: Color(0xFF808080),
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
                          return _buildLogLine(_logs[index]);
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogLine(ScanLogMessage log) {
    Color textColor;
    String prefix;

    switch (log.level) {
      case ScanLogLevel.error:
        textColor = const Color(0xFFF14C4C);
        prefix = '✕';
        break;
      case ScanLogLevel.warning:
        textColor = const Color(0xFFCCA700);
        prefix = '⚠';
        break;
      case ScanLogLevel.debug:
        textColor = const Color(0xFF808080);
        prefix = '·';
        break;
      case ScanLogLevel.info:
      default:
        textColor = const Color(0xFFCCCCCC);
        prefix = '›';
        break;
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

