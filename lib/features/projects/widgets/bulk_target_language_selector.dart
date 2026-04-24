import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_target_language_provider.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/models/domain/language.dart';

class BulkTargetLanguageSelector extends ConsumerWidget {
  const BulkTargetLanguageSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languagesAsync = ref.watch(allLanguagesProvider);
    final current = ref.watch(bulkTargetLanguageProvider).asData?.value;

    return languagesAsync.when(
      data: (languages) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: DropdownMenu<String>(
          width: 296,
          label: const Text('Target language'),
          initialSelection: current,
          dropdownMenuEntries: [
            for (final l in languages)
              DropdownMenuEntry<String>(
                value: l.code,
                label: l.displayName,
              ),
          ],
          onSelected: (code) {
            if (code != null) {
              ref.read(bulkTargetLanguageProvider.notifier).setLanguage(code);
            }
          },
        ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Failed to load languages: $e'),
      ),
    );
  }
}
