import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../../../features/settings/providers/settings_providers.dart';
import '../../../services/settings/settings_service.dart';
import '../../../services/service_locator.dart';
import '../../../services/steam/models/workshop_publish_params.dart';

/// Dialog to configure default templates for Workshop title and description.
///
/// Templates support `$modName` which is replaced by the project display name
/// at publish time.
class WorkshopPublishSettingsDialog extends StatefulWidget {
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
  State<WorkshopPublishSettingsDialog> createState() =>
      _WorkshopPublishSettingsDialogState();
}

class _WorkshopPublishSettingsDialogState
    extends State<WorkshopPublishSettingsDialog> {
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
    final service = ServiceLocator.get<SettingsService>();
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
        .firstOrNull;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final service = ServiceLocator.get<SettingsService>();
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
    final theme = Theme.of(context);

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          title: Row(
            children: [
              Icon(FluentIcons.settings_24_regular,
                  size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Text('Workshop Templates'),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _loading ? null : _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Use \$modName as a placeholder for the project name.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title template',
                        border: OutlineInputBorder(),
                        hintText: '\$modName - French translation',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: TextField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description template',
                          border: OutlineInputBorder(),
                          hintText: 'French translation for \$modName',
                        ),
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<WorkshopVisibility?>(
                      initialValue: _defaultVisibility,
                      decoration: const InputDecoration(
                        labelText: 'Default visibility',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<WorkshopVisibility?>(
                          value: null,
                          child: Text('No default'),
                        ),
                        ...WorkshopVisibility.values.map((v) {
                          return DropdownMenuItem<WorkshopVisibility?>(
                            value: v,
                            child: Text(v.label),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() => _defaultVisibility = value);
                      },
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
