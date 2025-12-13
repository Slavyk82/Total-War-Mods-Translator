import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../widgets/common/fluent_spinner.dart';
import '../providers/settings_providers.dart';
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
    final settingsAsync = ref.watch(generalSettingsProvider);

    return settingsAsync.when(
      loading: () => const Center(child: FluentSpinner()),
      error: (error, stack) => Center(
        child: Text('Error loading settings: $error'),
      ),
      data: (settings) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const LanguagePreferencesSection(),
            const SizedBox(height: 32),
            const IgnoredSourceTextsSection(),
            const SizedBox(height: 32),
            const MaintenanceSection(),
          ],
        );
      },
    );
  }
}
