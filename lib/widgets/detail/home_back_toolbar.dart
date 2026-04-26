import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/i18n/strings.g.dart';

import '../../config/router/app_router.dart';
import '../../config/router/navigation_guard.dart';
import '../../theme/twmt_theme_tokens.dart';
import '../lists/small_icon_button.dart';

/// Top toolbar for top-level screens reachable from the sidebar.
///
/// 48 px bar containing a back arrow on the left and an optional [leading]
/// widget right next to it (typically a `ListToolbarLeading` carrying the
/// screen icon + title + count). The back arrow returns to [AppRoutes.home],
/// guarded by [canNavigateNow] so an in-flight translation or pack
/// compilation blocks the move with the existing toast.
class HomeBackToolbar extends ConsumerWidget {
  final Widget? leading;

  const HomeBackToolbar({super.key, this.leading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l = leading;
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
            tooltip: t.widgets.toolbar.back,
            onTap: () {
              if (canNavigateNow(context, ref)) {
                context.go(AppRoutes.home);
              }
            },
          ),
          if (l != null) ...[
            const SizedBox(width: 12),
            Expanded(child: l),
          ],
        ],
      ),
    );
  }
}
