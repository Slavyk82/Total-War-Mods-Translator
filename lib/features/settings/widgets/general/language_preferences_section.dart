import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/config/tooltip_strings.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../../../../widgets/fluent/fluent_widgets.dart';
import '../../providers/language_settings_providers.dart';
import '../add_custom_language_dialog.dart';
import '../language_settings_datagrid.dart';
import 'settings_section_header.dart';

/// Language preferences configuration section.
///
/// Allows users to:
/// - Select the default target language from a table
/// - Add custom languages
/// - Delete custom languages
class LanguagePreferencesSection extends ConsumerWidget {
  const LanguagePreferencesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: SettingsSectionHeader(
                title: 'Transalation Language Preferences',
                subtitle: 'Manage available languages for translations and set the default target language',
              ),
            ),
            SmallTextButton(
              label: 'Add Language',
              icon: FluentIcons.add_24_regular,
              tooltip: TooltipStrings.settingsAddLanguage,
              onTap: () => _showAddLanguageDialog(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const LanguageSettingsDataGrid(),
      ],
    );
  }

  Future<void> _showAddLanguageDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final result = await showDialog<({String code, String name})>(
      context: context,
      builder: (context) => const AddCustomLanguageDialog(),
    );

    if (result != null && context.mounted) {
      final (success, error) =
          await ref.read(languageSettingsProvider.notifier).addCustomLanguage(
                code: result.code,
                name: result.name,
              );

      if (context.mounted) {
        if (success) {
          FluentToast.success(context, 'Language added successfully');
        } else {
          FluentToast.error(context, error ?? 'Failed to add language');
        }
      }
    }
  }
}
