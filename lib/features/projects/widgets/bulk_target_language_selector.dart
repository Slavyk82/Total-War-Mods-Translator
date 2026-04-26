import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/features/projects/providers/bulk_target_language_provider.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/providers/visible_projects_for_bulk_provider.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

class BulkTargetLanguageSelector extends ConsumerWidget {
  const BulkTargetLanguageSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languagesAsync = ref.watch(allLanguagesProvider);
    final scopeAsync = ref.watch(visibleProjectsForBulkProvider);
    final current = ref.watch(bulkTargetLanguageProvider).asData?.value;
    final tokens = context.tokens;

    final padding = const EdgeInsets.fromLTRB(12, 12, 12, 0);

    if (languagesAsync.isLoading || scopeAsync.isLoading) {
      return const SizedBox.shrink();
    }
    if (languagesAsync.hasError) {
      return Padding(
        padding: padding,
        child: Text(
          t.projects.bulk.languageSelector.loadFailed(error: languagesAsync.error.toString()),
          style: tokens.fontBody.copyWith(color: tokens.err, fontSize: 12),
        ),
      );
    }

    final allLanguages = languagesAsync.asData?.value ?? const <Language>[];
    final scope = scopeAsync.asData?.value;

    // Only propose languages already created in at least one visible project.
    final visibleCodes = <String>{};
    if (scope != null) {
      for (final project in scope.visible) {
        for (final pl in project.languages) {
          final code = pl.language?.code;
          if (code != null) visibleCodes.add(code);
        }
      }
    }

    final filtered = allLanguages
        .where((l) => visibleCodes.contains(l.code))
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    if (filtered.isEmpty) {
      return Padding(
        padding: padding,
        child: Text(
          t.projects.bulk.languageSelector.noLanguages,
          style: tokens.fontBody.copyWith(color: tokens.textDim, fontSize: 12),
        ),
      );
    }

    // If only one language exists across visible projects and no matching
    // selection is active, auto-select it so the user can act immediately.
    final effective = current != null && visibleCodes.contains(current)
        ? current
        : null;
    if (effective == null && filtered.length == 1) {
      final onlyCode = filtered.first.code;
      Future.microtask(() {
        ref.read(bulkTargetLanguageProvider.notifier).setLanguage(onlyCode);
      });
    }

    return Padding(
      padding: padding,
      child: DropdownMenu<String>(
        width: 296,
        label: Text(t.projects.bulk.targetLanguageLabel),
        initialSelection: effective,
        dropdownMenuEntries: [
          for (final l in filtered)
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
    );
  }
}
