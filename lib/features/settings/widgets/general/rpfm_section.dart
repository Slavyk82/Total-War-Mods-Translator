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
        const SettingsSectionHeader(
          title: 'RPFM Tool',
          subtitle: 'Path to RPFM executable for pack file extraction',
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
              'RPFM Executable',
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
              label: 'Test',
              icon: FluentIcons.beaker_24_regular,
              tooltip: t.tooltips.settings.testRpfm,
              onTap: _testRpfmPath,
            ),
            const SizedBox(width: 6),
            SmallTextButton(
              label: 'Browse',
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
              'RPFM Schema Folder',
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
          'Folder containing RPFM schema files (e.g., schema_wh3.ron)',
          style: tokens.fontBody.copyWith(
            fontSize: 12,
            color: tokens.textDim,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SmallTextButton(
              label: 'Default',
              icon: FluentIcons.checkmark_circle_24_regular,
              tooltip: t.tooltips.settings.defaultPath,
              onTap: _useDefaultRpfmSchemaPath,
            ),
            const SizedBox(width: 6),
            SmallTextButton(
              label: 'Browse',
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
      dialogTitle: 'Select RPFM Executable',
      type: FileType.custom,
      allowedExtensions: ['exe'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      if (mounted) FluentToast.info(context, 'Validating RPFM executable...');

      final validationResult = await RpfmCliManager.validateRpfmPath(path);
      validationResult.when(
        ok: (version) {
          setState(() => widget.rpfmPathController.text = path);
          _saveRpfmPath(path);
          if (mounted) {
            FluentToast.success(
                context, 'RPFM v$version validated successfully');
          }
        },
        err: (error) {
          if (mounted) {
            FluentToast.error(
                context, 'Invalid RPFM executable: ${error.message}');
          }
        },
      );
    }
  }

  Future<void> _selectRpfmSchemaPath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select RPFM Schema Folder',
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
      FluentToast.warning(context, 'Please enter RPFM path first');
      return;
    }

    FluentToast.info(context, 'Testing RPFM executable...');

    final validationResult = await RpfmCliManager.validateRpfmPath(path);
    validationResult.when(
      ok: (version) {
        if (mounted) {
          FluentToast.success(context, 'RPFM v$version is working correctly');
        }
      },
      err: (error) {
        if (mounted) {
          FluentToast.error(context, 'RPFM test failed: ${error.message}');
        }
      },
    );
  }

  // === Default Path Methods ===

  Future<void> _useDefaultRpfmSchemaPath() async {
    final username =
        io.Platform.environment['USERNAME'] ?? io.Platform.environment['USER'];
    if (username == null || username.isEmpty) {
      if (mounted) FluentToast.warning(context, 'Could not detect username');
      return;
    }

    final defaultPath =
        r'C:\Users\$username\AppData\Roaming\FrodoWazEre\rpfm\config\schemas'
            .replaceAll('\$username', username);

    setState(() => widget.rpfmSchemaPathController.text = defaultPath);
    await _saveRpfmSchemaPath(defaultPath);

    if (mounted) {
      FluentToast.info(context, 'Set to default schema path');
    }
  }

  // === Save Methods ===

  Future<void> _saveRpfmPath(String path) async {
    try {
      await ref
          .read(generalSettingsProvider.notifier)
          .updateRpfmPath(path);
    } catch (e) {
      if (mounted) FluentToast.error(context, 'Error saving RPFM path: $e');
    }
  }

  Future<void> _saveRpfmSchemaPath(String path) async {
    try {
      await ref
          .read(generalSettingsProvider.notifier)
          .updateRpfmSchemaPath(path);
    } catch (e) {
      if (mounted) FluentToast.error(context, 'Error saving RPFM schema path: $e');
    }
  }
}
