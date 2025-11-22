import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import '../../../../widgets/fluent/fluent_widgets.dart';
import '../../../../models/domain/game_installation.dart';
import '../../providers/projects_screen_providers.dart';
import 'project_creation_state.dart';

/// Step 1: Basic project information.
///
/// Collects project name and game selection.
/// If a detected mod is provided, this step is auto-filled and skipped.
class StepBasicInfo extends ConsumerStatefulWidget {
  final ProjectCreationState state;
  final GlobalKey<FormState> formKey;

  const StepBasicInfo({
    super.key,
    required this.state,
    required this.formKey,
  });

  @override
  ConsumerState<StepBasicInfo> createState() => _StepBasicInfoState();
}

class _StepBasicInfoState extends ConsumerState<StepBasicInfo> {
  bool _isLoadingModData = false;

  @override
  void initState() {
    super.initState();
    // Load mod data if a detected mod is provided
    if (widget.state.detectedMod != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadModData();
      });
    }
  }

  Future<void> _loadModData() async {
    if (widget.state.detectedMod == null || widget.state.workshopMod != null) {
      return;
    }

    setState(() => _isLoadingModData = true);

    try {
      final mod = widget.state.detectedMod!;

      // Load workshop mod from database
      final workshopRepo = ref.read(workshopModRepositoryProvider);
      final modResult = await workshopRepo.getByWorkshopId(mod.workshopId);

      if (modResult.isOk) {
        widget.state.workshopMod = modResult.unwrap();
        widget.state.modSteamIdController.text = widget.state.workshopMod!.workshopId;

        // Find game installation matching the mod's appId
        final games = await ref.read(allGameInstallationsProvider.future);
        final matchingGame = games.firstWhere(
          (game) =>
              game.steamAppId != null &&
              int.tryParse(game.steamAppId!) == widget.state.workshopMod!.appId,
          orElse: () => games.isNotEmpty
              ? games.first
              : throw StateError('No games found'),
        );
        widget.state.selectedGameId = matchingGame.id;

        // Set output folder to game's data folder
        if (matchingGame.installationPath != null) {
          widget.state.outputFileController.text =
              path.join(matchingGame.installationPath!, 'data');
        }
      }
    } catch (e) {
      // If mod not found in DB, still use detected mod data
      // Fields are already pre-filled in ProjectCreationState constructor
    } finally {
      if (mounted) {
        setState(() => _isLoadingModData = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDetectedMod = widget.state.detectedMod != null;

    if (_isLoadingModData) {
      return const Center(child: CircularProgressIndicator());
    }

    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Project name
          Text(
            'Project Name',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          FluentTextField(
            controller: widget.state.nameController,
            decoration: InputDecoration(
              hintText: 'Enter project name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 16),

          // Game selection - only show if no detected mod
          if (!hasDetectedMod) ...[
            Text(
              'Game',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _buildGameSelection(theme),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildGameSelection(ThemeData theme) {
    final gamesAsync = ref.watch(allGameInstallationsProvider);

    return gamesAsync.when(
      data: (games) => _buildGameDropdown(games, theme),
      loading: () => const CircularProgressIndicator(),
      error: (err, stack) => Text('Error loading games: $err'),
    );
  }

  Widget _buildGameDropdown(List<GameInstallation> games, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: widget.state.selectedGameId,
          hint: const Text('Select a game'),
          isExpanded: true,
          items: games.map((game) {
            return DropdownMenuItem(
              value: game.id,
              child: Text(game.gameName),
            );
          }).toList(),
          onChanged: (value) {
            setState(() => widget.state.selectedGameId = value);
          },
        ),
      ),
    );
  }
}
