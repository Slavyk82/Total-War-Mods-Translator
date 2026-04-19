import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
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
  String _targetLanguage = 'fr';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final importState = ref.watch(glossaryImportStateProvider);

    return TokenDialog(
      icon: FluentIcons.arrow_import_24_regular,
      title: 'Import Glossary (CSV)',
      width: 620,
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionLabel(tokens, 'File'),
            const SizedBox(height: 6),
            _buildFilePicker(tokens),
            const SizedBox(height: 14),
            _sectionLabel(tokens, 'Target Language'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _targetLanguage,
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.text,
              ),
              dropdownColor: tokens.panel,
              decoration: _inputDecoration(tokens, 'Target Language'),
              items: _languageCodes.map((lang) {
                return DropdownMenuItem(
                  value: lang,
                  child: Text(lang.toUpperCase()),
                );
              }).toList(),
              onChanged: (value) =>
                  setState(() => _targetLanguage = value ?? 'fr'),
            ),
            const SizedBox(height: 14),
            _sectionLabel(tokens, 'Options'),
            const SizedBox(height: 6),
            _OptionToggle(
              value: _skipDuplicates,
              onChanged: (v) => setState(() => _skipDuplicates = v),
              title: 'Skip duplicate entries',
              subtitle: 'Existing entries will not be overwritten',
            ),
            const SizedBox(height: 14),
            importState.when(
              data: (result) {
                if (result != null) {
                  return _buildSummaryBanner(
                    tokens,
                    icon: FluentIcons.checkmark_circle_24_regular,
                    title: 'Import Summary',
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
                    'Importing...',
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
          label: 'Close',
          onTap: () => Navigator.of(context).pop(),
        ),
        SmallTextButton(
          label: importState.isLoading ? 'Importing...' : 'Import',
          icon: FluentIcons.arrow_import_24_regular,
          filled: true,
          onTap: importState.isLoading ? null : _import,
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
                  _selectedFilePath ?? 'Click to select file...',
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

  InputDecoration _inputDecoration(TwmtThemeTokens tokens, String label) {
    return InputDecoration(
      labelText: label,
      labelStyle:
          tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
      floatingLabelStyle:
          tokens.fontBody.copyWith(fontSize: 12, color: tokens.accent),
      filled: true,
      fillColor: tokens.panel2,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.accent),
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
        FluentToast.error(context, 'Please select a file to import');
      }
      return;
    }

    await ref.read(glossaryImportStateProvider.notifier).importCsv(
          glossaryId: widget.glossaryId,
          filePath: _selectedFilePath!,
          targetLanguageCode: _targetLanguage,
          skipDuplicates: _skipDuplicates,
        );
  }

  static const List<String> _languageCodes = [
    'en',
    'fr',
    'de',
    'es',
    'it',
    'pt',
    'ru',
    'zh',
    'ja',
    'ko',
  ];
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
