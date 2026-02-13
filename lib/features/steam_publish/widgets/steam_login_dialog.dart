import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../settings/providers/settings_providers.dart';

const _secureStorage = FlutterSecureStorage(
  wOptions: WindowsOptions(useBackwardCompatibility: false),
);

/// Dialog for entering Steam credentials (username + password).
class SteamLoginDialog extends StatefulWidget {
  const SteamLoginDialog({super.key});

  /// Show the login dialog and return (username, password, steamGuardCode?) or null if cancelled.
  static Future<(String, String, String?)?> show(BuildContext context) {
    return showDialog<(String, String, String?)>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SteamLoginDialog(),
    );
  }

  @override
  State<SteamLoginDialog> createState() => _SteamLoginDialogState();
}

class _SteamLoginDialogState extends State<SteamLoginDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _steamGuardController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _rememberCredentials = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final username =
        await _secureStorage.read(key: SettingsKeys.steamUsername);
    final password =
        await _secureStorage.read(key: SettingsKeys.steamPassword);

    if (!mounted) return;

    if (username != null && username.isNotEmpty) {
      _usernameController.text = username;
      _passwordController.text = password ?? '';
      _rememberCredentials = true;
    }

    setState(() => _loading = false);
  }

  Future<void> _saveOrClearCredentials() async {
    if (_rememberCredentials) {
      await _secureStorage.write(
        key: SettingsKeys.steamUsername,
        value: _usernameController.text.trim(),
      );
      await _secureStorage.write(
        key: SettingsKeys.steamPassword,
        value: _passwordController.text,
      );
    } else {
      await _secureStorage.delete(key: SettingsKeys.steamUsername);
      await _secureStorage.delete(key: SettingsKeys.steamPassword);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _steamGuardController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      _saveOrClearCredentials();
      final code = _steamGuardController.text.trim().toUpperCase();
      Navigator.of(context).pop((
        _usernameController.text.trim(),
        _passwordController.text,
        code.length == 5 ? code : null,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(FluentIcons.person_24_regular, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Steam Login'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            : Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter your Steam credentials to publish to the Workshop.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(FluentIcons.person_24_regular),
                        border: OutlineInputBorder(),
                      ),
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Username is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon:
                            const Icon(FluentIcons.lock_closed_24_regular),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? FluentIcons.eye_24_regular
                                : FluentIcons.eye_off_24_regular,
                          ),
                          onPressed: () {
                            setState(
                                () => _obscurePassword = !_obscurePassword);
                          },
                        ),
                      ),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Password is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Steam Guard (optional)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'If you have Steam Mobile Authenticator, open the Steam app '
                      'on your phone → Steam Guard → enter the 5-character code.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _steamGuardController,
                      decoration: const InputDecoration(
                        labelText: 'Steam Guard Code',
                        prefixIcon: Icon(FluentIcons.shield_keyhole_24_regular),
                        border: OutlineInputBorder(),
                        hintText: 'XXXXX',
                      ),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z0-9]')),
                        LengthLimitingTextInputFormatter(5),
                      ],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: _rememberCredentials,
                      onChanged: (value) {
                        setState(
                            () => _rememberCredentials = value ?? false);
                      },
                      title: Text(
                        'Remember my credentials',
                        style: theme.textTheme.bodyMedium,
                      ),
                      subtitle: Text(
                        'Stored securely on this device',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      secondary: Icon(
                        FluentIcons.shield_keyhole_24_regular,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5),
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
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
          onPressed: _loading ? null : _submit,
          icon: const Icon(FluentIcons.arrow_right_24_regular, size: 18),
          label: const Text('Login'),
        ),
      ],
    );
  }
}
