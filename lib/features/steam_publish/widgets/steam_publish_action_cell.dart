import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/fluent/fluent_toast.dart';

import '../providers/publish_staging_provider.dart';
import '../providers/steam_publish_providers.dart';
import 'pack_language_dialog.dart';

/// State-machine action cell rendered in column 6 of the Steam Publish list.
///
/// Three rendering modes:
///
/// - No pack → "Generate pack" (project) or "Open compilation" (compilation).
/// - Pack + no Workshop id → inline Steam-id input + save.
/// - Pack + Workshop id → "Update" + "Open in Steam" + edit-id buttons.
class SteamActionCell extends ConsumerStatefulWidget {
  final PublishableItem item;

  const SteamActionCell({super.key, required this.item});

  @override
  ConsumerState<SteamActionCell> createState() => _SteamActionCellState();
}

class _SteamActionCellState extends ConsumerState<SteamActionCell> {
  final TextEditingController _steamIdController = TextEditingController();
  bool _isSavingSteamId = false;
  bool _isEditingSteamId = false;
  bool _isGenerating = false;
  double _generateProgress = 0.0;
  String? _generateStep;

  @override
  void dispose() {
    _steamIdController.dispose();
    super.dispose();
  }

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
      return _buildGenerateButton(context);
    }

    if (!hasPublishedId || _isEditingSteamId) {
      return _buildSteamIdInput(context);
    }

    return _buildPublishButtons(context);
  }

  // ---------------------------------------------------------------------------
  // State A: no pack — Generate pack / Open compilation.
  // ---------------------------------------------------------------------------

  Widget _buildGenerateButton(BuildContext context) {
    final tokens = context.tokens;
    final item = widget.item;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message: item.isCompilation
            ? 'Open compilation editor to generate'
            : 'Generate .pack file',
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
                  Flexible(
                    child: Text(
                      item.isCompilation
                          ? 'Open compilation'
                          : 'Generate pack',
                      overflow: TextOverflow.ellipsis,
                      style: tokens.fontBody.copyWith(
                        fontSize: 12,
                        color: tokens.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
                  _generateStep ?? 'Generating...',
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
          'No languages configured for this project.',
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
      _generateStep = 'Preparing...';
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
          'Pack generated: ${result.value.entryCount} entries',
        );
        ref.invalidate(publishableItemsProvider);
      } else {
        FluentToast.error(
          context,
          'Failed to generate pack: ${result.error}',
        );
      }
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, 'Error generating pack: $e');
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
        return 'Preparing data...';
      case 'generatingLocFiles':
        return 'Generating .loc files$langSuffix';
      case 'creatingPack':
        return 'Creating .pack$langSuffix';
      case 'generatingImage':
        return 'Generating preview image...';
      case 'finalizing':
        return 'Finalizing...';
      case 'completed':
        return 'Completed';
      default:
        return step;
    }
  }

  // ---------------------------------------------------------------------------
  // State B: pack, no/editing Workshop id — inline input.
  // ---------------------------------------------------------------------------

  Widget _buildSteamIdInput(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: _steamIdController,
                enabled: !_isSavingSteamId,
                style: tokens.fontMono.copyWith(
                  fontSize: 12,
                  color: tokens.text,
                ),
                decoration: InputDecoration(
                  hintText: 'Workshop id...',
                  hintStyle: tokens.fontMono.copyWith(
                    fontSize: 12,
                    color: tokens.textFaint,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: tokens.panel2,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    borderSide: BorderSide(color: tokens.accent),
                  ),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _saveSteamId(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _iconButton(
            icon: _isSavingSteamId ? null : FluentIcons.save_24_regular,
            tooltip: 'Save Workshop id',
            onTap: _isSavingSteamId ? null : _saveSteamId,
            busy: _isSavingSteamId,
            accent: true,
          ),
          if (_isEditingSteamId) ...[
            const SizedBox(width: 4),
            _iconButton(
              icon: FluentIcons.dismiss_24_regular,
              tooltip: 'Cancel',
              onTap: () {
                _steamIdController.clear();
                setState(() => _isEditingSteamId = false);
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _saveSteamId() async {
    final steamId = _steamIdController.text.trim();
    if (steamId.isEmpty) return;

    setState(() => _isSavingSteamId = true);

    try {
      final item = widget.item;
      if (item is ProjectPublishItem) {
        final projectRepo = ref.read(projectRepositoryProvider);
        final projectResult = await projectRepo.getById(item.project.id);
        if (projectResult.isOk) {
          final updated = projectResult.value.copyWith(
            publishedSteamId: steamId,
            updatedAt: projectResult.value.updatedAt,
          );
          await projectRepo.update(updated);
        }
      } else if (item is CompilationPublishItem) {
        final compilationRepo = ref.read(compilationRepositoryProvider);
        await compilationRepo.updateAfterPublish(
          item.compilation.id,
          steamId,
          item.publishedAt ?? 0,
        );
      }
      if (mounted) {
        _isEditingSteamId = false;
        ref.invalidate(publishableItemsProvider);
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingSteamId = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // State C: pack + Workshop id — Update / Open in Steam / Edit id.
  // ---------------------------------------------------------------------------

  Widget _buildPublishButtons(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: 'Update existing Workshop item',
              waitDuration: const Duration(milliseconds: 400),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
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
                      color: tokens.accentBg,
                      border: Border.all(color: tokens.accent),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          FluentIcons.cloud_arrow_up_24_regular,
                          size: 14,
                          color: tokens.accent,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Update',
                            overflow: TextOverflow.ellipsis,
                            style: tokens.fontBody.copyWith(
                              fontSize: 12,
                              color: tokens.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _iconButton(
            icon: FluentIcons.open_24_regular,
            tooltip: 'Open in Steam Workshop',
            onTap: () {
              final workshopId = widget.item.publishedSteamId!;
              launchUrl(
                Uri.parse(
                  'https://steamcommunity.com/sharedfiles/filedetails/?id=$workshopId',
                ),
              );
            },
          ),
          const SizedBox(width: 4),
          _iconButton(
            icon: FluentIcons.edit_24_regular,
            tooltip: 'Edit Workshop id',
            onTap: () {
              _steamIdController.text = widget.item.publishedSteamId ?? '';
              setState(() => _isEditingSteamId = true);
            },
          ),
        ],
      ),
    );
  }

  // Small square icon button used for inline actions.
  Widget _iconButton({
    required IconData? icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool busy = false,
    bool accent = false,
  }) {
    return Builder(
      builder: (context) {
        final tokens = context.tokens;
        final fg = accent ? tokens.accent : tokens.textMid;
        final borderColor = accent ? tokens.accent : tokens.border;
        final bg = accent ? tokens.accentBg : tokens.panel2;
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
                  color: bg,
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
                child: busy
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: fg,
                        ),
                      )
                    : (icon != null
                        ? Icon(icon, size: 14, color: fg)
                        : const SizedBox.shrink()),
              ),
            ),
          ),
        );
      },
    );
  }
}
