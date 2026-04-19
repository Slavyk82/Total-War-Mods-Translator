import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../providers/glossary_providers.dart';

/// Token-themed popup for exporting a glossary to a CSV file.
class GlossaryExportDialog extends ConsumerStatefulWidget {
  final String glossaryId;

  const GlossaryExportDialog({
    super.key,
    required this.glossaryId,
  });

  @override
  ConsumerState<GlossaryExportDialog> createState() =>
      _GlossaryExportDialogState();
}

class _GlossaryExportDialogState extends ConsumerState<GlossaryExportDialog> {
  String? _selectedFilePath;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final exportState = ref.watch(glossaryExportStateProvider);

    return TokenDialog(
      icon: FluentIcons.arrow_export_24_regular,
      title: 'Export Glossary (CSV)',
      width: 620,
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Output File',
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
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
                      Icon(FluentIcons.save_24_regular, color: tokens.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedFilePath ??
                              'Click to select output file...',
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
            ),
            const SizedBox(height: 14),
            exportState.when(
              data: (result) {
                if (result != null) {
                  return _buildSummaryBanner(
                    tokens,
                    title: 'Export Summary',
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
                    'Exporting...',
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
          label: exportState.isLoading ? 'Exporting...' : 'Export',
          icon: FluentIcons.arrow_export_24_regular,
          filled: true,
          onTap: exportState.isLoading ? null : _export,
        ),
      ],
    );
  }

  Widget _buildSummaryBanner(
    TwmtThemeTokens tokens, {
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
              Icon(
                FluentIcons.checkmark_circle_24_regular,
                color: tokens.ok,
                size: 18,
              ),
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
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Glossary Export',
      fileName: 'glossary.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null) {
      setState(() {
        _selectedFilePath = result;
      });
    }
  }

  Future<void> _export() async {
    if (_selectedFilePath == null) {
      if (mounted) {
        FluentToast.error(context, 'Please select an output file');
      }
      return;
    }

    await ref.read(glossaryExportStateProvider.notifier).exportCsv(
          glossaryId: widget.glossaryId,
          filePath: _selectedFilePath!,
        );
  }
}
