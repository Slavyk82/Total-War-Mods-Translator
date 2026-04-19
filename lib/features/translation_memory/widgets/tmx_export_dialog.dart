import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../providers/tm_providers.dart';

/// Token-themed popup for exporting TM entries to a TMX file.
class TmxExportDialog extends ConsumerStatefulWidget {
  const TmxExportDialog({super.key});

  @override
  ConsumerState<TmxExportDialog> createState() => _TmxExportDialogState();
}

class _TmxExportDialogState extends ConsumerState<TmxExportDialog> {
  String? _outputPath;
  String? _targetLanguage;
  ExportScope _exportScope = ExportScope.all;
  bool _includeMetadata = true;
  bool _includeStats = true;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final exportState = ref.watch(tmExportStateProvider);

    return TokenDialog(
      icon: FluentIcons.arrow_export_24_regular,
      title: 'Export Translation Memory (TMX)',
      width: 620,
      body: SizedBox(
        height: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(tokens, 'Filters'),
              const SizedBox(height: 10),
              _buildTargetLanguageDropdown(tokens),
              const SizedBox(height: 18),
              _sectionTitle(tokens, 'What to export'),
              const SizedBox(height: 8),
              _ScopeRadio(
                value: ExportScope.all,
                groupValue: _exportScope,
                label: 'All entries (matching filters)',
                onChanged: (v) => setState(() => _exportScope = v),
              ),
              _ScopeRadio(
                value: ExportScope.frequentlyUsed,
                groupValue: _exportScope,
                label: 'Frequently used only (>5 times)',
                onChanged: (v) => setState(() => _exportScope = v),
              ),
              const SizedBox(height: 18),
              _sectionTitle(tokens, 'Output File'),
              const SizedBox(height: 8),
              _buildOutputPathPicker(tokens),
              const SizedBox(height: 18),
              _sectionTitle(tokens, 'Format Options'),
              const SizedBox(height: 10),
              _OptionToggle(
                value: _includeMetadata,
                onChanged: (v) => setState(() => _includeMetadata = v),
                title: 'Include metadata',
                subtitle: 'Add quality scores, usage counts, etc.',
              ),
              const SizedBox(height: 6),
              _OptionToggle(
                value: _includeStats,
                onChanged: (v) => setState(() => _includeStats = v),
                title: 'Include statistics',
                subtitle: 'Add export summary and stats to file header',
              ),
              const SizedBox(height: 18),
              exportState.when(
                data: (result) {
                  if (result != null) {
                    return _buildResult(tokens, result);
                  }
                  return const SizedBox.shrink();
                },
                loading: () => _buildProgress(tokens),
                error: (error, _) => _buildError(tokens, error.toString()),
              ),
            ],
          ),
        ),
      ),
      actions: [
        SmallTextButton(
          label: 'Cancel',
          onTap: exportState.isLoading
              ? null
              : () {
                  ref.read(tmExportStateProvider.notifier).reset();
                  Navigator.of(context).pop();
                },
        ),
        SmallTextButton(
          label: 'Export',
          icon: FluentIcons.arrow_export_24_regular,
          filled: true,
          onTap: _outputPath == null || exportState.isLoading
              ? null
              : _startExport,
        ),
      ],
    );
  }

  Widget _sectionTitle(TwmtThemeTokens tokens, String title) {
    return Text(
      title,
      style: tokens.fontBody.copyWith(
        fontSize: 13,
        color: tokens.text,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildTargetLanguageDropdown(TwmtThemeTokens tokens) {
    const items = ['EN', 'FR', 'DE', 'ZH', 'ES'];
    return DropdownButtonFormField<String>(
      initialValue: _targetLanguage,
      style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.text),
      dropdownColor: tokens.panel,
      decoration: InputDecoration(
        labelText: 'Target Language',
        labelStyle: tokens.fontBody.copyWith(
          fontSize: 12,
          color: tokens.textDim,
        ),
        filled: true,
        fillColor: tokens.panel2,
        hintText: 'All',
        hintStyle: tokens.fontBody.copyWith(
          fontSize: 13,
          color: tokens.textFaint,
        ),
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
      ),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text('All')),
        ...items.map(
          (e) => DropdownMenuItem<String>(value: e, child: Text(e)),
        ),
      ],
      onChanged: (value) => setState(() => _targetLanguage = value),
    );
  }

  Widget _buildOutputPathPicker(TwmtThemeTokens tokens) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _pickOutputPath,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tokens.panel2,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Row(
            children: [
              Icon(FluentIcons.save_24_regular, color: tokens.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _outputPath ?? 'Click to select save location',
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color:
                        _outputPath != null ? tokens.text : tokens.textFaint,
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
    );
  }

  Widget _buildProgress(TwmtThemeTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Exporting...',
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
            minHeight: 8,
            backgroundColor: tokens.panel2,
            valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
          ),
        ),
      ],
    );
  }

  Widget _buildResult(TwmtThemeTokens tokens, TmExportResult result) {
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
                'Export Complete',
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.ok,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Exported ${result.entriesExported} entries',
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            result.filePath,
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: tokens.textDim,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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

  Future<void> _pickOutputPath() async {
    final result = await FilePicker.platform.saveFile(
      type: FileType.custom,
      allowedExtensions: ['tmx'],
      dialogTitle: 'Save TMX File',
      fileName: 'translation_memory_export.tmx',
    );

    if (result != null) {
      setState(() {
        _outputPath = result;
      });
    }
  }

  Future<void> _startExport() async {
    if (_outputPath == null) return;

    await ref.read(tmExportStateProvider.notifier).exportToTmx(
          outputPath: _outputPath!,
          targetLanguageCode: _targetLanguage,
        );
  }
}

class _ScopeRadio extends StatelessWidget {
  final ExportScope value;
  final ExportScope groupValue;
  final String label;
  final ValueChanged<ExportScope> onChanged;

  const _ScopeRadio({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final selected = value == groupValue;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                selected
                    ? FluentIcons.radio_button_24_filled
                    : FluentIcons.radio_button_24_regular,
                size: 18,
                color: selected ? tokens.accent : tokens.textFaint,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.text,
                ),
              ),
            ],
          ),
        ),
      ),
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

enum ExportScope {
  all,
  frequentlyUsed,
}
