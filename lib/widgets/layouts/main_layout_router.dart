import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../fluent/fluent_widgets.dart';
import '../navigation/breadcrumb.dart';
import '../navigation/navigation_sidebar.dart';
import 'fluent_scaffold.dart';
import '../../config/router/app_router.dart';
import '../../features/translation_editor/providers/editor_providers.dart';
import '../../features/pack_compilation/providers/pack_compilation_providers.dart';

/// Shell layout: sidebar + global breadcrumb + active screen.
///
/// This plan keeps the breadcrumb rendered at the shell level. Plans 3-5
/// move it into each screen's toolbar, at which point the [Breadcrumb]
/// line below is removed.
class MainLayoutRouter extends ConsumerWidget {
  const MainLayoutRouter({super.key, required this.child});

  final Widget child;

  bool _canNavigate(BuildContext context, WidgetRef ref) {
    if (ref.read(translationInProgressProvider)) {
      FluentToast.warning(
        context,
        'Translation in progress. Stop the translation first.',
      );
      return false;
    }
    if (ref.read(compilationInProgressProvider)) {
      FluentToast.warning(
        context,
        'Pack generation in progress. Stop the generation first.',
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final hideBreadcrumb = _shouldHideBreadcrumb(path);

    return FluentScaffold(
      body: Column(
        children: [
          if (!hideBreadcrumb) const Breadcrumb(),
          Expanded(
            child: Row(
              children: [
                NavigationSidebar(
                  onNavigate: (p) {
                    if (_canNavigate(context, ref)) context.go(p);
                  },
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Editor and single-publish screens render their own header and would
  /// double-up with the shell breadcrumb.
  bool _shouldHideBreadcrumb(String path) {
    if (path.contains('/editor/')) return true;
    if (path == AppRoutes.steamPublishSingle) return true;
    if (path == AppRoutes.steamPublishBatch) return true;
    return false;
  }
}
