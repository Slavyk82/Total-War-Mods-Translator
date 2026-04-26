import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/projects/providers/project_detail_providers.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/utils/open_project_editor.dart';
import 'package:twmt/features/projects/widgets/add_language_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/shared/repository_providers.dart' as shared_repo;
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// Language switcher chip + popover used by the translation editor.
///
/// Renders the current language as a filled accent chip. Tapping opens a menu
/// listing every language declared in the project (with its progress %), a
/// trash affordance per language (disabled when the project has a single
/// language), and an "Add language" entry at the bottom that reuses
/// [AddLanguageDialog].
class EditorLanguageSwitcher extends ConsumerWidget {
  const EditorLanguageSwitcher({
    super.key,
    required this.projectId,
    required this.currentLanguageId,
  });

  final String projectId;
  final String currentLanguageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final langsAsync = ref.watch(projectLanguagesProvider(projectId));
    final langs = langsAsync.asData?.value ?? const <ProjectLanguageDetails>[];
    final current = langs
        .where((l) => l.projectLanguage.languageId == currentLanguageId)
        .firstOrNull;

    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      builder: (context, controller, _) {
        return _SwitcherChip(
          key: const Key('editor-language-switcher-chip'),
          label: current?.language.name ?? '—',
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
      menuChildren: [
        if (langs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(t.translationEditor.languageSwitcher.noLanguage,
                style: tokens.fontBody
                    .copyWith(fontSize: 12, color: tokens.textDim)),
          )
        else
          for (final l in langs)
            _LanguageMenuItem(
              details: l,
              isCurrent: l.projectLanguage.languageId == currentLanguageId,
              canDelete: langs.length > 1,
              onSelect: () => _switchTo(context, l.projectLanguage.languageId),
              onDelete: () => _confirmDelete(context, ref, l),
            ),
        const Divider(height: 1),
        _AddLanguageMenuItem(
          onTap: () => _openAddDialog(context, ref, langs),
        ),
      ],
    );
  }

  void _switchTo(BuildContext context, String languageId) {
    if (languageId == currentLanguageId) return;
    context.go(AppRoutes.translationEditor(projectId, languageId));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ProjectLanguageDetails details,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final tokens = ctx.tokens;
        return TokenDialog(
          icon: FluentIcons.warning_24_regular,
          iconColor: tokens.err,
          title: t.translationEditor.dialogs.deleteLanguage.title,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.translationEditor.dialogs.deleteLanguage.message(
                  name: details.language.name,
                  count: details.translatedUnits,
                ),
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.textDim,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.warnBg,
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  border:
                      Border.all(color: tokens.warn.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      FluentIcons.info_24_regular,
                      size: 16,
                      color: tokens.warn,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.translationEditor.dialogs.deleteLanguage.cannotBeUndone,
                        style: tokens.fontBody.copyWith(
                          fontSize: 12,
                          color: tokens.warn,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            SmallTextButton(
              label: t.common.actions.cancel,
              onTap: () => Navigator.of(ctx).pop(false),
            ),
            SmallTextButton(
              label: t.common.actions.delete,
              icon: FluentIcons.delete_24_regular,
              filled: true,
              onTap: () => Navigator.of(ctx).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final result = await ref
        .read(shared_repo.projectLanguageRepositoryProvider)
        .delete(details.projectLanguage.id);
    if (!context.mounted) return;

    if (result.isErr) {
      FluentToast.error(context, 'Failed to delete language: ${result.error}');
      return;
    }

    // Riverpod 3 contract: `invalidate` + immediate `.future` read waits for a
    // fresh build; `openProjectEditor` below will not see the stale list.
    ref.invalidate(projectLanguagesProvider(projectId));
    // `refreshProject` currently swallows repository errors internally. Update
    // this call site if that contract ever changes.
    unawaited(ref
        .read(projectsWithDetailsProvider.notifier)
        .refreshProject(projectId));

    if (details.projectLanguage.languageId == currentLanguageId) {
      await openProjectEditor(context, ref, projectId);
    }
  }

  Future<void> _openAddDialog(
    BuildContext context,
    WidgetRef ref,
    List<ProjectLanguageDetails> current,
  ) async {
    final addedLanguageIds = await showDialog<List<String>>(
      context: context,
      builder: (_) => AddLanguageDialog(
        projectId: projectId,
        existingLanguageIds:
            current.map((l) => l.projectLanguage.languageId).toList(),
      ),
    );
    if (addedLanguageIds == null ||
        addedLanguageIds.isEmpty ||
        !context.mounted) {
      return;
    }
    // Switch immediately to the first newly added language so the editor
    // reflects the user's intent to start translating it.
    context.go(AppRoutes.translationEditor(projectId, addedLanguageIds.first));
  }
}

class _SwitcherChip extends StatelessWidget {
  const _SwitcherChip({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.accentBg,
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.globe_24_regular,
                  size: 16, color: tokens.accent),
              const SizedBox(width: 6),
              Text(label,
                  style: tokens.fontBody.copyWith(
                      fontSize: 13,
                      color: tokens.accent,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Icon(FluentIcons.chevron_down_24_regular,
                  size: 14, color: tokens.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageMenuItem extends StatelessWidget {
  const _LanguageMenuItem({
    required this.details,
    required this.isCurrent,
    required this.canDelete,
    required this.onSelect,
    required this.onDelete,
  });

  final ProjectLanguageDetails details;
  final bool isCurrent;
  final bool canDelete;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final pct = details.progressPercent.toInt();
    return SizedBox(
      width: 280,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onSelect,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      isCurrent
                          ? FluentIcons.checkmark_24_regular
                          : FluentIcons.translate_24_regular,
                      size: 16,
                      color: isCurrent ? tokens.accent : tokens.textDim,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(details.language.name,
                          style: tokens.fontBody
                              .copyWith(fontSize: 13, color: tokens.text)),
                    ),
                    Text('$pct%',
                        style: tokens.fontMono
                            .copyWith(fontSize: 12, color: tokens.textDim)),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            key: Key(
                'editor-language-delete-${details.projectLanguage.languageId}'),
            icon: Icon(FluentIcons.delete_24_regular,
                size: 16, color: canDelete ? tokens.err : tokens.textFaint),
            tooltip: canDelete
                ? t.translationEditor.languageSwitcher.deleteLanguage
                : t.translationEditor.languageSwitcher.cannotDeleteLast,
            onPressed: canDelete ? onDelete : null,
          ),
        ],
      ),
    );
  }
}

class _AddLanguageMenuItem extends StatelessWidget {
  const _AddLanguageMenuItem({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 280,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(FluentIcons.add_24_regular, size: 16, color: tokens.accent),
              const SizedBox(width: 8),
              Text(t.translationEditor.languageSwitcher.addLanguage,
                  style: tokens.fontBody.copyWith(
                      fontSize: 13,
                      color: tokens.accent,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
