import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// Token-themed popup for selecting which languages to include in a pack
/// export. Returns `List<String>` of selected language codes on confirm, or
/// `null` on cancel.
class PackLanguageDialog extends StatefulWidget {
  final List<String> availableLanguages;

  const PackLanguageDialog({super.key, required this.availableLanguages});

  static Future<List<String>?> show(
    BuildContext context, {
    required List<String> availableLanguages,
  }) {
    return showDialog<List<String>>(
      context: context,
      builder: (_) =>
          PackLanguageDialog(availableLanguages: availableLanguages),
    );
  }

  @override
  State<PackLanguageDialog> createState() => _PackLanguageDialogState();
}

class _PackLanguageDialogState extends State<PackLanguageDialog> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.availableLanguages.toSet();
  }

  @override
  Widget build(BuildContext context) {
    return TokenDialog(
      icon: FluentIcons.globe_24_regular,
      title: 'Select languages',
      width: 360,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final lang in widget.availableLanguages)
            _LanguageCheckbox(
              label: lang,
              value: _selected.contains(lang),
              onChanged: (checked) {
                setState(() {
                  if (checked) {
                    _selected.add(lang);
                  } else {
                    _selected.remove(lang);
                  }
                });
              },
            ),
        ],
      ),
      actions: [
        SmallTextButton(
          label: 'Cancel',
          onTap: () => Navigator.of(context).pop(null),
        ),
        SmallTextButton(
          label: 'Generate',
          icon: FluentIcons.checkmark_24_regular,
          filled: true,
          onTap: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected.toList()),
        ),
      ],
    );
  }
}

class _LanguageCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _LanguageCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                value
                    ? FluentIcons.checkbox_checked_24_filled
                    : FluentIcons.checkbox_unchecked_24_regular,
                size: 18,
                color: value ? tokens.accent : tokens.textFaint,
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
