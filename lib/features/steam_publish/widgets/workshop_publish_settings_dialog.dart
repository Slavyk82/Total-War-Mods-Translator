import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../../../features/settings/providers/settings_providers.dart'
    hide settingsServiceProvider;
import '../../../providers/shared/service_providers.dart';
import '../../../services/steam/models/workshop_publish_params.dart';

/// Token-themed popup configuring default templates for Workshop title and
/// description. Templates support `$modName` which is replaced by the project
/// display name at publish time.
class WorkshopPublishSettingsDialog extends ConsumerStatefulWidget {
  const WorkshopPublishSettingsDialog({super.key});

  /// Show the settings dialog. Returns `true` if the user saved changes.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => const WorkshopPublishSettingsDialog(),
    );
    return result ?? false;
  }

  @override
  ConsumerState<WorkshopPublishSettingsDialog> createState() =>
      _WorkshopPublishSettingsDialogState();
}

class _WorkshopPublishSettingsDialogState
    extends ConsumerState<WorkshopPublishSettingsDialog> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  WorkshopVisibility? _defaultVisibility;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    final service = ref.read(settingsServiceProvider);
    final title = await service.getString(SettingsKeys.workshopTitleTemplate);
    final description =
        await service.getString(SettingsKeys.workshopDescriptionTemplate);
    final visibilityName =
        await service.getString(SettingsKeys.workshopDefaultVisibility);
    if (!mounted) return;
    _titleController.text = title;
    _descriptionController.text = description;
    _defaultVisibility = WorkshopVisibility.values
            .where((v) => v.name == visibilityName)
            .firstOrNull ??
        WorkshopVisibility.public_;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final service = ref.read(settingsServiceProvider);
    await service.setString(
      SettingsKeys.workshopTitleTemplate,
      _titleController.text,
    );
    await service.setString(
      SettingsKeys.workshopDescriptionTemplate,
      _descriptionController.text,
    );
    await service.setString(
      SettingsKeys.workshopDefaultVisibility,
      _defaultVisibility?.name ?? '',
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return TokenDialog(
      icon: FluentIcons.settings_24_regular,
      title: t.steamPublish.settingsDialog.title,
      width: 640,
      body: _loading
          ? SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(color: tokens.accent),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.steamPublish.settingsDialog.description(modName: r'$modName'),
                  style: tokens.fontBody.copyWith(
                    fontSize: 12,
                    color: tokens.textDim,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _titleController,
                  style: tokens.fontBody
                      .copyWith(fontSize: 13, color: tokens.text),
                  decoration: _decoration(
                    tokens,
                    label: t.steamPublish.settingsDialog.titleTemplateLabel,
                    hint: t.steamPublish.settingsDialog.titleTemplateHint(modName: r'$modName'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: TextField(
                    controller: _descriptionController,
                    style: tokens.fontBody
                        .copyWith(fontSize: 13, color: tokens.text),
                    decoration: _decoration(
                      tokens,
                      label: t.steamPublish.settingsDialog.descriptionTemplateLabel,
                      hint: t.steamPublish.settingsDialog.descriptionTemplateHint(modName: r'$modName'),
                    ),
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<WorkshopVisibility?>(
                  initialValue: _defaultVisibility,
                  style: tokens.fontBody
                      .copyWith(fontSize: 13, color: tokens.text),
                  dropdownColor: tokens.panel,
                  decoration: _decoration(
                    tokens,
                    label: t.steamPublish.settingsDialog.defaultVisibilityLabel,
                  ),
                  items: [
                    DropdownMenuItem<WorkshopVisibility?>(
                      value: null,
                      child: Text(t.steamPublish.settingsDialog.noDefault),
                    ),
                    ...WorkshopVisibility.values.map((v) {
                      return DropdownMenuItem<WorkshopVisibility?>(
                        value: v,
                        child: Text(v.label),
                      );
                    }),
                  ],
                  onChanged: (value) =>
                      setState(() => _defaultVisibility = value),
                ),
              ],
            ),
      actions: [
        SmallTextButton(
          label: t.steamPublish.settingsDialog.cancel,
          onTap: () => Navigator.of(context).pop(false),
        ),
        SmallTextButton(
          label: t.steamPublish.settingsDialog.save,
          icon: FluentIcons.save_24_regular,
          filled: true,
          onTap: _loading ? null : _save,
        ),
      ],
    );
  }

  InputDecoration _decoration(
    TwmtThemeTokens tokens, {
    required String label,
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
    );
  }
}
