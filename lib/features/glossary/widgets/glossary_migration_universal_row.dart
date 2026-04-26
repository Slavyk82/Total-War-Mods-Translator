import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/services/glossary/glossary_migration_service.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// One universal glossary row in [GlossaryMigrationScreen].
///
/// Renders the glossary name, optional description, and a "Target: {lang} —
/// {N} entries" footer on the left; an Export-CSV button and a
/// "Convert to…" dropdown on the right. The dropdown always exposes a
/// "— Don't convert —" option (value `null`) in addition to every
/// [ConfiguredGame].
class GlossaryMigrationUniversalRow extends StatelessWidget {
  const GlossaryMigrationUniversalRow({
    super.key,
    required this.info,
    required this.games,
    required this.selectedGameCode,
    required this.onChanged,
    required this.onExport,
  });

  final UniversalGlossaryInfo info;
  final List<ConfiguredGame> games;
  final String? selectedGameCode;
  final ValueChanged<String?> onChanged;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.panel2,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.name,
                  style: tokens.fontBody.copyWith(
                    fontSize: 14,
                    color: tokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (info.description != null && info.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      info.description!,
                      style: tokens.fontBody
                          .copyWith(fontSize: 12, color: tokens.textDim),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  t.glossary.messages.targetLanguageEntries(languageCode: info.targetLanguageCode, count: info.entryCount),
                  style: tokens.fontMono
                      .copyWith(fontSize: 12, color: tokens.textDim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SmallTextButton(
            key: Key('glossary-migration-export-${info.id}'),
            label: t.glossary.actions.exportCsv,
            icon: FluentIcons.arrow_export_24_regular,
            onTap: onExport,
          ),
          const SizedBox(width: 8),
          DropdownButton<String?>(
            key: Key('glossary-migration-convert-${info.id}'),
            value: selectedGameCode,
            hint: Text(
              t.glossary.dialogs.convertTo,
              style: tokens.fontBody
                  .copyWith(fontSize: 12.5, color: tokens.textDim),
            ),
            style:
                tokens.fontBody.copyWith(fontSize: 12.5, color: tokens.text),
            dropdownColor: tokens.panel,
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  t.glossary.dialogs.dontConvert,
                  style: tokens.fontBody
                      .copyWith(fontSize: 12.5, color: tokens.text),
                ),
              ),
              ...games.map(
                (g) => DropdownMenuItem<String?>(
                  value: g.code,
                  child: Text(
                    g.name,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.fontBody
                        .copyWith(fontSize: 12.5, color: tokens.text),
                  ),
                ),
              ),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
