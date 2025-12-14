import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/config/tooltip_strings.dart';
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
            _AddLanguageButton(
              onPressed: () => _showAddLanguageDialog(context, ref),
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

/// Button to add a new custom language
class _AddLanguageButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _AddLanguageButton({required this.onPressed});

  @override
  State<_AddLanguageButton> createState() => _AddLanguageButtonState();
}

class _AddLanguageButtonState extends State<_AddLanguageButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: TooltipStrings.settingsAddLanguage,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _isHovered
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _isHovered
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.add_24_regular,
                  size: 18,
                  color: _isHovered
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                ),
                const SizedBox(width: 6),
                Text(
                  'Add Language',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _isHovered
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
