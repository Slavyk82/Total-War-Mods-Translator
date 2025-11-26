import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../../providers/settings_providers.dart';
import 'settings_section_header.dart';

/// Language preferences configuration section.
///
/// Allows users to configure the default target language for new projects.
class LanguagePreferencesSection extends ConsumerStatefulWidget {
  final String initialLanguage;

  const LanguagePreferencesSection({
    super.key,
    required this.initialLanguage,
  });

  @override
  ConsumerState<LanguagePreferencesSection> createState() =>
      _LanguagePreferencesSectionState();
}

class _LanguagePreferencesSectionState
    extends ConsumerState<LanguagePreferencesSection> {
  late String _targetLanguage;

  @override
  void initState() {
    super.initState();
    _targetLanguage = widget.initialLanguage;
  }

  @override
  void didUpdateWidget(covariant LanguagePreferencesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialLanguage != widget.initialLanguage) {
      _targetLanguage = widget.initialLanguage;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Language Preferences',
          subtitle: 'Default target language for new projects',
        ),
        const SizedBox(height: 16),
        _buildLanguageDropdown(),
      ],
    );
  }

  Widget _buildLanguageDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Default Target Language',
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _targetLanguage,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: const [
            DropdownMenuItem(value: 'en', child: Text('English')),
            DropdownMenuItem(value: 'de', child: Text('German (Deutsch)')),
            DropdownMenuItem(value: 'es', child: Text('Spanish (Espanol)')),
            DropdownMenuItem(value: 'fr', child: Text('French (Francais)')),
            DropdownMenuItem(value: 'ru', child: Text('Russian')),
            DropdownMenuItem(value: 'zh', child: Text('Chinese')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _targetLanguage = value);
              _saveTargetLanguage(value);
            }
          },
        ),
      ],
    );
  }

  Future<void> _saveTargetLanguage(String language) async {
    try {
      await ref
          .read(generalSettingsProvider.notifier)
          .updateDefaultTargetLanguage(language);
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, 'Error saving target language: $e');
      }
    }
  }
}
