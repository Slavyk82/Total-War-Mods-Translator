import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_providers.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../models/game_display_info.dart';
import 'general/game_installations_section.dart';
import 'general/workshop_section.dart';
import 'general/rpfm_section.dart';
import 'general/language_preferences_section.dart';
import 'general/application_settings_section.dart';
import 'general/cache_management_section.dart';

/// General settings tab for configuring game paths, languages, and preferences.
///
/// Delegates to specialized section widgets for each configuration area.
class GeneralSettingsTab extends ConsumerStatefulWidget {
  const GeneralSettingsTab({super.key});

  @override
  ConsumerState<GeneralSettingsTab> createState() => _GeneralSettingsTabState();
}

class _GeneralSettingsTabState extends ConsumerState<GeneralSettingsTab> {
  final _formKey = GlobalKey<FormState>();

  late Map<String, TextEditingController> _gamePathControllers;
  late TextEditingController _workshopPathController;
  late TextEditingController _rpfmPathController;
  late TextEditingController _rpfmSchemaPathController;

  /// Supported games with display information
  static const List<GameDisplayInfo> _games = [
    GameDisplayInfo(
      code: 'wh3',
      name: 'Total War: WARHAMMER III',
      settingsKey: SettingsKeys.gamePathWh3,
    ),
    GameDisplayInfo(
      code: 'wh2',
      name: 'Total War: WARHAMMER II',
      settingsKey: SettingsKeys.gamePathWh2,
    ),
    GameDisplayInfo(
      code: 'wh',
      name: 'Total War: WARHAMMER',
      settingsKey: SettingsKeys.gamePathWh,
    ),
    GameDisplayInfo(
      code: 'rome2',
      name: 'Total War: Rome II',
      settingsKey: SettingsKeys.gamePathRome2,
    ),
    GameDisplayInfo(
      code: 'attila',
      name: 'Total War: Attila',
      settingsKey: SettingsKeys.gamePathAttila,
    ),
    GameDisplayInfo(
      code: 'troy',
      name: 'Total War: Troy',
      settingsKey: SettingsKeys.gamePathTroy,
    ),
    GameDisplayInfo(
      code: '3k',
      name: 'Total War: Three Kingdoms',
      settingsKey: SettingsKeys.gamePath3k,
    ),
    GameDisplayInfo(
      code: 'pharaoh',
      name: 'Total War: Pharaoh',
      settingsKey: SettingsKeys.gamePathPharaoh,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _workshopPathController = TextEditingController();
    _rpfmPathController = TextEditingController();
    _rpfmSchemaPathController = TextEditingController();
    _gamePathControllers = {
      for (final game in _games) game.code: TextEditingController(),
    };
  }

  @override
  void dispose() {
    _workshopPathController.dispose();
    _rpfmPathController.dispose();
    _rpfmSchemaPathController.dispose();
    for (final controller in _gamePathControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(generalSettingsProvider);

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Text('Error loading settings: $error'),
      ),
      data: (settings) {
        _loadSettingsIntoControllers(settings);

        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              GameInstallationsSection(
                gamePathControllers: _gamePathControllers,
                games: _games,
              ),
              const SizedBox(height: 16),
              WorkshopSection(
                workshopPathController: _workshopPathController,
              ),
              const SizedBox(height: 32),
              RpfmSection(
                rpfmPathController: _rpfmPathController,
                rpfmSchemaPathController: _rpfmSchemaPathController,
              ),
              const SizedBox(height: 32),
              LanguagePreferencesSection(
                initialLanguage:
                    settings[SettingsKeys.defaultTargetLanguage] ?? 'fr',
              ),
              const SizedBox(height: 32),
              ApplicationSettingsSection(
                initialAutoUpdate:
                    settings[SettingsKeys.autoUpdate] == 'true',
              ),
              const SizedBox(height: 32),
              CacheManagementSection(
                onResetToDefaults: _resetToDefaults,
              ),
            ],
          ),
        );
      },
    );
  }

  void _loadSettingsIntoControllers(Map<String, dynamic> settings) {
    for (final game in _games) {
      if (_gamePathControllers[game.code]!.text.isEmpty) {
        _gamePathControllers[game.code]!.text = settings[game.settingsKey] ?? '';
      }
    }
    if (_workshopPathController.text.isEmpty) {
      _workshopPathController.text = settings[SettingsKeys.workshopPath] ?? '';
    }
    if (_rpfmPathController.text.isEmpty) {
      _rpfmPathController.text = settings[SettingsKeys.rpfmPath] ?? '';
    }
    if (_rpfmSchemaPathController.text.isEmpty) {
      _rpfmSchemaPathController.text =
          settings[SettingsKeys.rpfmSchemaPath] ?? '';
    }
  }

  Future<void> _resetToDefaults() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: const Text(
          'Are you sure you want to reset all general settings to defaults?',
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FluentTextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(generalSettingsProvider.notifier).resetToDefaults();
      for (final controller in _gamePathControllers.values) {
        controller.clear();
      }
      _workshopPathController.clear();
      _rpfmPathController.clear();
      _rpfmSchemaPathController.clear();
      if (mounted) {
        FluentToast.success(context, 'Settings reset to defaults');
      }
    }
  }
}
