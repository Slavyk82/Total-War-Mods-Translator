import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../../providers/settings_providers.dart';
import 'settings_section_header.dart';

/// Application settings configuration section.
///
/// Allows users to configure general application preferences like auto-update.
class ApplicationSettingsSection extends ConsumerStatefulWidget {
  final bool initialAutoUpdate;

  const ApplicationSettingsSection({
    super.key,
    required this.initialAutoUpdate,
  });

  @override
  ConsumerState<ApplicationSettingsSection> createState() =>
      _ApplicationSettingsSectionState();
}

class _ApplicationSettingsSectionState
    extends ConsumerState<ApplicationSettingsSection> {
  late bool _autoUpdate;

  @override
  void initState() {
    super.initState();
    _autoUpdate = widget.initialAutoUpdate;
  }

  @override
  void didUpdateWidget(covariant ApplicationSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialAutoUpdate != widget.initialAutoUpdate) {
      _autoUpdate = widget.initialAutoUpdate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Application Settings',
          subtitle: 'General application preferences',
        ),
        const SizedBox(height: 16),
        _buildAutoUpdateCheckbox(),
      ],
    );
  }

  Widget _buildAutoUpdateCheckbox() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _toggleAutoUpdate,
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: _autoUpdate,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _autoUpdate = value);
                    _saveAutoUpdate(value);
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Check for updates automatically',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  void _toggleAutoUpdate() {
    final newValue = !_autoUpdate;
    setState(() => _autoUpdate = newValue);
    _saveAutoUpdate(newValue);
  }

  Future<void> _saveAutoUpdate(bool value) async {
    try {
      await ref.read(generalSettingsProvider.notifier).updateAutoUpdate(value);
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, 'Error saving auto-update setting: $e');
      }
    }
  }
}
