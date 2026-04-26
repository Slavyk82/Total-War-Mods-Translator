import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../../../widgets/common/fluent_spinner.dart';
import '../providers/settings_providers.dart';
import 'general/app_language_section.dart';
import 'general/backup_section.dart';
import 'general/language_preferences_section.dart';
import 'general/maintenance_section.dart';
import 'ignored_source_texts_section.dart';

/// General settings tab for configuring languages and maintenance.
///
/// Delegates to specialized section widgets for each configuration area.
/// Note: Application update checking is now in the navigation sidebar.
class GeneralSettingsTab extends ConsumerWidget {
  const GeneralSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final settingsAsync = ref.watch(generalSettingsProvider);

    return settingsAsync.when(
      loading: () => const Center(child: FluentSpinner()),
      error: (error, stack) => Center(
        child: Text(
          t.settings.errors.loadSettings(error: error),
          style: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.err,
          ),
        ),
      ),
      data: (settings) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // AppLanguageSection stays const: it watches `appLocaleProvider`
            // and self-rebuilds on locale change. The other sections must be
            // non-const so MyApp's locale-driven rebuild propagates here and
            // refreshes their translated section headers. See the rationale
            // comment in `settings_screen.dart`.
            const AppLanguageSection(),
            const SizedBox(height: 32),
            LanguagePreferencesSection(),
            const SizedBox(height: 32),
            IgnoredSourceTextsSection(),
            const SizedBox(height: 32),
            MaintenanceSection(),
            const SizedBox(height: 32),
            BackupSection(),
          ],
        );
      },
    );
  }
}
