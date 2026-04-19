import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';

/// Token-themed progress popup for the "clear translations" operation.
class ClearProgressDialog extends StatelessWidget {
  final int processed;
  final int total;
  final String phase;

  const ClearProgressDialog({
    super.key,
    required this.processed,
    required this.total,
    required this.phase,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final progress = total > 0 ? processed / total : 0.0;
    final percentage = (progress * 100).toStringAsFixed(0);

    return TokenDialog(
      icon: FluentIcons.delete_24_regular,
      iconColor: tokens.err,
      title: 'Clearing Translations',
      width: 440,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            phase,
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.textDim,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: tokens.panel2,
              valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$processed / $total',
                style: tokens.fontBody.copyWith(
                  fontSize: 12,
                  color: tokens.textDim,
                ),
              ),
              Text(
                '$percentage%',
                style: tokens.fontBody.copyWith(
                  fontSize: 12,
                  color: tokens.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
