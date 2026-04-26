import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../providers/settings_providers.dart';
import '../models/game_display_info.dart';
import 'general/game_installations_section.dart';
import 'general/workshop_section.dart';
import 'general/rpfm_section.dart';

class FoldersSettingsTab extends ConsumerStatefulWidget {
  const FoldersSettingsTab({super.key});

  @override
  ConsumerState<FoldersSettingsTab> createState() => _FoldersSettingsTabState();
}

class _FoldersSettingsTabState extends ConsumerState<FoldersSettingsTab> {
  final _formKey = GlobalKey<FormState>();

  late final Map<String, TextEditingController> _gamePathControllers;
  late final TextEditingController _workshopPathController;
  late final TextEditingController _rpfmPathController;
  late final TextEditingController _rpfmSchemaPathController;
  bool _initialLoadDone = false;

  static const List<GameDisplayInfo> _games = [
    GameDisplayInfo(code: 'wh3', name: 'Total War: WARHAMMER III', settingsKey: SettingsKeys.gamePathWh3),
    GameDisplayInfo(code: 'wh2', name: 'Total War: WARHAMMER II', settingsKey: SettingsKeys.gamePathWh2),
    GameDisplayInfo(code: 'wh', name: 'Total War: WARHAMMER', settingsKey: SettingsKeys.gamePathWh),
    GameDisplayInfo(code: 'rome2', name: 'Total War: Rome II', settingsKey: SettingsKeys.gamePathRome2),
    GameDisplayInfo(code: 'attila', name: 'Total War: Attila', settingsKey: SettingsKeys.gamePathAttila),
    GameDisplayInfo(code: 'troy', name: 'Total War: Troy', settingsKey: SettingsKeys.gamePathTroy),
    GameDisplayInfo(code: '3k', name: 'Total War: Three Kingdoms', settingsKey: SettingsKeys.gamePath3k),
    GameDisplayInfo(code: 'pharaoh', name: 'Total War: Pharaoh', settingsKey: SettingsKeys.gamePathPharaoh),
    GameDisplayInfo(code: 'pharaoh_dynasties', name: 'Total War: Pharaoh Dynasties', settingsKey: SettingsKeys.gamePathPharaohDynasties),
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

    // Load settings into controllers once, via listenManual (not in build).
    ref.listenManual<AsyncValue<Map<String, dynamic>>>(
      generalSettingsProvider,
      (_, next) {
        if (_initialLoadDone) return;
        final settings = next is AsyncData<Map<String, dynamic>> ? next.value : null;
        if (settings == null) return;
        _initialLoadDone = true;
        for (final game in _games) {
          _gamePathControllers[game.code]!.text = settings[game.settingsKey] ?? '';
        }
        _workshopPathController.text = settings[SettingsKeys.workshopPath] ?? '';
        _rpfmPathController.text = settings[SettingsKeys.rpfmPath] ?? '';
        _rpfmSchemaPathController.text = settings[SettingsKeys.rpfmSchemaPath] ?? '';
      },
      fireImmediately: true,
    );
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
    final tokens = context.tokens;

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Text(
          t.settings.errors.loadSettings(error: error),
          style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.err),
        ),
      ),
      data: (settings) {
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
}
