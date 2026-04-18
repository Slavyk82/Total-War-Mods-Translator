import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Compact accent card surfaced at the end of a workflow screen to nudge the
/// user toward the next pipeline step. Reads "Next: <label>" and routes via
/// [onTap]. Disabled when [onTap] is `null`.
class NextStepCta extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData icon;

  const NextStepCta({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = FluentIcons.arrow_right_24_regular,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final disabled = onTap == null;
    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: disabled ? tokens.panel2 : tokens.accentBg,
            border: Border.all(
              color: disabled ? tokens.border : tokens.accent,
            ),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: disabled ? tokens.textFaint : tokens.accent,
              ),
              const SizedBox(width: 8),
              Text(
                'Next: $label',
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: disabled ? tokens.textFaint : tokens.accent,
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
