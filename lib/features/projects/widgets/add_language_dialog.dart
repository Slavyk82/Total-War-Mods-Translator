import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:uuid/uuid.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../../../models/domain/language.dart';
import '../../../models/domain/project_language.dart';
import '../../../models/domain/translation_version.dart';
import '../../../services/glossary/glossary_auto_provisioning_service.dart';
import '../../../services/service_locator.dart';
import '../../../services/shared/i_logging_service.dart';
import '../providers/projects_screen_providers.dart';
import '../providers/project_detail_providers.dart';

/// Token-themed popup for adding target languages to a project.
class AddLanguageDialog extends ConsumerStatefulWidget {
  final String projectId;
  final List<String> existingLanguageIds;

  const AddLanguageDialog({
    super.key,
    required this.projectId,
    required this.existingLanguageIds,
  });

  @override
  ConsumerState<AddLanguageDialog> createState() => _AddLanguageDialogState();
}

class _AddLanguageDialogState extends ConsumerState<AddLanguageDialog> {
  final Set<String> _selectedLanguageIds = {};
  bool _isLoading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final languagesAsync = ref.watch(allLanguagesProvider);

    return TokenDialog(
      icon: FluentIcons.add_circle_24_regular,
      title: 'Add Target Languages',
      width: 540,
      body: SizedBox(
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              _buildErrorBanner(tokens),
              const SizedBox(height: 14),
            ],
            Text(
              'Select languages to add to this project',
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.textDim,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: languagesAsync.when(
                data: (languages) => _buildLanguagesList(languages, tokens),
                loading: () => Center(
                  child: CircularProgressIndicator(color: tokens.accent),
                ),
                error: (err, _) => _buildErrorState(tokens, err),
              ),
            ),
          ],
        ),
      ),
      actions: [
        SmallTextButton(
          label: 'Cancel',
          onTap: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
        SmallTextButton(
          label: _isLoading ? 'Adding...' : 'Add Languages',
          icon: FluentIcons.checkmark_24_regular,
          filled: true,
          onTap: _selectedLanguageIds.isEmpty || _isLoading
              ? null
              : () => _addLanguages(context),
        ),
      ],
    );
  }

  Widget _buildLanguagesList(
    List<Language> allLanguages,
    TwmtThemeTokens tokens,
  ) {
    final availableLanguages = allLanguages
        .where((lang) =>
            lang.isActive && !widget.existingLanguageIds.contains(lang.id))
        .toList();

    if (availableLanguages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.checkmark_circle_24_regular,
              size: 48,
              color: tokens.textFaint,
            ),
            const SizedBox(height: 12),
            Text(
              'All languages already added',
              style: tokens.fontBody.copyWith(
                fontSize: 14,
                color: tokens.textDim,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: availableLanguages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final language = availableLanguages[index];
        final isSelected = _selectedLanguageIds.contains(language.id);
        return _LanguageOption(
          language: language,
          selected: isSelected,
          onChanged: (value) {
            setState(() {
              if (value) {
                _selectedLanguageIds.add(language.id);
              } else {
                _selectedLanguageIds.remove(language.id);
              }
            });
          },
        );
      },
    );
  }

  Widget _buildErrorBanner(TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.errBg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.err.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            color: tokens.err,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: tokens.fontBody.copyWith(
                fontSize: 12.5,
                color: tokens.err,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(TwmtThemeTokens tokens, Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            size: 48,
            color: tokens.err,
          ),
          const SizedBox(height: 12),
          Text(
            'Error loading languages',
            style: tokens.fontBody.copyWith(
              fontSize: 14,
              color: tokens.err,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            error.toString(),
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: tokens.textDim,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _addLanguages(BuildContext context) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final projectLangRepo = ref.read(projectLanguageRepositoryProvider);
      final translationUnitRepo = ref.read(translationUnitRepositoryProvider);
      final translationVersionRepo =
          ref.read(translationVersionRepositoryProvider);
      final projectRepo = ref.read(projectRepositoryProvider);
      final gameInstallationRepo = ref.read(gameInstallationRepositoryProvider);
      const uuid = Uuid();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final unitsResult =
          await translationUnitRepo.getByProject(widget.projectId);

      if (unitsResult.isErr) {
        throw Exception(
            'Failed to load translation units: ${unitsResult.error}');
      }

      final translationUnits = unitsResult.unwrap();

      final languageIdsList = _selectedLanguageIds.toList();

      for (final languageId in languageIdsList) {
        final projectLanguageId = uuid.v4();
        final projectLanguage = ProjectLanguage(
          id: projectLanguageId,
          projectId: widget.projectId,
          languageId: languageId,
          progressPercent: 0.0,
          createdAt: now,
          updatedAt: now,
        );

        final result = await projectLangRepo.insert(projectLanguage);

        if (result.isErr) {
          throw Exception('Failed to add language: ${result.error}');
        }

        final versionsToInsert = <TranslationVersion>[];
        for (final unit in translationUnits) {
          versionsToInsert.add(TranslationVersion(
            id: uuid.v4(),
            unitId: unit.id,
            projectLanguageId: projectLanguageId,
            translatedText: null,
            isManuallyEdited: false,
            status: TranslationVersionStatus.pending,
            createdAt: now,
            updatedAt: now,
          ));
        }

        final versionResult =
            await translationVersionRepo.insertBatch(versionsToInsert);

        if (versionResult.isErr) {
          throw Exception(
              'Failed to create translation versions: ${versionResult.error}');
        }
      }

      // Best-effort: provision an empty glossary per (gameCode, languageId)
      // so the new language automatically has a glossary available. Never
      // block the add-language flow on provisioning failures.
      try {
        final projectResult = await projectRepo.getById(widget.projectId);
        if (projectResult.isOk) {
          final project = projectResult.value;
          final gameResult =
              await gameInstallationRepo.getById(project.gameInstallationId);
          if (gameResult.isOk) {
            final gameCode = gameResult.value.gameCode;
            final provisioner =
                ServiceLocator.get<GlossaryAutoProvisioningService>();
            for (final languageId in languageIdsList) {
              await provisioner.provisionForProjectLanguage(
                gameCode: gameCode,
                targetLanguageId: languageId,
              );
            }
          } else {
            ServiceLocator.get<ILoggingService>().warning(
              'Glossary auto-provision skipped: game installation lookup failed',
              {
                'projectId': widget.projectId,
                'gameInstallationId': project.gameInstallationId,
                'error': gameResult.error.toString(),
              },
            );
          }
        } else {
          ServiceLocator.get<ILoggingService>().warning(
            'Glossary auto-provision skipped: project lookup failed',
            {
              'projectId': widget.projectId,
              'error': projectResult.error.toString(),
            },
          );
        }
      } catch (e) {
        ServiceLocator.get<ILoggingService>().warning(
          'Glossary auto-provision for project languages failed',
          {'projectId': widget.projectId, 'error': e.toString()},
        );
      }

      if (!context.mounted) return;

      ref.invalidate(projectLanguagesProvider(widget.projectId));
      unawaited(ref
          .read(projectsWithDetailsProvider.notifier)
          .refreshProject(widget.projectId));
      ref.read(translationStatsVersionProvider.notifier).increment();

      FluentToast.success(
        context,
        'Added ${languageIdsList.length} language'
        '${languageIdsList.length > 1 ? 's' : ''} with '
        '${translationUnits.length} translation units each',
      );

      Navigator.of(context).pop(languageIdsList);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to add languages: $e';
        _isLoading = false;
      });
    }
  }
}

class _LanguageOption extends StatelessWidget {
  final Language language;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const _LanguageOption({
    required this.language,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!selected),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? tokens.accentBg : tokens.panel2,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(
              color: selected ? tokens.accent : tokens.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? FluentIcons.checkbox_checked_24_filled
                    : FluentIcons.checkbox_unchecked_24_regular,
                size: 18,
                color: selected ? tokens.accent : tokens.textFaint,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      language.displayName,
                      style: tokens.fontBody.copyWith(
                        fontSize: 13,
                        color: tokens.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Code: ${language.code.toUpperCase()}',
                      style: tokens.fontBody.copyWith(
                        fontSize: 11.5,
                        color: tokens.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
