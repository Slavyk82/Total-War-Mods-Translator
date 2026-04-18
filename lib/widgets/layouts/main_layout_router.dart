import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/router/navigation_guard.dart';
import '../navigation/navigation_sidebar.dart';
import 'fluent_scaffold.dart';

/// Shell layout: sidebar + active screen.
///
/// Each screen renders its own toolbar/header; the in-progress-operation guard
/// is shared with crumb taps via [canNavigateNow].
class MainLayoutRouter extends ConsumerWidget {
  const MainLayoutRouter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FluentScaffold(
      body: Row(
        children: [
          NavigationSidebar(
            onNavigate: (p) {
              if (canNavigateNow(context, ref)) context.go(p);
            },
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
