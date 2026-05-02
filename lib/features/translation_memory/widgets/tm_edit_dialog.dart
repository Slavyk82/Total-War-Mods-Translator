import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/relative_date.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/wizard/labeled_field.dart';
import 'package:twmt/widgets/wizard/token_text_field.dart';
import '../providers/tm_providers.dart';

/// Token-themed dialog for editing the target text of a TM entry.
///
/// Source text is read-only — the corresponding source hash and
/// deduplication key cannot change without invalidating downstream
/// matching, so editing is intentionally scoped to the translation only.
class TmEditDialog extends ConsumerStatefulWidget {
  final TranslationMemoryEntry entry;

  const TmEditDialog({super.key, required this.entry});

  @override
  ConsumerState<TmEditDialog> createState() => _TmEditDialogState();
}

class _TmEditDialogState extends ConsumerState<TmEditDialog> {
  late final TextEditingController _controller;
  late final ScrollController _sourceScrollController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.entry.translatedText);
    _controller.addListener(_onTextChanged);
    _sourceScrollController = ScrollController();
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _sourceScrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    // Re-evaluate the Save button enabled state on every keystroke.
    setState(() {});
  }

  bool get _canSave {
    final trimmed = _controller.text.trim();
    return !_saving &&
        trimmed.isNotEmpty &&
        trimmed != widget.entry.translatedText;
  }

  Future<void> _handleSave() async {
    final newText = _controller.text.trim();
    if (newText.isEmpty || newText == widget.entry.translatedText) return;

    setState(() => _saving = true);

    final success = await ref
        .read(tmUpdateStateProvider.notifier)
        .updateTargetText(entryId: widget.entry.id, newTargetText: newText);

    if (!mounted) return;

    if (success) {
      // Pop with the new target text so the caller can patch the grid
      // optimistically without waiting for the provider refetch.
      Navigator.of(context).pop(newText);
      FluentToast.success(
        context,
        t.translationMemory.messages.tmEntryEditedSuccess,
      );
    } else {
      setState(() => _saving = false);
      FluentToast.error(
        context,
        t.translationMemory.messages.failedToEditTmEntry,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return TokenDialog(
      icon: FluentIcons.edit_24_regular,
      title: t.translationMemory.dialogs.editTmTitle,
      width: 720,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSourceSection(tokens),
          const SizedBox(height: 16),
          LabeledField(
            label: t.translationMemory.labels.targetText,
            child: TokenTextField(
              controller: _controller,
              hint: '',
              enabled: !_saving,
              minLines: 4,
              maxLines: 10,
              autofocus: true,
            ),
          ),
          const SizedBox(height: 16),
          _buildMetadataRow(tokens),
        ],
      ),
      actions: [
        SmallTextButton(
          label: t.common.actions.cancel,
          onTap: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        SmallTextButton(
          label: t.common.actions.save,
          icon: FluentIcons.checkmark_24_regular,
          filled: true,
          onTap: _canSave ? _handleSave : null,
        ),
      ],
    );
  }

  Widget _buildSourceSection(TwmtThemeTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.translationMemory.labels.sourceText,
          style: tokens.fontBody.copyWith(
            fontSize: 11,
            color: tokens.textDim,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 150),
          decoration: BoxDecoration(
            color: tokens.panel2,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: Scrollbar(
            controller: _sourceScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _sourceScrollController,
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                widget.entry.sourceText,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.text,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataRow(TwmtThemeTokens tokens) {
    final created = _formatTimestamp(widget.entry.createdAt);
    final lastUsed = _formatTimestamp(widget.entry.lastUsedAt);

    Widget item(String label, String value) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: tokens.fontMono.copyWith(
                fontSize: 10,
                color: tokens.textDim,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.textMid,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        item(
          t.translationMemory.labels.usageCount,
          widget.entry.usageCount.toString(),
        ),
        item(t.translationMemory.labels.lastUsed, lastUsed),
        item(t.translationMemory.labels.created, created),
      ],
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return formatAbsoluteDate(date) ?? '';
  }
}
