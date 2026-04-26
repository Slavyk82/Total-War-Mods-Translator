import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:path/path.dart' as path;

import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/wizard/labeled_field.dart';
import 'package:twmt/widgets/wizard/readonly_field.dart';
import 'package:twmt/widgets/wizard/token_text_field.dart';

import '../../../../models/domain/game_installation.dart';
import '../../../../utils/game_label.dart';
import '../../providers/projects_screen_providers.dart';
import 'project_creation_state.dart';

/// Step 1: Basic project information.
///
/// Collects project name and game selection.
/// If a detected mod is provided, this step is auto-filled and skipped.
///
/// Retokenised (Plan 5d · Task 6): [TokenTextField] + [LabeledField] inputs,
/// [ReadonlyField] rows for auto-filled mod metadata, token-themed dropdown.
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
        widget.state.modSteamIdController.text =
            widget.state.workshopMod!.workshopId;

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
    final tokens = context.tokens;
    final hasDetectedMod = widget.state.detectedMod != null;

    if (_isLoadingModData) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
            ),
          ),
        ),
      );
    }

    // Auto-filled mod context: show read-only summary rows.
    if (hasDetectedMod) {
      return Form(
        key: widget.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.projects.createProject.basicInfo.descriptionAutoFilled,
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.textDim,
              ),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: t.projects.createProject.basicInfo.fieldProjectName,
              child: TokenTextField(
                controller: widget.state.nameController,
                hint: t.projects.createProject.basicInfo.hintProjectName,
                enabled: true,
              ),
            ),
            const SizedBox(height: 12),
            ReadonlyField(
              label: t.projects.createProject.basicInfo.fieldSourcePack,
              value: widget.state.sourceFileController.text,
            ),
            const SizedBox(height: 12),
            ReadonlyField(
              label: t.projects.createProject.basicInfo.fieldWorkshopId,
              value: widget.state.modSteamIdController.text,
            ),
          ],
        ),
      );
    }

    // Manual entry: name + game dropdown.
    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.projects.createProject.basicInfo.descriptionManual,
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.textDim,
            ),
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: t.projects.createProject.basicInfo.fieldProjectName,
            child: TokenTextField(
              controller: widget.state.nameController,
              hint: t.projects.createProject.basicInfo.hintProjectName,
              enabled: true,
            ),
          ),
          const SizedBox(height: 12),
          LabeledField(
            label: t.projects.createProject.basicInfo.fieldGame,
            child: _buildGameSelection(tokens),
          ),
        ],
      ),
    );
  }

  Widget _buildGameSelection(TwmtThemeTokens tokens) {
    final gamesAsync = ref.watch(allGameInstallationsProvider);

    return gamesAsync.when(
      data: (games) => _buildGameDropdown(games, tokens),
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
          ),
        ),
      ),
      error: (err, _) => Text(
        t.projects.createProject.basicInfo.errorLoadingGames(error: err.toString()),
        style: tokens.fontBody.copyWith(
          fontSize: 13,
          color: tokens.err,
        ),
      ),
    );
  }

  Widget _buildGameDropdown(
      List<GameInstallation> games, TwmtThemeTokens tokens) {
    final bodyStyle = tokens.fontBody.copyWith(
      fontSize: 13,
      color: tokens.text,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.panel2,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: widget.state.selectedGameId,
          hint: Text(
            t.projects.createProject.basicInfo.hintGame,
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.textFaint,
            ),
          ),
          isExpanded: true,
          dropdownColor: tokens.panel2,
          iconEnabledColor: tokens.textMid,
          icon: const Icon(FluentIcons.chevron_down_24_regular, size: 16),
          style: bodyStyle,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          items: games.map((game) {
            return DropdownMenuItem(
              value: game.id,
              child: Text(gameLabel(game.gameName), style: bodyStyle),
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
