import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:twmt/config/tooltip_strings.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import '../../providers/settings_providers.dart';
import 'settings_section_header.dart';

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
        const SettingsSectionHeader(
          title: 'Steam Workshop',
          subtitle:
              'Base folder for Steam Workshop content (game IDs will be appended automatically)',
        ),
        const SizedBox(height: 16),
        _buildWorkshopPathField(),
      ],
    );
  }

  Widget _buildWorkshopPathField() {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              FluentIcons.folder_24_regular,
              size: 16,
              color: tokens.text,
            ),
            const SizedBox(width: 8),
            Text(
              'Steam Workshop Base Folder',
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
              label: _isDetecting ? 'Detecting...' : 'Detect',
              icon: FluentIcons.search_24_regular,
              tooltip: TooltipStrings.settingsDetectWorkshop,
              onTap: _isDetecting ? null : _autoDetectWorkshop,
            ),
            const SizedBox(width: 6),
            SmallTextButton(
              label: 'Browse',
              icon: FluentIcons.folder_open_24_regular,
              tooltip: TooltipStrings.settingsBrowsePath,
              onTap: _selectWorkshopPath,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: widget.workshopPathController,
                decoration: InputDecoration(
                  hintText:
                      r'C:\Program Files (x86)\Steam\steamapps\workshop\content',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: _saveWorkshopPath,
              ),
            ),
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
    if (_isDetecting) return;

    setState(() => _isDetecting = true);

    try {
      final steamDetection = ref.read(steamDetectionServiceProvider);
      final result = await steamDetection.detectWorkshopFolder();

      if (!mounted) return;

      if (result.isOk) {
        final workshopPath = result.unwrap();
        if (workshopPath != null && workshopPath.isNotEmpty) {
          setState(() => widget.workshopPathController.text = workshopPath);
          await _saveWorkshopPath(workshopPath);
          if (mounted) {
            FluentToast.success(context, 'Workshop folder detected: $workshopPath');
          }
        } else {
          if (mounted) {
            FluentToast.warning(context, 'Workshop folder not found. Please select manually.');
          }
        }
      } else {
        if (mounted) {
          FluentToast.error(context, 'Detection failed: ${result.unwrapErr().message}');
        }
      }
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, 'Detection error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isDetecting = false);
      }
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
