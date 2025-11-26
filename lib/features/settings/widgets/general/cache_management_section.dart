import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../../providers/settings_providers.dart';
import 'settings_section_header.dart';

/// Cache management configuration section.
///
/// Allows users to clear cached data and reset settings to defaults.
class CacheManagementSection extends ConsumerWidget {
  final VoidCallback onResetToDefaults;

  const CacheManagementSection({
    super.key,
    required this.onResetToDefaults,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Cache Management',
          subtitle: 'Manage application cache and temporary data',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FluentOutlinedButton(
              onPressed: () => _clearCache(context, ref),
              icon: const Icon(FluentIcons.delete_24_regular),
              child: const Text('Clear Cache'),
            ),
            const SizedBox(width: 8),
            Text(
              'Clear cached files and temporary data',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        FluentOutlinedButton(
          onPressed: onResetToDefaults,
          icon: const Icon(FluentIcons.arrow_reset_24_regular),
          child: const Text('Reset to Defaults'),
        ),
      ],
    );
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text('Are you sure you want to clear all cached data?'),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FluentTextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await ref.read(generalSettingsProvider.notifier).clearCache();
      if (context.mounted) {
        FluentToast.success(context, 'Cache cleared successfully');
      }
    }
  }
}
