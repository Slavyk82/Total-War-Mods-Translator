import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../../settings/providers/settings_providers.dart';

const _secureStorage = FlutterSecureStorage(
  wOptions: WindowsOptions(useBackwardCompatibility: false),
);

/// Token-themed popup for entering Steam credentials.
class SteamLoginDialog extends StatefulWidget {
  const SteamLoginDialog({super.key});

  /// Return saved credentials without showing the dialog, or null if none saved.
  static Future<(String, String, String?)?> getSavedCredentials() async {
    final username =
        await _secureStorage.read(key: SettingsKeys.steamUsername);
    final password =
        await _secureStorage.read(key: SettingsKeys.steamPassword);
    if (username != null &&
        username.isNotEmpty &&
        password != null &&
        password.isNotEmpty) {
      return (username, password, null);
    }
    return null;
  }

  /// Show the login dialog and return (username, password, steamGuardCode?) or
  /// null if cancelled.
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
    final tokens = context.tokens;

    return TokenDialog(
      icon: FluentIcons.person_24_regular,
      title: t.steamPublish.loginDialog.title,
      width: 460,
      body: _loading
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: tokens.accent),
              ),
            )
          : Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t.steamPublish.loginDialog.description,
                    style: tokens.fontBody.copyWith(
                      fontSize: 13,
                      color: tokens.textDim,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _usernameController,
                    style: tokens.fontBody
                        .copyWith(fontSize: 13, color: tokens.text),
                    decoration: _decoration(
                      tokens,
                      label: t.steamPublish.loginDialog.usernameLabel,
                      prefixIcon: FluentIcons.person_24_regular,
                    ),
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return t.steamPublish.loginDialog.errors.usernameRequired;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _passwordController,
                    style: tokens.fontBody
                        .copyWith(fontSize: 13, color: tokens.text),
                    decoration: _decoration(
                      tokens,
                      label: t.steamPublish.loginDialog.passwordLabel,
                      prefixIcon: FluentIcons.lock_closed_24_regular,
                    ).copyWith(
                      suffixIcon: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          child: Icon(
                            _obscurePassword
                                ? FluentIcons.eye_24_regular
                                : FluentIcons.eye_off_24_regular,
                            color: tokens.textDim,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return t.steamPublish.loginDialog.errors.passwordRequired;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  Text(
                    t.steamPublish.loginDialog.steamGuardSection,
                    style: tokens.fontBody.copyWith(
                      fontSize: 13,
                      color: tokens.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.steamPublish.loginDialog.steamGuardDescription,
                    style: tokens.fontBody.copyWith(
                      fontSize: 11.5,
                      color: tokens.textDim,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _steamGuardController,
                    style: tokens.fontBody
                        .copyWith(fontSize: 13, color: tokens.text),
                    decoration: _decoration(
                      tokens,
                      label: t.steamPublish.loginDialog.steamGuardCodeLabel,
                      prefixIcon: FluentIcons.shield_keyhole_24_regular,
                      hint: t.steamPublish.loginDialog.hintCode,
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
                  const SizedBox(height: 10),
                  _RememberToggle(
                    value: _rememberCredentials,
                    onChanged: (v) =>
                        setState(() => _rememberCredentials = v),
                  ),
                ],
              ),
            ),
      actions: [
        SmallTextButton(
          label: t.steamPublish.loginDialog.cancel,
          onTap: () => Navigator.of(context).pop(null),
        ),
        SmallTextButton(
          label: t.steamPublish.loginDialog.login,
          icon: FluentIcons.arrow_right_24_regular,
          filled: true,
          onTap: _loading ? null : _submit,
        ),
      ],
    );
  }

  InputDecoration _decoration(
    TwmtThemeTokens tokens, {
    required String label,
    required IconData prefixIcon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle:
          tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
      floatingLabelStyle:
          tokens.fontBody.copyWith(fontSize: 12, color: tokens.accent),
      hintText: hint,
      hintStyle:
          tokens.fontBody.copyWith(fontSize: 13, color: tokens.textFaint),
      prefixIcon: Icon(prefixIcon, color: tokens.textDim, size: 18),
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.err),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.err),
      ),
      errorStyle:
          tokens.fontBody.copyWith(fontSize: 11.5, color: tokens.err),
    );
  }
}

class _RememberToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _RememberToggle({required this.value, required this.onChanged});

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
                      t.steamPublish.loginDialog.rememberCredentials,
                      style: tokens.fontBody.copyWith(
                        fontSize: 13,
                        color: tokens.text,
                      ),
                    ),
                    Text(
                      t.steamPublish.loginDialog.storedSecurely,
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
