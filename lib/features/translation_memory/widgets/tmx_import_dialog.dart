import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../providers/tm_providers.dart';

/// Token-themed popup for importing translation-memory TMX files.
class TmxImportDialog extends ConsumerStatefulWidget {
  const TmxImportDialog({super.key});

  @override
  ConsumerState<TmxImportDialog> createState() => _TmxImportDialogState();
}

class _TmxImportDialogState extends ConsumerState<TmxImportDialog> {
  String? _selectedFilePath;
  bool _overwriteExisting = false;
  bool _validateEntries = true;
  int _processedEntries = 0;
  int _totalEntries = 0;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final importState = ref.watch(tmImportStateProvider);

    return TokenDialog(
      icon: FluentIcons.arrow_import_24_regular,
      title: t.translationMemory.dialogs.importTitle,
      width: 620,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFilePicker(tokens),
          if (_selectedFilePath != null) ...[
            const SizedBox(height: 18),
            _buildFilePreview(tokens),
          ],
          const SizedBox(height: 18),
          _buildOptions(tokens),
          const SizedBox(height: 18),
          importState.when(
            data: (result) {
              if (result != null) {
                return _buildImportResult(tokens, result);
              }
              return const SizedBox.shrink();
            },
            loading: () => _buildProgress(tokens),
            error: (error, stack) =>
                _buildError(tokens, error.toString()),
          ),
        ],
      ),
      actions: [
        SmallTextButton(
          label: t.common.actions.cancel,
          onTap: importState.isLoading
              ? null
              : () {
                  ref.read(tmImportStateProvider.notifier).reset();
                  Navigator.of(context).pop();
                },
        ),
        SmallTextButton(
          label: t.translationMemory.actions.import,
          icon: FluentIcons.arrow_import_24_regular,
          filled: true,
          onTap: _selectedFilePath == null || importState.isLoading
              ? null
              : _startImport,
        ),
      ],
    );
  }

  Widget _buildFilePicker(TwmtThemeTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.translationMemory.labels.selectedFile,
          style: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        MouseRegion(
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
                  Icon(
                    FluentIcons.document_24_regular,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedFilePath ?? t.translationMemory.hints.clickToSelectTmxFile,
                      style: tokens.fontBody.copyWith(
                        fontSize: 13,
                        color: _selectedFilePath != null
                            ? tokens.text
                            : tokens.textFaint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    FluentIcons.folder_open_24_regular,
                    size: 18,
                    color: tokens.textDim,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilePreview(TwmtThemeTokens tokens) {
    final file = File(_selectedFilePath!);
    final sizeInBytes = file.lengthSync();
    final sizeInKB = (sizeInBytes / 1024).toStringAsFixed(1);
    final fileName = file.path.split(Platform.pathSeparator).last;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.panel2,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.translationMemory.labels.selectedFile,
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: tokens.textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                FluentIcons.document_24_filled,
                size: 16,
                color: tokens.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fileName,
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: tokens.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            t.translationMemory.messages.sizeKb(size: sizeInKB),
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: tokens.textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptions(TwmtThemeTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.translationMemory.labels.importOptions,
          style: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        _OptionToggle(
          value: _overwriteExisting,
          onChanged: (v) => setState(() => _overwriteExisting = v),
          title: t.translationMemory.options.overwriteExisting,
          subtitle: t.translationMemory.options.overwriteExistingHint,
        ),
        const SizedBox(height: 6),
        _OptionToggle(
          value: _validateEntries,
          onChanged: (v) => setState(() => _validateEntries = v),
          title: t.translationMemory.options.validateEntries,
          subtitle: t.translationMemory.options.validateEntriesHint,
        ),
      ],
    );
  }

  Widget _buildProgress(TwmtThemeTokens tokens) {
    final progress =
        _totalEntries > 0 ? _processedEntries / _totalEntries : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.translationMemory.actions.importing,
          style: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: tokens.panel2,
            valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
          ),
        ),
        if (_totalEntries > 0) ...[
          const SizedBox(height: 6),
          Text(
            t.translationMemory.messages.processedOf(processed: _processedEntries, total: _totalEntries),
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: tokens.textDim,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImportResult(TwmtThemeTokens tokens, TmImportResult result) {
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
              Icon(
                FluentIcons.checkmark_circle_24_filled,
                color: tokens.ok,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                t.translationMemory.messages.importComplete,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.ok,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _resultRow(tokens, t.translationMemory.importResult.totalEntries, result.totalEntries.toString()),
          _resultRow(tokens, t.translationMemory.importResult.imported, result.importedEntries.toString()),
          if (result.skippedEntries > 0)
            _resultRow(tokens, t.translationMemory.importResult.skippedDuplicates,
                result.skippedEntries.toString()),
          if (result.failedEntries > 0)
            _resultRow(tokens, t.translationMemory.importResult.failedValidation,
                result.failedEntries.toString()),
        ],
      ),
    );
  }

  Widget _resultRow(TwmtThemeTokens tokens, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: tokens.textDim,
            ),
          ),
          Text(
            value,
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: tokens.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(TwmtThemeTokens tokens, String error) {
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
              error,
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
      allowedExtensions: ['tmx'],
      dialogTitle: 'Select TMX File',
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFilePath = result.files.single.path;
      });
    }
  }

  Future<void> _startImport() async {
    if (_selectedFilePath == null) return;

    await ref.read(tmImportStateProvider.notifier).importFromTmx(
          filePath: _selectedFilePath!,
          overwriteExisting: _overwriteExisting,
          onProgress: (processed, total) {
            setState(() {
              _processedEntries = processed;
              _totalEntries = total;
            });
          },
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
