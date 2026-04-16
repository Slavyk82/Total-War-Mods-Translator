import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/home/providers/home_status_provider.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Header shown at the top of the Home page.
///
/// Layout: display-font "Home" title with a status sub-line on the left and
/// two trailing buttons on the right — a disabled `Command ⌘K` placeholder
/// (palette opens in a later plan, see parent spec §11) and a `+ New project`
/// primary action that navigates to the Mods library.
class HomePageHeader extends ConsumerWidget {
  const HomePageHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final statusAsync = ref.watch(homeStatusProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Home',
                  style: tokens.fontDisplay.copyWith(
                    fontSize: 28,
                    height: 1.1,
                    letterSpacing: -0.5,
                    color: tokens.text,
                  ),
                ),
                const SizedBox(height: 4),
                statusAsync.when(
                  data: (s) => Text(
                    s.label,
                    style: tokens.fontBody.copyWith(
                      fontSize: 13,
                      color: tokens.textDim,
                    ),
                  ),
                  loading: () => const SizedBox(height: 16),
                  error: (_, __) => const SizedBox(height: 16),
                ),
              ],
            ),
          ),
          TextButton(
            key: const Key('HomePageHeader.CommandButton'),
            onPressed: null, // placeholder — palette lands in a later plan
            child: const Text('Command  ⌘K'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('HomePageHeader.NewProjectButton'),
            onPressed: () => context.go(AppRoutes.mods),
            child: const Text('+ New project'),
          ),
        ],
      ),
    );
  }
}
