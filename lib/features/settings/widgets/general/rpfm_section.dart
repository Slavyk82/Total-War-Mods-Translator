import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/services/rpfm/rpfm_cli_manager.dart';
import '../../providers/settings_providers.dart';
import 'settings_section_header.dart';

/// RPFM Tool configuration section.
///
/// Allows users to configure paths to RPFM executable and schema folder.
class RpfmSection extends ConsumerStatefulWidget {
  final TextEditingController rpfmPathController;
  final TextEditingController rpfmSchemaPathController;

  const RpfmSection({
    super.key,
    required this.rpfmPathController,
    required this.rpfmSchemaPathController,
  });

  @override
  ConsumerState<RpfmSection> createState() => _RpfmSectionState();
}

class _RpfmSectionState extends ConsumerState<RpfmSection> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(
          title: t.settings.general.rpfm.sectionTitle,
          subtitle: t.settings.general.rpfm.sectionSubtitle,
        ),
        const SizedBox(height: 16),
        _buildRpfmPathField(),
        const SizedBox(height: 24),
        _buildRpfmSchemaPathField(),
      ],
    );
  }

  Widget _buildRpfmPathField() {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              FluentIcons.wrench_24_regular,
              size: 16,
              color: tokens.text,
            ),
            const SizedBox(width: 8),
            Text(
              t.settings.general.rpfm.executableSubtitle,
              style: tokens.fontBody.copyWith(
                fontSize: 14,
                color: tokens.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SmallTextButton(
              label: t.settings.general.rpfm.testButton,
              icon: FluentIcons.beaker_24_regular,
              tooltip: t.tooltips.settings.testRpfm,
              onTap: _testRpfmPath,
            ),
            const SizedBox(width: 6),
            SmallTextButton(
              label: t.settings.general.rpfm.browseButton,
              icon: FluentIcons.folder_open_24_regular,
              tooltip: t.tooltips.settings.browsePath,
              onTap: _selectRpfmPath,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: widget.rpfmPathController,
                decoration: InputDecoration(
                  hintText: r'C:\Path\To\rpfm_cli.exe',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: _saveRpfmPath,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRpfmSchemaPathField() {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              FluentIcons.database_24_regular,
              size: 16,
              color: tokens.text,
            ),
            const SizedBox(width: 8),
            Text(
              t.settings.general.rpfm.schemaSubtitle,
              style: tokens.fontBody.copyWith(
                fontSize: 14,
                color: tokens.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          t.settings.general.rpfm.schemaDescription,
          style: tokens.fontBody.copyWith(
            fontSize: 12,
            color: tokens.textDim,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SmallTextButton(
              label: t.settings.general.rpfm.defaultButton,
              icon: FluentIcons.checkmark_circle_24_regular,
              tooltip: t.tooltips.settings.defaultPath,
              onTap: _useDefaultRpfmSchemaPath,
            ),
            const SizedBox(width: 6),
            SmallTextButton(
              label: t.settings.general.rpfm.browseButton,
              icon: FluentIcons.folder_open_24_regular,
              tooltip: t.tooltips.settings.browsePath,
              onTap: _selectRpfmSchemaPath,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: widget.rpfmSchemaPathController,
                decoration: InputDecoration(
                  hintText:
                      r'C:\Users\USERNAME\AppData\Roaming\FrodoWazEre\rpfm\config\schemas',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: _saveRpfmSchemaPath,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // === File Picker Methods ===

  Future<void> _selectRpfmPath() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: t.settings.general.rpfm.browseExeDialogTitle,
      type: FileType.custom,
      allowedExtensions: ['exe'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      if (mounted) FluentToast.info(context, t.settings.general.rpfm.toasts.validating);

      final validationResult = await RpfmCliManager.validateRpfmPath(path);
      validationResult.when(
        ok: (version) {
          setState(() => widget.rpfmPathController.text = path);
          _saveRpfmPath(path);
          if (mounted) {
            FluentToast.success(
                context, t.settings.general.rpfm.toasts.validatedSuccess(version: version));
          }
        },
        err: (error) {
          if (mounted) {
            FluentToast.error(
                context, t.settings.general.rpfm.toasts.invalidExe(error: error.message));
          }
        },
      );
    }
  }

  Future<void> _selectRpfmSchemaPath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: t.settings.general.rpfm.browseSchemaDialogTitle,
    );
    if (result != null) {
      setState(() => widget.rpfmSchemaPathController.text = result);
      await _saveRpfmSchemaPath(result);
    }
  }

  // === Test Methods ===

  Future<void> _testRpfmPath() async {
    final path = widget.rpfmPathController.text.trim();
    if (path.isEmpty) {
      FluentToast.warning(context, t.settings.general.rpfm.toasts.enterPathFirst);
      return;
    }

    FluentToast.info(context, t.settings.general.rpfm.toasts.testing);

    final validationResult = await RpfmCliManager.validateRpfmPath(path);
    validationResult.when(
      ok: (version) {
        if (mounted) {
          FluentToast.success(context, t.settings.general.rpfm.toasts.testSuccess(version: version));
        }
      },
      err: (error) {
        if (mounted) {
          FluentToast.error(context, t.settings.general.rpfm.toasts.testFailed(error: error.message));
        }
      },
    );
  }

  // === Default Path Methods ===

  Future<void> _useDefaultRpfmSchemaPath() async {
    final defaultPath =
        resolveDefaultRpfmSchemaPath(io.Platform.environment);
    if (defaultPath == null) {
      if (mounted) FluentToast.warning(context, t.settings.general.rpfm.toasts.usernameNotDetected);
      return;
    }

    setState(() => widget.rpfmSchemaPathController.text = defaultPath);
    await _saveRpfmSchemaPath(defaultPath);

    if (mounted) {
      FluentToast.info(context, t.settings.general.rpfm.toasts.defaultPathSet);
    }
  }

  // === Save Methods ===

  Future<void> _saveRpfmPath(String path) async {
    try {
      await ref
          .read(generalSettingsProvider.notifier)
          .updateRpfmPath(path);
    } catch (e) {
      if (mounted) FluentToast.error(context, t.settings.general.rpfm.toasts.savePathError(error: e));
    }
  }

  Future<void> _saveRpfmSchemaPath(String path) async {
    try {
      await ref
          .read(generalSettingsProvider.notifier)
          .updateRpfmSchemaPath(path);
    } catch (e) {
      if (mounted) FluentToast.error(context, t.settings.general.rpfm.toasts.saveSchemaPathError(error: e));
    }
  }
}

/// Resolves the default RPFM schema directory from [environment].
///
/// Prefers `APPDATA` — the real roaming-profile directory, which stays
/// correct on relocated profiles, profile folders whose name differs from
/// the account name, and systems where Windows is not installed on `C:` —
/// and falls back to `USERPROFILE\AppData\Roaming` when `APPDATA` is unset.
/// Returns `null` when neither variable is available.
///
/// Pure function (environment injected) so it can be unit-tested; production
/// code passes [io.Platform.environment], which is case-insensitive on
/// Windows.
@visibleForTesting
String? resolveDefaultRpfmSchemaPath(Map<String, String> environment) {
  String? roaming;
  final appData = environment['APPDATA'];
  if (appData != null && appData.isNotEmpty) {
    roaming = appData;
  } else {
    final userProfile = environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      roaming = '$userProfile\\AppData\\Roaming';
    }
  }
  if (roaming == null) return null;

  // Avoid a doubled separator when the variable ends with a backslash.
  if (roaming.endsWith('\\')) {
    roaming = roaming.substring(0, roaming.length - 1);
  }
  return '$roaming\\FrodoWazEre\\rpfm\\config\\schemas';
}
