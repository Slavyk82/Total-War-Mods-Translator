import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_target_language_provider.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';

typedef BulkScope = ({
  List<ProjectWithDetails> visible,
  List<ProjectWithDetails> matching,
});

final visibleProjectsForBulkProvider = Provider<AsyncValue<BulkScope>>((ref) {
  final visibleAsync = ref.watch(paginatedProjectsProvider);
  final targetCode = ref.watch(bulkTargetLanguageProvider).asData?.value;

  return visibleAsync.when(
    data: (visible) {
      final matching = targetCode == null
          ? <ProjectWithDetails>[]
          : visible
              .where(
                (p) => p.languages.any((l) => l.language?.code == targetCode),
              )
              .toList();
      return AsyncValue.data((visible: visible, matching: matching));
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});
