import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Centered icon + title + subtitle message used by the
/// [ModelManagementDialog] for its loading-error and "no models found"
/// placeholders.
///
/// [iconColor] lets callers pick between the error accent (`tokens.err`) and
/// the neutral faint (`tokens.textFaint`) so the same shape serves both
/// cases. All other colours come from [context.tokens].
class LlmModelEmptyState extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const LlmModelEmptyState({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: iconColor),
          const SizedBox(height: 16),
          Text(
            title,
            style: tokens.fontBody.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: tokens.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: tokens.textDim,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
