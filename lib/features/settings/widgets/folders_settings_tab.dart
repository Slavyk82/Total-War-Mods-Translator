import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_providers.dart';
import '../models/game_display_info.dart';
import 'general/game_installations_section.dart';
import 'general/workshop_section.dart';
import 'general/rpfm_section.dart';

/// Folders settings tab for configuring game paths, workshop, and tools.
///
/// Delegates to specialized section widgets for each folder configuration area.
class FoldersSettingsTab extends ConsumerStatefulWidget {
  const FoldersSettingsTab({super.key});

  @override
  ConsumerState<FoldersSettingsTab> createState() => _FoldersSettingsTabState();
}

class _FoldersSettingsTabState extends ConsumerState<FoldersSettingsTab> {
  final _formKey = GlobalKey<FormState>();

  late Map<String, TextEditingController> _gamePathControllers;
  late TextEditingController _workshopPathController;
  late TextEditingController _rpfmPathController;
  late TextEditingController _rpfmSchemaPathController;

  /// Tracks whether initial load has been performed to avoid overwriting user changes
  bool _initialLoadDone = false;

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
            ],
          ),
        );
      },
    );
  }

  void _loadSettingsIntoControllers(Map<String, dynamic> settings) {
    // Only load settings once to avoid overwriting user's unsaved changes
    if (_initialLoadDone) return;
    _initialLoadDone = true;

    for (final game in _games) {
      _gamePathControllers[game.code]!.text = settings[game.settingsKey] ?? '';
    }
    _workshopPathController.text = settings[SettingsKeys.workshopPath] ?? '';
    _rpfmPathController.text = settings[SettingsKeys.rpfmPath] ?? '';
    _rpfmSchemaPathController.text =
        settings[SettingsKeys.rpfmSchemaPath] ?? '';
  }
}
