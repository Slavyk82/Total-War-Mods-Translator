import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../../providers/settings_providers.dart';
import 'settings_action_button.dart';

/// Steam Workshop configuration section.
///
/// Allows users to configure the base path to Steam Workshop content folder.
class WorkshopSection extends ConsumerStatefulWidget {
  final TextEditingController workshopPathController;

  const WorkshopSection({
    super.key,
    required this.workshopPathController,
  });

  @override
  ConsumerState<WorkshopSection> createState() => _WorkshopSectionState();
}

class _WorkshopSectionState extends ConsumerState<WorkshopSection> {
  bool _isDetecting = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Steam Workshop',
          subtitle:
              'Base folder for Steam Workshop content (game IDs will be appended automatically)',
        ),
        const SizedBox(height: 16),
        _buildWorkshopPathField(),
      ],
    );
  }

  Widget _buildSectionHeader(String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
          ),
        ],
      ],
    );
  }

  Widget _buildWorkshopPathField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(FluentIcons.folder_24_regular, size: 16),
            const SizedBox(width: 8),
            Text(
              'Steam Workshop Base Folder',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: widget.workshopPathController,
                decoration: InputDecoration(
                  hintText:
                      r'C:\Program Files (x86)\Steam\steamapps\workshop\content',
                  helperText:
                      'Game IDs (e.g., 1142710 for Warhammer III) will be added automatically',
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: _saveWorkshopPath,
              ),
            ),
            const SizedBox(width: 8),
            SettingsActionButton.detect(
              onPressed: _autoDetectWorkshop,
              isDetecting: _isDetecting,
            ),
            const SizedBox(width: 4),
            SettingsActionButton.browse(onPressed: _selectWorkshopPath),
          ],
        ),
      ],
    );
  }

  // === File Picker Methods ===

  Future<void> _selectWorkshopPath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Steam Workshop Folder',
    );
    if (result != null) {
      setState(() => widget.workshopPathController.text = result);
      await _saveWorkshopPath(result);
    }
  }

  // === Auto-Detection Methods ===

  Future<void> _autoDetectWorkshop() async {
    if (mounted) {
      FluentToast.info(context, 'Auto-detection not yet implemented for Workshop folder');
    }
  }

  // === Save Methods ===

  Future<void> _saveWorkshopPath(String path) async {
    try {
      await ref
          .read(generalSettingsProvider.notifier)
          .updateWorkshopPath(path);
    } catch (e) {
      if (mounted) FluentToast.error(context, 'Error saving workshop path: $e');
    }
  }
}
