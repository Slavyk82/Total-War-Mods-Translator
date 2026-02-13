import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// Dialog for entering a Steam Guard authentication code.
class SteamGuardDialog extends StatefulWidget {
  const SteamGuardDialog({super.key});

  /// Show the Steam Guard dialog and return the code or null if cancelled.
  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SteamGuardDialog(),
    );
  }

  @override
  State<SteamGuardDialog> createState() => _SteamGuardDialogState();
}

class _SteamGuardDialogState extends State<SteamGuardDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_controller.text.trim().toUpperCase());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(FluentIcons.shield_keyhole_24_regular,
              color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Steam Guard'),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the 5-character code from your Steam Mobile app.\n'
                'Open the Steam app → Steam Guard → use the rotating code shown on screen.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Note: approving the push notification is not enough — steamcmd requires the code.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'Steam Guard Code',
                  prefixIcon: Icon(FluentIcons.key_24_regular),
                  border: OutlineInputBorder(),
                  hintText: 'XXXXX',
                ),
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                  LengthLimitingTextInputFormatter(5),
                ],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Code is required';
                  }
                  if (value.trim().length < 5) {
                    return 'Code must be 5 characters';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(FluentIcons.checkmark_24_regular, size: 18),
          label: const Text('Verify'),
        ),
      ],
    );
  }
}
