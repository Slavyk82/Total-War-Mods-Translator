import 'dart:io' show exit;

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/glossary/providers/glossary_migration_providers.dart';
import 'package:twmt/features/glossary/widgets/glossary_migration_universal_row.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/glossary/glossary_migration_service.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// Blocking popup dialog shown at app boot when the glossary schema is
/// mid-migration to strictly game-scoped glossaries.
///
/// Drives three sections:
///  * An intro warning,
///  * Universal glossaries awaiting user decisions (convert / drop),
///  * Duplicate (game_code, target_language_id) groups that will be merged.
///
/// The footer has `Cancel migration` (closes the app on desktop via [exit];
/// on web it shows a toast asking the user to close the tab) and
/// `Apply and continue` (runs [GlossaryMigrationService.applyMigration] then
/// invokes [onDone]).
class GlossaryMigrationScreen extends ConsumerStatefulWidget {
  const GlossaryMigrationScreen({
    super.key,
    required this.pending,
    required this.onDone,
  });

  final PendingGlossaryMigration pending;
  final VoidCallback onDone;

  @override
  ConsumerState<GlossaryMigrationScreen> createState() =>
      _GlossaryMigrationScreenState();
}

class _GlossaryMigrationScreenState
    extends ConsumerState<GlossaryMigrationScreen> {
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    // Seed the plan after first frame to avoid mutating a provider during
    // build. Each universal starts as `null` (i.e. "— Don't convert —").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(glossaryMigrationPlanProvider.notifier)
          .seed(widget.pending.universals.map((u) => u.id).toList());
    });
  }

  Future<void> _exportCsv(UniversalGlossaryInfo info) async {
    final sanitized = info.name.replaceAll(RegExp(r'[^\w\-]'), '_');
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export "${info.name}" to CSV',
      fileName: '$sanitized.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (result == null || !mounted) return;
    final exportService = ref.read(glossaryServiceProvider);
    final outcome = await exportService.exportToCsv(
      glossaryId: info.id,
      filePath: result,
    );
    if (!mounted) return;
    if (outcome.isErr) {
      FluentToast.error(context, 'Export failed: ${outcome.error}');
    } else {
      FluentToast.success(context, 'Exported ${outcome.value} entries');
    }
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      final service = ref.read(glossaryMigrationServiceProvider);
      final plan = ref.read(glossaryMigrationPlanProvider);
      await service.applyMigration(MigrationPlan(conversions: plan));
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, 'Migration failed: $e');
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  /// Closes the app cleanly. The DB is left half-migrated; the boot-time
  /// predicate will re-open this screen next launch.
  void _cancel() {
    // Cancel leaves the DB half-migrated; next boot will show this screen
    // again.
    if (kIsWeb) {
      // On web there's no reliable exit; show a toast and leave the modal in
      // place.
      FluentToast.info(
        context,
        'Please close the browser tab to cancel the migration.',
      );
      return;
    }
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final configuredGamesAsync = ref.watch(configuredGamesProvider);
    final plan = ref.watch(glossaryMigrationPlanProvider);
    final games =
        configuredGamesAsync.asData?.value ?? const <ConfiguredGame>[];

    final viewportHeight = MediaQuery.of(context).size.height;
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: tokens.panel,
        insetPadding: const EdgeInsets.all(40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          side: BorderSide(color: tokens.border),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 900,
            maxHeight: viewportHeight - 80,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      FluentIcons.warning_24_filled,
                      size: 24,
                      color: tokens.warn,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Glossary migration required',
                        style: tokens.fontDisplay.copyWith(
                          fontSize: 20,
                          color: tokens.text,
                          fontStyle: tokens.fontDisplayStyle,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Glossaries are now strictly game-specific. '
                  'Resolve the following items to continue.',
                  style: tokens.fontBody
                      .copyWith(fontSize: 13, color: tokens.textDim),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.pending.universals.isNotEmpty)
                          _UniversalsSection(
                            universals: widget.pending.universals,
                            games: games,
                            plan: plan,
                            onChanged: (id, gc) => ref
                                .read(glossaryMigrationPlanProvider.notifier)
                                .setChoice(id, gc),
                            onExport: _exportCsv,
                          ),
                        if (widget.pending.duplicates.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _DuplicatesSection(
                              groups: widget.pending.duplicates),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SmallTextButton(
                      key: const Key('glossary-migration-cancel'),
                      label: 'Cancel migration',
                      onTap: _applying ? null : _cancel,
                    ),
                    const SizedBox(width: 8),
                    SmallTextButton(
                      key: const Key('glossary-migration-apply'),
                      label: _applying ? 'Applying…' : 'Apply and continue',
                      icon: FluentIcons.checkmark_24_regular,
                      filled: true,
                      onTap: _applying ? null : _apply,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UniversalsSection extends StatelessWidget {
  const _UniversalsSection({
    required this.universals,
    required this.games,
    required this.plan,
    required this.onChanged,
    required this.onExport,
  });

  final List<UniversalGlossaryInfo> universals;
  final List<ConfiguredGame> games;
  final Map<String, String?> plan;
  final void Function(String id, String? gameCode) onChanged;
  final void Function(UniversalGlossaryInfo info) onExport;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Universal glossaries',
          style: tokens.fontDisplay.copyWith(
            fontSize: 16,
            color: tokens.text,
            fontStyle: tokens.fontDisplayStyle,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        for (final u in universals) ...[
          GlossaryMigrationUniversalRow(
            info: u,
            games: games,
            selectedGameCode: plan[u.id],
            onChanged: (gc) => onChanged(u.id, gc),
            onExport: () => onExport(u),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: tokens.warnBg,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.warn.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(FluentIcons.info_24_regular, size: 14, color: tokens.warn),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Universal glossaries not converted will be deleted '
                  'permanently.',
                  style: tokens.fontBody
                      .copyWith(fontSize: 12, color: tokens.warn),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DuplicatesSection extends StatelessWidget {
  const _DuplicatesSection({required this.groups});

  final List<DuplicateGlossaryGroup> groups;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Duplicate glossaries',
          style: tokens.fontDisplay.copyWith(
            fontSize: 16,
            color: tokens.text,
            fontStyle: tokens.fontDisplayStyle,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'These glossaries will be merged automatically. Duplicate entries '
          '(same source term, case-insensitive) will be deduplicated, keeping '
          'the most recent one.',
          style:
              tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
        ),
        const SizedBox(height: 8),
        for (final g in groups) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tokens.panel2,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${g.gameCode} · ${g.targetLanguageCode}',
                  style: tokens.fontMono
                      .copyWith(fontSize: 12, color: tokens.textDim),
                ),
                const SizedBox(height: 4),
                for (final m in g.members)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '  • ${m.name} (${m.entryCount} entries)',
                      style: tokens.fontBody
                          .copyWith(fontSize: 12, color: tokens.text),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
