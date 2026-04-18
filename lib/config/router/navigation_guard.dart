import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/pack_compilation/providers/pack_compilation_providers.dart';
import '../../features/translation_editor/providers/editor_providers.dart';
import '../../widgets/fluent/fluent_widgets.dart';

/// Returns `true` if it is safe to navigate away from the current screen.
///
/// When a translation or pack compilation is in progress, this emits the
/// matching warning toast on [context] and returns `false`. Callers should
/// short-circuit their navigation on a `false` result.
///
/// Shared between the sidebar ([MainLayoutRouter]) and the detail-screen
/// crumb tap handler.
bool canNavigateNow(BuildContext context, WidgetRef ref) {
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
