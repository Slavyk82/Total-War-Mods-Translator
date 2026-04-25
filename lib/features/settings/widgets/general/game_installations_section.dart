import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:twmt/i18n/strings.g.dart';
import '../../models/game_display_info.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/fluent/fluent_expander.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/utils/game_label.dart';
import '../../providers/settings_providers.dart';
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
                header: gameLabel(game.name),
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
    final tokens = context.tokens;
    return Row(
      children: [
        SmallTextButton(
          label: _isDetecting ? 'Detecting...' : 'Auto-Detect All Games',
          icon: FluentIcons.search_24_regular,
          tooltip: t.tooltips.settings.detectAllGames,
          onTap: _isDetecting ? null : _autoDetectAllGames,
        ),
        const SizedBox(width: 8),
        Text(
          'Automatically find all installed Total War games',
          style: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.text,
          ),
        ),
      ],
    );
  }

  Widget _buildGamePathField(GameDisplayInfo game) {
    final tokens = context.tokens;
    return Row(
      children: [
        SmallTextButton(
          label: 'Detect',
          icon: FluentIcons.search_24_regular,
          tooltip: t.tooltips.settings.detectGame,
          onTap: _isDetecting ? null : () => _autoDetectGame(game.code),
        ),
        const SizedBox(width: 6),
        SmallTextButton(
          label: 'Browse',
          icon: FluentIcons.folder_open_24_regular,
          tooltip: t.tooltips.settings.browsePath,
          onTap: () => _selectGamePath(game.code),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: widget.gamePathControllers[game.code],
            decoration: InputDecoration(
              hintText: 'Path to ${gameLabel(game.name)} installation...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
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
      final detectionService = ref.read(steamDetectionServiceProvider);
      final result = await detectionService.detectGame(gameCode);
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
      final detectionService = ref.read(steamDetectionServiceProvider);
      final result = await detectionService.detectAllGames();
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
    return gameLabel(game.name);
  }
}
