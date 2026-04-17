import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../fluent/fluent_widgets.dart';
import '../navigation/navigation_sidebar.dart';
import 'fluent_scaffold.dart';
import '../../features/translation_editor/providers/editor_providers.dart';
import '../../features/pack_compilation/providers/pack_compilation_providers.dart';

/// Shell layout: sidebar + active screen.
///
/// Each screen now renders its own toolbar/header (Plan 5c), so the global
/// breadcrumb previously rendered here has been removed.
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
    return FluentScaffold(
      body: Row(
        children: [
          NavigationSidebar(
            onNavigate: (p) {
              if (_canNavigate(context, ref)) context.go(p);
            },
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
