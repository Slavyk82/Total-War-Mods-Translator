import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../../../features/settings/providers/settings_providers.dart';
import '../../../services/settings/settings_service.dart';
import '../../../services/service_locator.dart';

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
    if (!mounted) return;
    _titleController.text = title;
    _descriptionController.text = description;
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

    return AlertDialog(
      title: Row(
        children: [
          Icon(FluentIcons.settings_24_regular,
              size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Workshop Templates'),
        ],
      ),
      content: _loading
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          : SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Use \$modName as a placeholder for the project name.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                  TextField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description template',
                      border: OutlineInputBorder(),
                      hintText: 'French translation for \$modName',
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
