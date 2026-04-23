import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/mods/models/scan_log_message.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

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
    final tokens = context.tokens;

    return Center(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 400),
        decoration: BoxDecoration(
          color: tokens.panel,
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          border: Border.all(color: tokens.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
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
                color: tokens.panel2,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(tokens.radiusMd - 1),
                ),
                border: Border(bottom: BorderSide(color: tokens.border)),
              ),
              child: Row(
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
                    widget.title,
                    style: tokens.fontDisplay.copyWith(
                      color: tokens.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    FluentIcons.window_console_20_regular,
                    size: 18,
                    color: tokens.textDim,
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
                          style: tokens.fontMono.copyWith(
                            color: tokens.textFaint,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        shrinkWrap: true,
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          return _buildLogLine(_logs[index], tokens);
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogLine(ScanLogMessage log, TwmtThemeTokens tokens) {
    Color textColor;
    String prefix;

    switch (log.level) {
      case ScanLogLevel.error:
        textColor = tokens.err;
        prefix = '✕';
        break;
      case ScanLogLevel.warning:
        textColor = tokens.warn;
        prefix = '⚠';
        break;
      case ScanLogLevel.debug:
        textColor = tokens.textFaint;
        prefix = '·';
        break;
      case ScanLogLevel.info:
        textColor = tokens.textMid;
        prefix = '›';
    }

    final lineStyle = tokens.fontMono.copyWith(
      color: textColor,
      fontSize: 12,
      height: 1.4,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$prefix ', style: lineStyle),
          Expanded(
            child: Text(log.message, style: lineStyle),
          ),
        ],
      ),
    );
  }
}
