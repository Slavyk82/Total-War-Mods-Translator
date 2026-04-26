import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/widgets/fluent/fluent_toast.dart';

import '../providers/steam_publish_providers.dart';
import '../utils/workshop_url_parser.dart';

/// Parses [rawInput] into a Workshop id and persists it on the right
/// repository for [item], then invalidates [publishableItemsProvider] so
/// downstream rows rebuild with the new id.
///
/// Surfaces a warning toast when [rawInput] doesn't parse and an error toast
/// when the repository call throws. Returns true on success, false otherwise.
/// Callers must check `mounted` themselves before consuming the result —
/// this helper does NOT touch widget state.
Future<bool> saveWorkshopId({
  required WidgetRef ref,
  required BuildContext context,
  required PublishableItem item,
  required String rawInput,
}) async {
  final trimmed = rawInput.trim();
  if (trimmed.isEmpty) return false;

  final parsed = parseWorkshopId(trimmed);
  if (parsed == null) {
    FluentToast.warning(
      context,
      t.steamPublish.steamId.toasts.parseWarning,
    );
    return false;
  }

  try {
    if (item is ProjectPublishItem) {
      final projectRepo = ref.read(projectRepositoryProvider);
      final projectResult = await projectRepo.getById(item.project.id);
      if (projectResult.isOk) {
        final updated = projectResult.value.copyWith(
          publishedSteamId: parsed,
          updatedAt: projectResult.value.updatedAt,
        );
        await projectRepo.update(updated);
      }
    } else if (item is CompilationPublishItem) {
      final compilationRepo = ref.read(compilationRepositoryProvider);
      // Preserve existing fallback semantics from SteamActionCell — when an
      // item has never been published, publishedAt is null and we write 0.
      await compilationRepo.updateAfterPublish(
        item.compilation.id,
        parsed,
        item.publishedAt ?? 0,
      );
    }
    ref.invalidate(publishableItemsProvider);
    return true;
  } catch (e) {
    if (context.mounted) {
      FluentToast.error(context, t.steamPublish.steamId.toasts.saveFailed(error: e));
    }
    return false;
  }
}
