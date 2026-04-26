import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:twmt/i18n/strings.g.dart';
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
        SettingsSectionHeader(
          title: t.settings.general.workshop.sectionTitle,
          subtitle: t.settings.general.workshop.sectionSubtitle,
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
              t.settings.general.workshop.folderSubtitle,
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
              label: _isDetecting ? t.settings.general.workshop.detectingLabel : t.settings.general.workshop.detectButton,
              icon: FluentIcons.search_24_regular,
              tooltip: t.tooltips.settings.detectWorkshop,
              onTap: _isDetecting ? null : _autoDetectWorkshop,
            ),
            const SizedBox(width: 6),
            SmallTextButton(
              label: t.settings.general.workshop.browseButton,
              icon: FluentIcons.folder_open_24_regular,
              tooltip: t.tooltips.settings.browsePath,
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
      dialogTitle: t.settings.general.workshop.browseDialogTitle,
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
            FluentToast.success(context, t.settings.general.workshop.toasts.detected(path: workshopPath));
          }
        } else {
          if (mounted) {
            FluentToast.warning(context, t.settings.general.workshop.toasts.notFound);
          }
        }
      } else {
        if (mounted) {
          FluentToast.error(context, t.settings.general.workshop.toasts.detectionFailed(error: result.unwrapErr().message));
        }
      }
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, t.settings.general.workshop.toasts.detectionError(error: e));
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
      if (mounted) FluentToast.error(context, t.settings.general.workshop.toasts.saveError(error: e));
    }
  }
}
