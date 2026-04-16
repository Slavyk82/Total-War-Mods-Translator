import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../../../../models/domain/translation_version.dart';

/// Status cell widget for DataGrid
///
/// Displays a 7x7px status dot with a token colour matching the translation
/// version status (pending/translated/needs review).
class StatusCellRenderer extends StatelessWidget {
  final TranslationVersionStatus status;

  const StatusCellRenderer({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8.0),
      child: StatusIcon(status: status),
    );
  }
}

/// Status indicator widget rendered as a 7x7px dot.
///
/// Colour mapping (per plan §4.3):
/// - pending     -> tokens.textFaint
/// - translated  -> tokens.ok
/// - needsReview -> tokens.warn
class StatusIcon extends StatelessWidget {
  final TranslationVersionStatus status;

  const StatusIcon({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: _statusColor(tokens),
        shape: BoxShape.circle,
      ),
    );
  }

  Color _statusColor(TwmtThemeTokens tokens) {
    switch (status) {
      case TranslationVersionStatus.pending:
        return tokens.textFaint;
      case TranslationVersionStatus.translated:
        return tokens.ok;
      case TranslationVersionStatus.needsReview:
        return tokens.warn;
    }
  }
}
