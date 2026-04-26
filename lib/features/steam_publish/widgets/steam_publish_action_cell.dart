import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/platform/game_launcher_opener.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/fluent/fluent_toast.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../providers/publish_staging_provider.dart';
import '../providers/steam_publish_providers.dart';
import 'pack_language_dialog.dart';

/// State-machine action cell rendered in the action column of the Steam
/// Publish list.
///
/// Rendering modes:
///
/// - A₀ — No pack, no Workshop id → "Generate pack".
/// - A₁ — No pack, has Workshop id → "Generate pack" + "Open in Steam".
/// - B — Pack + no Workshop id → "Update" (disabled) + "Open launcher".
/// - C — Pack + Workshop id → "Update" + "Open in Steam".
///
/// Editing the Workshop id lives in [SteamIdCell] in the dedicated Steam ID
/// column — the action cell never owns the inline editor anymore.
class SteamActionCell extends ConsumerStatefulWidget {
  final PublishableItem item;

  const SteamActionCell({super.key, required this.item});

  @override
  ConsumerState<SteamActionCell> createState() => _SteamActionCellState();
}

class _SteamActionCellState extends ConsumerState<SteamActionCell> {
  bool _isGenerating = false;
  double _generateProgress = 0.0;
  String? _generateStep;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasPack = item.hasPack;
    final hasPublishedId = item.publishedSteamId != null &&
        item.publishedSteamId!.isNotEmpty;

    if (_isGenerating) {
      return _buildGenerateProgress(context);
    }

    if (!hasPack) {
      // State A₀: Generate pack alone.
      // State A₁: Generate pack + Open in Steam.
      if (hasPublishedId) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(child: _buildGenerateButton(context, padded: false)),
              const SizedBox(width: 6),
              SmallTextButton(
                label: t.steamPublish.actionCell.buttons.openInWorkshop,
                tooltip: t.steamPublish.actionCell.tooltips.openInWorkshop,
                icon: FluentIcons.open_24_regular,
                onTap: _openWorkshop,
              ),
            ],
          ),
        );
      }
      return _buildGenerateButton(context);
    }

    // State B: pack but no Workshop id — disabled Update + launcher.
    if (!hasPublishedId) {
      return _buildPublishButtons(context, updateDisabled: true);
    }

    // State C: pack + Workshop id — Update + Open in Steam.
    return _buildPublishButtons(context, updateDisabled: false);
  }

  // ---------------------------------------------------------------------------
  // State A: no pack — Generate pack / Open compilation.
  // ---------------------------------------------------------------------------

  Widget _buildGenerateButton(BuildContext context, {bool padded = true}) {
    final tokens = context.tokens;
    final item = widget.item;
    final core = Tooltip(
      message: item.isCompilation
          ? t.steamPublish.actionCell.tooltips.openCompilationToGenerate
          : t.steamPublish.actionCell.tooltips.generatePackFile,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _handleGeneratePack(context),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.accentBg,
              border: Border.all(color: tokens.accent),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.isCompilation
                        ? FluentIcons.open_24_regular
                        : FluentIcons.box_arrow_up_24_regular,
                    size: 14,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.isCompilation
                        ? t.steamPublish.actionCell.buttons.openCompilation
                        : t.steamPublish.actionCell.buttons.generatePack,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: tokens.fontBody.copyWith(
                      fontSize: 12,
                      color: tokens.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!padded) return core;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: core,
    );
  }

  /// Opens the item's published Workshop page in the default browser.
  ///
  /// The caller is expected to guard on `publishedSteamId != null` before
  /// invoking.
  void _openWorkshop() {
    final workshopId = widget.item.publishedSteamId;
    if (workshopId == null || workshopId.isEmpty) return;
    launchUrl(
      Uri.parse(
        'https://steamcommunity.com/sharedfiles/filedetails/?id=$workshopId',
      ),
    );
  }

  Widget _buildGenerateProgress(BuildContext context) {
    final tokens = context.tokens;
    final percent = (_generateProgress * 100).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.accent,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _generateStep ?? t.steamPublish.actionCell.progress.generating,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.fontBody.copyWith(
                    fontSize: 11.5,
                    color: tokens.textMid,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$percent%',
                style: tokens.fontMono.copyWith(
                  fontSize: 11,
                  color: tokens.textDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radiusXs),
            child: LinearProgressIndicator(
              value: _generateProgress,
              minHeight: 3,
              backgroundColor: tokens.panel,
              valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleGeneratePack(BuildContext context) async {
    final item = widget.item;

    if (item is CompilationPublishItem) {
      context.goPackCompilation();
      return;
    }

    if (item is ProjectPublishItem) {
      final languages = item.languageCodes;
      if (languages.isEmpty) {
        FluentToast.warning(
          context,
          t.steamPublish.actionCell.toasts.noLanguages,
        );
        return;
      }

      List<String> selectedLanguages;
      if (languages.length > 1) {
        final result = await PackLanguageDialog.show(
          context,
          availableLanguages: languages,
        );
        if (result == null) return;
        selectedLanguages = result;
      } else {
        selectedLanguages = languages;
      }

      await _generatePackForProject(item, selectedLanguages);
    }
  }

  Future<void> _generatePackForProject(
    ProjectPublishItem item,
    List<String> languageCodes,
  ) async {
    if (!mounted) return;
    setState(() {
      _isGenerating = true;
      _generateProgress = 0.0;
      _generateStep = t.steamPublish.actionCell.progress.preparing;
    });

    try {
      final orchestrator = ref.read(exportOrchestratorServiceProvider);
      final result = await orchestrator.exportToPack(
        projectId: item.project.id,
        languageCodes: languageCodes,
        outputPath: '',
        validatedOnly: false,
        onProgress: (step, progress, {currentLanguage, currentIndex, total}) {
          if (mounted) {
            setState(() {
              _generateProgress = progress;
              _generateStep = _humanizeStep(step, currentLanguage);
            });
          }
        },
      );

      if (!mounted) return;
      if (result.isOk) {
        FluentToast.success(
          context,
          t.steamPublish.actionCell.toasts.packGenerated(count: result.value.entryCount),
        );
        ref.invalidate(publishableItemsProvider);
      } else {
        FluentToast.error(
          context,
          t.steamPublish.actionCell.toasts.packFailed(error: result.error),
        );
      }
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, t.steamPublish.actionCell.toasts.packError(error: e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generateProgress = 0.0;
          _generateStep = null;
        });
      }
    }
  }

  String _humanizeStep(String step, String? language) {
    final langSuffix = language != null ? ' ($language)' : '';
    switch (step) {
      case 'preparingData':
        return t.steamPublish.actionCell.progress.steps.preparingData;
      case 'generatingLocFiles':
        return t.steamPublish.actionCell.progress.steps.generatingLocFiles(lang: langSuffix);
      case 'creatingPack':
        return t.steamPublish.actionCell.progress.steps.creatingPack(lang: langSuffix);
      case 'generatingImage':
        return t.steamPublish.actionCell.progress.steps.generatingPreview;
      case 'finalizing':
        return t.steamPublish.actionCell.progress.steps.finalizing;
      case 'completed':
        return t.steamPublish.actionCell.progress.steps.completed;
      default:
        return step;
    }
  }

  /// Launches the in-game Workshop publisher for Total War: WARHAMMER III.
  ///
  /// The app id is hard-coded to match parity with the workshop publish screen
  /// (single-game scope). If Steam cannot handle the `steam://run/...` URI the
  /// user is informed via a warning toast rather than silently failing.
  Future<void> _openLauncher() async {
    final ok = await openGameLauncher('1142710'); // TW:WH3
    if (!ok && mounted) {
      FluentToast.warning(
        context,
        t.steamPublish.actionCell.toasts.steamNotFound,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // State C: pack + Workshop id — Update / Open in Steam.
  // State B: pack + no Workshop id — Update (disabled) / Open launcher.
  // ---------------------------------------------------------------------------

  Widget _buildPublishButtons(
    BuildContext context, {
    required bool updateDisabled,
  }) {
    final tokens = context.tokens;

    final updateFg = updateDisabled ? tokens.textFaint : tokens.accent;
    final updateBorder = updateDisabled ? tokens.border : tokens.accent;
    final updateBg = updateDisabled ? tokens.panel2 : tokens.accentBg;
    final updateTooltip = updateDisabled
        ? t.steamPublish.actionCell.tooltips.setIdFirst
        : t.steamPublish.actionCell.tooltips.updateWorkshop;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: updateTooltip,
              waitDuration: const Duration(milliseconds: 400),
              child: MouseRegion(
                cursor: updateDisabled
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: updateDisabled
                      ? null
                      : () {
                          ref
                              .read(singlePublishStagingProvider.notifier)
                              .set(widget.item);
                          context.goWorkshopPublishSingle();
                        },
                  child: Container(
                    height: 28,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: updateBg,
                      border: Border.all(color: updateBorder),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            FluentIcons.cloud_arrow_up_24_regular,
                            size: 14,
                            color: updateFg,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            t.steamPublish.actionCell.buttons.update,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.clip,
                            style: tokens.fontBody.copyWith(
                              fontSize: 12,
                              color: updateFg,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (updateDisabled)
            _iconButton(
              icon: FluentIcons.play_24_regular,
              tooltip: t.steamPublish.actionCell.tooltips.openGameLauncher,
              onTap: _openLauncher,
            )
          else
            _iconButton(
              icon: FluentIcons.open_24_regular,
              tooltip: t.steamPublish.actionCell.tooltips.openInWorkshop,
              onTap: _openWorkshop,
            ),
        ],
      ),
    );
  }

  // Small square icon button used for inline actions.
  Widget _iconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return Builder(
      builder: (context) {
        final tokens = context.tokens;
        return Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 400),
          child: MouseRegion(
            cursor: onTap != null
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.panel2,
                  border: Border.all(color: tokens.border),
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
                child: Icon(icon, size: 14, color: tokens.textMid),
              ),
            ),
          ),
        );
      },
    );
  }
}
