import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';

/// Detail-screen top toolbar (§7.2 / §7.5).
///
/// 48px fixed height with a back button, ellipsised crumb text, and optional
/// trailing widgets (actions). Used by Project Detail, Glossary Detail, and
/// the three Plan 5c wizard screens.
class DetailScreenToolbar extends StatelessWidget {
  final String crumb;
  final VoidCallback onBack;
  final List<Widget> trailing;

  const DetailScreenToolbar({
    super.key,
    required this.crumb,
    required this.onBack,
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          SmallIconButton(
            icon: FluentIcons.arrow_left_24_regular,
            tooltip: 'Back',
            onTap: onBack,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              crumb,
              overflow: TextOverflow.ellipsis,
              style: tokens.fontMono.copyWith(
                fontSize: 12,
                color: tokens.textDim,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (trailing.isNotEmpty) ...[
            const SizedBox(width: 12),
            ...trailing,
          ],
        ],
      ),
    );
  }
}
