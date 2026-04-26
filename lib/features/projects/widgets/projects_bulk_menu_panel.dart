import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/features/projects/providers/bulk_info_card_dismissed_provider.dart';
import 'package:twmt/features/projects/widgets/bulk_action_buttons.dart';
import 'package:twmt/features/projects/widgets/bulk_info_card.dart';
import 'package:twmt/features/projects/widgets/bulk_scope_indicator.dart';
import 'package:twmt/features/projects/widgets/bulk_target_language_selector.dart';
import 'package:twmt/features/translation_editor/widgets/editor_toolbar_batch_settings.dart';
import 'package:twmt/features/translation_editor/widgets/editor_toolbar_model_selector.dart';
import 'package:twmt/features/translation_editor/widgets/editor_toolbar_skip_tm.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Right-hand bulk-actions side panel of the Projects screen.
///
/// Width matches the translation editor's inspector panel default (320 px).
class ProjectsBulkMenuPanel extends ConsumerWidget {
  const ProjectsBulkMenuPanel({super.key});

  static const double width = 320;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoDismissed =
        ref.watch(bulkInfoCardDismissedProvider).asData?.value ?? false;
    final tokens = context.tokens;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(left: BorderSide(color: tokens.border)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BulkInfoCard(),
            const BulkTargetLanguageSelector(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
              child: Text(
                t.projects.bulk.sectionSettings,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: EditorToolbarModelSelector(compact: true),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: EditorToolbarSkipTm(),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: EditorToolbarBatchSettings(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
              child: Text(
                t.projects.bulk.sectionActions,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const BulkActionButtons(),
            const BulkScopeIndicator(),
            if (infoDismissed)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: TextButton.icon(
                  onPressed: () =>
                      ref.read(bulkInfoCardDismissedProvider.notifier).reset(),
                  icon: const Icon(Icons.info_outline, size: 14),
                  label: Text(t.projects.bulk.sectionInfo),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
