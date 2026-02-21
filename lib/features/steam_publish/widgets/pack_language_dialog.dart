import 'package:flutter/material.dart';

/// Dialog for selecting which languages to include in a pack export.
///
/// Returns `List<String>` of selected language codes on confirm, or `null` on cancel.
class PackLanguageDialog extends StatefulWidget {
  final List<String> availableLanguages;

  const PackLanguageDialog({super.key, required this.availableLanguages});

  /// Show the dialog and return selected languages, or null if cancelled.
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
    return AlertDialog(
      title: const Text('Select languages'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final lang in widget.availableLanguages)
              CheckboxListTile(
                title: Text(lang),
                value: _selected.contains(lang),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _selected.add(lang);
                    } else {
                      _selected.remove(lang);
                    }
                  });
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected.toList()),
          child: const Text('Generate'),
        ),
      ],
    );
  }
}
