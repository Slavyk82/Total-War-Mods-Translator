import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../../../providers/shared/repository_providers.dart';
import '../../../providers/shared/service_providers.dart';
import '../providers/glossary_providers.dart';

/// Token-themed popup for importing a glossary from a CSV file.
class GlossaryImportDialog extends ConsumerStatefulWidget {
  final String glossaryId;

  const GlossaryImportDialog({
    super.key,
    required this.glossaryId,
  });

  @override
  ConsumerState<GlossaryImportDialog> createState() =>
      _GlossaryImportDialogState();
}

class _GlossaryImportDialogState extends ConsumerState<GlossaryImportDialog> {
  String? _selectedFilePath;
  bool _skipDuplicates = true;

  /// The glossary's real target language code, resolved from its
  /// target_language_id. Imported entries MUST use this code so they stay
  /// scoped to the glossary's (game, language) pair and are not orphaned.
  String? _resolvedLanguageCode;
  bool _resolvingLanguage = true;
  String? _languageError;

  @override
  void initState() {
    super.initState();
    _resolveGlossaryLanguage();
  }

  /// Resolve the glossary's target language code from its target_language_id.
  Future<void> _resolveGlossaryLanguage() async {
    try {
      final service = ref.read(glossaryServiceProvider);
      final glossaryResult = await service.getGlossaryById(widget.glossaryId);
      if (glossaryResult.isErr) {
        throw Exception(glossaryResult.error.message);
      }
      final glossary = glossaryResult.unwrap();

      final langRepo = ref.read(languageRepositoryProvider);
      final langResult = await langRepo.getById(glossary.targetLanguageId);
      if (langResult.isErr) {
        throw Exception(langResult.error.message);
      }
      final code = langResult.unwrap().code;

      if (mounted) {
        setState(() {
          _resolvedLanguageCode = code;
          _resolvingLanguage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _languageError = '$e';
          _resolvingLanguage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final importState = ref.watch(glossaryImportStateProvider);

    return TokenDialog(
      icon: FluentIcons.arrow_import_24_regular,
      title: t.glossary.dialogs.importTitle,
      width: 620,
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionLabel(tokens, t.glossary.labels.file),
            const SizedBox(height: 6),
            _buildFilePicker(tokens),
            const SizedBox(height: 14),
            _sectionLabel(tokens, t.glossary.labels.targetLanguage),
            const SizedBox(height: 6),
            _buildResolvedLanguage(tokens),
            const SizedBox(height: 14),
            _sectionLabel(tokens, t.glossary.labels.options),
            const SizedBox(height: 6),
            _OptionToggle(
              value: _skipDuplicates,
              onChanged: (v) => setState(() => _skipDuplicates = v),
              title: t.glossary.hints.skipDuplicates,
              subtitle: t.glossary.hints.skipDuplicatesHint,
            ),
            const SizedBox(height: 14),
            importState.when(
              data: (result) {
                if (result != null) {
                  return _buildSummaryBanner(
                    tokens,
                    icon: FluentIcons.checkmark_circle_24_regular,
                    title: t.glossary.labels.importSummary,
                    message: result.summary,
                  );
                }
                return const SizedBox.shrink();
              },
              loading: () => Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      backgroundColor: tokens.panel2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(tokens.accent),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t.glossary.actions.importing,
                    style: tokens.fontBody.copyWith(
                      fontSize: 12.5,
                      color: tokens.textDim,
                    ),
                  ),
                ],
              ),
              error: (error, _) => _buildErrorBanner(tokens, '$error'),
            ),
          ],
        ),
      ),
      actions: [
        SmallTextButton(
          label: t.common.actions.close,
          onTap: () => Navigator.of(context).pop(),
        ),
        SmallTextButton(
          label: importState.isLoading ? t.glossary.actions.importing : t.glossary.actions.import,
          icon: FluentIcons.arrow_import_24_regular,
          filled: true,
          onTap: (importState.isLoading ||
                  _resolvingLanguage ||
                  _resolvedLanguageCode == null)
              ? null
              : _import,
        ),
      ],
    );
  }

  Widget _sectionLabel(TwmtThemeTokens tokens, String text) {
    return Text(
      text,
      style: tokens.fontBody.copyWith(
        fontSize: 13,
        color: tokens.text,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildFilePicker(TwmtThemeTokens tokens) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _pickFile,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tokens.panel2,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Row(
            children: [
              Icon(FluentIcons.folder_open_24_regular, color: tokens.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedFilePath ?? t.glossary.hints.clickToSelectFile,
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: _selectedFilePath == null
                        ? tokens.textFaint
                        : tokens.text,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Read-only display of the glossary's resolved target language. The user
  /// cannot change it: imported entries are always scoped to the glossary's
  /// own (game, language) pair.
  Widget _buildResolvedLanguage(TwmtThemeTokens tokens) {
    final String display;
    if (_resolvingLanguage) {
      display = '...';
    } else if (_languageError != null) {
      display = '-';
    } else {
      display = (_resolvedLanguageCode ?? '').toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.panel2,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Row(
        children: [
          Icon(FluentIcons.local_language_24_regular,
              color: tokens.accent, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              display,
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBanner(
    TwmtThemeTokens tokens, {
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.okBg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.ok.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: tokens.ok, size: 18),
              const SizedBox(width: 10),
              Text(
                title,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.ok,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: tokens.fontBody.copyWith(
              fontSize: 12.5,
              color: tokens.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(TwmtThemeTokens tokens, String error) {
    return Container(
      padding: const EdgeInsets.all(14),
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
              'Error: $error',
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

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFilePath = result.files.single.path;
      });
    }
  }

  Future<void> _import() async {
    if (_selectedFilePath == null) {
      if (mounted) {
        FluentToast.error(context, t.glossary.messages.pleaseSelectFile);
      }
      return;
    }

    // The target language is the glossary's own resolved language, never a
    // free user choice — this keeps imported entries from being orphaned.
    final code = _resolvedLanguageCode;
    if (code == null || code.isEmpty) {
      if (mounted) {
        FluentToast.error(
          context,
          _languageError ?? t.glossary.actions.importing,
        );
      }
      return;
    }

    await ref.read(glossaryImportStateProvider.notifier).importCsv(
          glossaryId: widget.glossaryId,
          filePath: _selectedFilePath!,
          targetLanguageCode: code,
          skipDuplicates: _skipDuplicates,
        );
  }
}

class _OptionToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String subtitle;

  const _OptionToggle({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                value
                    ? FluentIcons.checkbox_checked_24_filled
                    : FluentIcons.checkbox_unchecked_24_regular,
                size: 18,
                color: value ? tokens.accent : tokens.textFaint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: tokens.fontBody.copyWith(
                        fontSize: 13,
                        color: tokens.text,
                      ),
                    ),
                    Text(
                      subtitle,
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
