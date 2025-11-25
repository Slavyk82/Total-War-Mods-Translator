import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/settings_providers.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/services/rpfm/rpfm_cli_manager.dart';
import 'package:twmt/services/steam/steam_detection_service.dart';
import '../models/game_display_info.dart';
import 'general/game_installations_section.dart';
import 'general/workshop_section.dart';
import 'general/rpfm_section.dart';
import 'general/settings_action_button.dart';

/// General settings tab for configuring game paths, languages, and preferences.
///
/// Refactored to reduce file size and improve maintainability.
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
  String _targetLanguage = 'es';
  bool _autoUpdate = true;
  
  // Detection service and state
  final _detectionService = SteamDetectionService();
  bool _isDetecting = false;

  // Supported games with display information
  final List<GameDisplayInfo> _games = [
    const GameDisplayInfo(
      code: 'wh3',
      name: 'Total War: WARHAMMER III',
      settingsKey: SettingsKeys.gamePathWh3,
    ),
    const GameDisplayInfo(
      code: 'wh2',
      name: 'Total War: WARHAMMER II',
      settingsKey: SettingsKeys.gamePathWh2,
    ),
    const GameDisplayInfo(
      code: 'wh',
      name: 'Total War: WARHAMMER',
      settingsKey: SettingsKeys.gamePathWh,
    ),
    const GameDisplayInfo(
      code: 'rome2',
      name: 'Total War: Rome II',
      settingsKey: SettingsKeys.gamePathRome2,
    ),
    const GameDisplayInfo(
      code: 'attila',
      name: 'Total War: Attila',
      settingsKey: SettingsKeys.gamePathAttila,
    ),
    const GameDisplayInfo(
      code: 'troy',
      name: 'Total War: Troy',
      settingsKey: SettingsKeys.gamePathTroy,
    ),
    const GameDisplayInfo(
      code: '3k',
      name: 'Total War: Three Kingdoms',
      settingsKey: SettingsKeys.gamePath3k,
    ),
    const GameDisplayInfo(
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

  // === File Picker Methods ===

  Future<void> _selectGamePath(String gameCode) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select ${_getGameName(gameCode)} Installation Folder',
    );
    if (result != null) {
      setState(() => _gamePathControllers[gameCode]?.text = result);
      await _saveGamePath(gameCode, result);
    }
  }

  Future<void> _selectWorkshopPath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Steam Workshop Folder',
    );
    if (result != null) {
      setState(() => _workshopPathController.text = result);
      await _saveWorkshopPath(result);
    }
  }

  Future<void> _selectRpfmPath() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select RPFM Executable',
      type: FileType.custom,
      allowedExtensions: ['exe'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      if (mounted) FluentToast.info(context, 'Validating RPFM executable...');

      final validationResult = await RpfmCliManager.validateRpfmPath(path);
      validationResult.when(
        ok: (version) {
          setState(() => _rpfmPathController.text = path);
          _saveRpfmPath(path);
          if (mounted) {
            FluentToast.success(context, 'RPFM v$version validated successfully');
          }
        },
        err: (error) {
          if (mounted) {
            FluentToast.error(context, 'Invalid RPFM executable: ${error.message}');
          }
        },
      );
    }
  }

  Future<void> _selectRpfmSchemaPath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select RPFM Schema Folder',
    );
    if (result != null) {
      setState(() => _rpfmSchemaPathController.text = result);
      await _saveRpfmSchemaPath(result);
    }
  }

  // === Auto-Detection Methods ===

  Future<void> _autoDetectGame(String gameCode) async {
    setState(() => _isDetecting = true);
    try {
      final result = await _detectionService.detectGame(gameCode);
      result.when(
        ok: (path) {
          if (path != null) {
            setState(() => _gamePathControllers[gameCode]?.text = path);
            _saveGamePath(gameCode, path);
            if (mounted) {
              FluentToast.success(context, 'Found ${_getGameName(gameCode)}');
            }
          } else {
            if (mounted) {
              FluentToast.warning(context, '${_getGameName(gameCode)} not found');
            }
          }
        },
        err: (error) {
          if (mounted) {
            FluentToast.error(context, 'Detection failed: ${error.message}');
          }
        },
      );
    } finally {
      setState(() => _isDetecting = false);
    }
  }

  Future<void> _autoDetectAllGames() async {
    setState(() => _isDetecting = true);
    try {
      final result = await _detectionService.detectAllGames();
      result.when(
        ok: (detectedGames) {
          setState(() {
            for (final entry in detectedGames.entries) {
              _gamePathControllers[entry.key]?.text = entry.value;
            }
          });
          for (final entry in detectedGames.entries) {
            _saveGamePath(entry.key, entry.value);
          }
          if (mounted) {
            if (detectedGames.isNotEmpty) {
              FluentToast.success(context, 'Found ${detectedGames.length} game(s)');
            } else {
              FluentToast.warning(context, 'No games found');
            }
          }
        },
        err: (error) {
          if (mounted) {
            FluentToast.error(context, 'Detection failed: ${error.message}');
          }
        },
      );
    } finally {
      setState(() => _isDetecting = false);
    }
  }

  Future<void> _autoDetectWorkshop() async {
    setState(() => _isDetecting = true);
    try {
      final result = await _detectionService.detectWorkshopFolder();
      result.when(
        ok: (path) {
          if (path != null) {
            setState(() => _workshopPathController.text = path);
            _saveWorkshopPath(path);
            if (mounted) FluentToast.success(context, 'Found Workshop folder');
          } else {
            if (mounted) FluentToast.warning(context, 'Workshop folder not found');
          }
        },
        err: (error) {
          if (mounted) {
            FluentToast.error(context, 'Detection failed: ${error.message}');
          }
        },
      );
    } finally {
      setState(() => _isDetecting = false);
    }
  }

  // === Save Methods ===

  Future<void> _saveGamePath(String gameCode, String path) async {
    try {
      await ref.read(generalSettingsProvider.notifier).updateGamePath(gameCode, path);
    } catch (e) {
      if (mounted) FluentToast.error(context, 'Error saving game path: $e');
    }
  }

  Future<void> _saveWorkshopPath(String path) async {
    try {
      await ref.read(generalSettingsProvider.notifier).updateWorkshopPath(path);
    } catch (e) {
      if (mounted) FluentToast.error(context, 'Error saving workshop path: $e');
    }
  }

  Future<void> _saveRpfmPath(String path) async {
    try {
      await ref.read(generalSettingsProvider.notifier).updateRpfmPath(path);
    } catch (e) {
      if (mounted) FluentToast.error(context, 'Error saving RPFM path: $e');
    }
  }

  Future<void> _saveRpfmSchemaPath(String path) async {
    try {
      await ref.read(generalSettingsProvider.notifier).updateRpfmSchemaPath(path);
    } catch (e) {
      if (mounted) FluentToast.error(context, 'Error saving RPFM schema path: $e');
    }
  }

  Future<void> _saveTargetLanguage(String language) async {
    try {
      await ref.read(generalSettingsProvider.notifier).updateDefaultTargetLanguage(language);
    } catch (e) {
      if (mounted) FluentToast.error(context, 'Error saving target language: $e');
    }
  }

  Future<void> _saveAutoUpdate(bool value) async {
    try {
      await ref.read(generalSettingsProvider.notifier).updateAutoUpdate(value);
    } catch (e) {
      if (mounted) FluentToast.error(context, 'Error saving auto-update setting: $e');
    }
  }

  // === Utility Methods ===

  String _getGameName(String gameCode) {
    return _games.firstWhere((g) => g.code == gameCode).name;
  }

  Future<void> _useDefaultRpfmSchemaPath() async {
    final username = io.Platform.environment['USERNAME'] ?? io.Platform.environment['USER'];
    if (username == null || username.isEmpty) {
      if (mounted) FluentToast.warning(context, 'Could not detect username');
      return;
    }

    final defaultPath = r'C:\Users\$username\AppData\Roaming\FrodoWazEre\rpfm\config\schemas'
        .replaceAll('\$username', username);

    setState(() => _rpfmSchemaPathController.text = defaultPath);
    await _saveRpfmSchemaPath(defaultPath);
    if (mounted) FluentToast.success(context, 'Default schema path configured');
  }

  Future<void> _testRpfmPath() async {
    final path = _rpfmPathController.text.trim();
    if (path.isEmpty) {
      if (mounted) FluentToast.warning(context, 'Please select an RPFM executable first');
      return;
    }

    if (mounted) FluentToast.info(context, 'Testing RPFM executable...');
    final validationResult = await RpfmCliManager.validateRpfmPath(path);
    validationResult.when(
      ok: (version) {
        if (mounted) {
          FluentToast.success(context, 'RPFM v$version is working correctly');
        }
      },
      err: (error) {
        if (mounted) FluentToast.error(context, 'RPFM test failed: ${error.message}');
      },
    );
  }

  Future<void> _resetToDefaults() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: const Text('Are you sure you want to reset all general settings to defaults?'),
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
      if (mounted) FluentToast.success(context, 'Settings reset to defaults');
    }
  }

  Future<void> _clearCache() async {
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

    if (confirm == true) {
      await ref.read(generalSettingsProvider.notifier).clearCache();
      if (mounted) FluentToast.success(context, 'Cache cleared successfully');
    }
  }

  // === Build Methods ===

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(generalSettingsProvider);

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error loading settings: $error')),
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
              _buildLanguageSection(),
              const SizedBox(height: 32),
              _buildApplicationSettingsSection(),
              const SizedBox(height: 32),
              _buildCacheSection(),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              FluentOutlinedButton(
                onPressed: _resetToDefaults,
                icon: const Icon(FluentIcons.arrow_reset_24_regular),
                child: const Text('Reset to Defaults'),
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
      _rpfmSchemaPathController.text = settings[SettingsKeys.rpfmSchemaPath] ?? '';
    }
    _targetLanguage = settings[SettingsKeys.defaultTargetLanguage] ?? 'es';
    _autoUpdate = settings[SettingsKeys.autoUpdate] == 'true';
  }

  Widget _buildLanguageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Language Preferences',
          subtitle: 'Default target language for new projects',
        ),
        const SizedBox(height: 16),
        _buildLanguageDropdown(),
      ],
    );
  }

  Widget _buildApplicationSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Application Settings',
          subtitle: 'General application preferences',
        ),
        const SizedBox(height: 16),
        _buildAutoUpdateCheckbox(),
      ],
    );
  }

  Widget _buildCacheSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Cache Management',
          subtitle: 'Manage application cache and temporary data',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FluentOutlinedButton(
              onPressed: _clearCache,
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
      ],
    );
  }

  Widget _buildSectionHeader(String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAutoDetectAllButton() {
    return Row(
      children: [
        FluentButton(
          onPressed: _isDetecting ? null : _autoDetectAllGames,
          icon: _isDetecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(FluentIcons.search_24_regular),
          child: Text(_isDetecting ? 'Detecting...' : 'Auto-Detect All Games'),
        ),
        const SizedBox(width: 8),
        Text(
          'Automatically find all installed Total War games',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildGamePathField(GameDisplayInfo game) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _gamePathControllers[game.code],
            decoration: InputDecoration(
              hintText: 'Path to ${game.name} installation...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (value) => _saveGamePath(game.code, value),
          ),
        ),
        const SizedBox(width: 8),
        SettingsActionButton.detect(
          onPressed: () => _autoDetectGame(game.code),
          isDetecting: _isDetecting,
        ),
        const SizedBox(width: 4),
        SettingsActionButton.browse(onPressed: () => _selectGamePath(game.code)),
      ],
    );
  }

  Widget _buildWorkshopPathField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(FluentIcons.folder_24_regular, size: 16),
            const SizedBox(width: 8),
            Text(
              'Steam Workshop Base Folder',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _workshopPathController,
                decoration: InputDecoration(
                  hintText: r'C:\Program Files (x86)\Steam\steamapps\workshop\content',
                  helperText: 'Game IDs (e.g., 1142710 for Warhammer III) will be added automatically',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: _saveWorkshopPath,
              ),
            ),
            const SizedBox(width: 8),
            SettingsActionButton.detect(
              onPressed: _autoDetectWorkshop,
              isDetecting: _isDetecting,
            ),
            const SizedBox(width: 4),
            SettingsActionButton.browse(onPressed: _selectWorkshopPath),
          ],
        ),
      ],
    );
  }

  Widget _buildRpfmPathField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(FluentIcons.wrench_24_regular, size: 16),
            const SizedBox(width: 8),
            Text(
              'RPFM Executable',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _rpfmPathController,
                decoration: InputDecoration(
                  hintText: r'C:\Path\To\rpfm_cli.exe',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: _saveRpfmPath,
              ),
            ),
            const SizedBox(width: 8),
            SettingsActionButton.test(onPressed: _testRpfmPath),
            const SizedBox(width: 4),
            SettingsActionButton.browse(onPressed: _selectRpfmPath),
          ],
        ),
      ],
    );
  }

  Widget _buildRpfmSchemaPathField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(FluentIcons.database_24_regular, size: 16),
            const SizedBox(width: 8),
            Text(
              'RPFM Schema Folder',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Folder containing RPFM schema files (e.g., schema_wh3.ron)',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _rpfmSchemaPathController,
                decoration: InputDecoration(
                  hintText: r'C:\Users\USERNAME\AppData\Roaming\FrodoWazEre\rpfm\config\schemas',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: _saveRpfmSchemaPath,
              ),
            ),
            const SizedBox(width: 8),
            SettingsActionButton.defaultPath(onPressed: _useDefaultRpfmSchemaPath),
            const SizedBox(width: 4),
            SettingsActionButton.browse(onPressed: _selectRpfmSchemaPath),
          ],
        ),
      ],
    );
  }

  Widget _buildLanguageDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Default Target Language',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _targetLanguage,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: const [
            DropdownMenuItem(value: 'en', child: Text('English')),
            DropdownMenuItem(value: 'de', child: Text('German (Deutsch)')),
            DropdownMenuItem(value: 'es', child: Text('Spanish (Español)')),
            DropdownMenuItem(value: 'fr', child: Text('French (Français)')),
            DropdownMenuItem(value: 'ru', child: Text('Russian (Русский)')),
            DropdownMenuItem(value: 'zh', child: Text('Chinese (中文)')),
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

  Widget _buildAutoUpdateCheckbox() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final newValue = !_autoUpdate;
          setState(() => _autoUpdate = newValue);
          _saveAutoUpdate(newValue);
        },
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
}
