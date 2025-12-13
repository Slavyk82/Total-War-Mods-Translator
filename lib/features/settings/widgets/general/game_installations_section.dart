import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:twmt/config/tooltip_strings.dart';
import '../../models/game_display_info.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/fluent/fluent_expander.dart';
import 'package:twmt/services/steam/steam_detection_service.dart';
import '../../providers/settings_providers.dart';
import 'settings_action_button.dart';
import 'settings_section_header.dart';

/// Game installations configuration section.
///
/// Allows users to configure paths to their Total War game installations
/// with auto-detection and manual browse capabilities.
class GameInstallationsSection extends ConsumerStatefulWidget {
  final Map<String, TextEditingController> gamePathControllers;
  final List<GameDisplayInfo> games;

  const GameInstallationsSection({
    super.key,
    required this.gamePathControllers,
    required this.games,
  });

  @override
  ConsumerState<GameInstallationsSection> createState() =>
      _GameInstallationsSectionState();
}

class _GameInstallationsSectionState
    extends ConsumerState<GameInstallationsSection> {
  bool _isDetecting = false;
  final SteamDetectionService _detectionService = SteamDetectionService();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Game Installations',
          subtitle: 'Configure paths to your Total War games',
        ),
        const SizedBox(height: 8),
        _buildAutoDetectAllButton(),
        const SizedBox(height: 16),
        ...widget.games.map((game) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FluentExpander(
                header: game.name,
                icon: FluentIcons.games_24_regular,
                initiallyExpanded:
                    (widget.gamePathControllers[game.code]?.text ?? '')
                        .isNotEmpty,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildGamePathField(game),
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildAutoDetectAllButton() {
    return Row(
      children: [
        Tooltip(
          message: TooltipStrings.settingsDetectAllGames,
          waitDuration: const Duration(milliseconds: 500),
          child: FluentButton(
            onPressed: _isDetecting ? null : _autoDetectAllGames,
            icon: _isDetecting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(FluentIcons.search_24_regular),
            child:
                Text(_isDetecting ? 'Detecting...' : 'Auto-Detect All Games'),
          ),
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
        SettingsActionButton.detect(
          onPressed: () => _autoDetectGame(game.code),
          isDetecting: _isDetecting,
          tooltip: TooltipStrings.settingsDetectGame,
        ),
        const SizedBox(width: 4),
        SettingsActionButton.browse(
          onPressed: () => _selectGamePath(game.code),
          tooltip: TooltipStrings.settingsBrowsePath,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: widget.gamePathControllers[game.code],
            decoration: InputDecoration(
              hintText: 'Path to ${game.name} installation...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (value) => _saveGamePath(game.code, value),
          ),
        ),
      ],
    );
  }

  // === File Picker Methods ===

  Future<void> _selectGamePath(String gameCode) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select ${_getGameName(gameCode)} Installation Folder',
    );
    if (result != null) {
      setState(() => widget.gamePathControllers[gameCode]?.text = result);
      await _saveGamePath(gameCode, result);
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
            setState(() =>
                widget.gamePathControllers[gameCode]?.text = path);
            _saveGamePath(gameCode, path);
            if (mounted) {
              FluentToast.success(
                  context, 'Found ${_getGameName(gameCode)}');
            }
          } else {
            if (mounted) {
              FluentToast.warning(
                  context, '${_getGameName(gameCode)} not found');
            }
          }
        },
        err: (error) {
          if (mounted) {
            FluentToast.error(
                context, 'Detection failed: ${error.message}');
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
              widget.gamePathControllers[entry.key]?.text = entry.value;
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

  // === Save Methods ===

  Future<void> _saveGamePath(String gameCode, String path) async {
    try {
      await ref
          .read(generalSettingsProvider.notifier)
          .updateGamePath(gameCode, path);
    } catch (e) {
      if (mounted) FluentToast.error(context, 'Error saving game path: $e');
    }
  }

  // === Helper Methods ===

  String _getGameName(String code) {
    final game = widget.games.firstWhere(
      (g) => g.code == code,
      orElse: () => widget.games.first,
    );
    return game.name;
  }
}
