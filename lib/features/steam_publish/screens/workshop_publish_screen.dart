import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/wizard/dynamic_zone_panel.dart';
import 'package:twmt/widgets/wizard/form_section.dart';
import 'package:twmt/widgets/wizard/labeled_field.dart';
import 'package:twmt/widgets/wizard/readonly_field.dart';
import 'package:twmt/widgets/wizard/sticky_form_panel.dart';
import 'package:twmt/widgets/wizard/summary_box.dart';
import 'package:twmt/widgets/wizard/token_text_field.dart';
import 'package:twmt/widgets/wizard/wizard_screen_layout.dart';

import '../../../features/settings/providers/settings_providers.dart'
    hide settingsServiceProvider;
import '../../../providers/shared/service_providers.dart';
import '../../../services/steam/models/workshop_publish_params.dart';
import '../../../services/steam/steamcmd_manager.dart';
import '../../../widgets/fluent/fluent_toast.dart';
import '../providers/publish_staging_provider.dart';
import '../providers/steam_publish_providers.dart';
import '../providers/workshop_publish_notifier.dart';
import '../widgets/steam_guard_dialog.dart';
import '../widgets/steam_login_dialog.dart';
import '../widgets/steamcmd_install_dialog.dart';
import '../widgets/workshop_publish_settings_dialog.dart';

/// Workshop Publish single screen (§7.5 wizard archetype).
///
/// Layout: [WizardScreenLayout] = [DetailScreenToolbar] +
/// [StickyFormPanel] (Publication + Pack sections, Will-update summary,
/// Cancel/Update actions) + [DynamicZonePanel] wrapping an
/// [AnimatedSwitcher] that flips between preview / progress / done / failed
/// sub-views.
///
/// Uses [singlePublishStagingProvider] to resolve the [PublishableItem].
/// Consumes [workshopPublishProvider] for the publish phase + progress +
/// log buffer. Preserves Steam Guard, login, and steamcmd-install dialogs
/// plus the template-loaded Workshop settings.
class WorkshopPublishScreen extends ConsumerStatefulWidget {
  const WorkshopPublishScreen({super.key});

  @override
  ConsumerState<WorkshopPublishScreen> createState() =>
      _WorkshopPublishScreenState();
}

class _WorkshopPublishScreenState
    extends ConsumerState<WorkshopPublishScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _changeNoteController;
  WorkshopVisibility _visibility = WorkshopVisibility.public_;
  DateTime? _uploadStartTime;
  Timer? _elapsedTimer;
  bool _showingSteamGuardDialog = false;
  late final WorkshopPublishNotifier _publishNotifier;
  PublishableItem? _item;

  bool get _isUpdate =>
      _item != null &&
      _item!.hasPack &&
      _item!.publishedSteamId != null &&
      _item!.publishedSteamId!.isNotEmpty;

  String get _packFilePath => _item!.outputPath;

  String? get _previewImagePath {
    final packPath = _packFilePath;
    if (packPath.isEmpty) return null;
    final imagePath =
        '${packPath.substring(0, packPath.lastIndexOf('.'))}.png';
    if (File(imagePath).existsSync()) return imagePath;
    return null;
  }

  @override
  void initState() {
    super.initState();
    _item = ref.read(singlePublishStagingProvider);
    _publishNotifier = ref.read(workshopPublishProvider.notifier);
    Future.microtask(() => _publishNotifier.reset());

    _titleController = TextEditingController(
      text: _item?.displayName ?? '',
    );
    _descriptionController = TextEditingController();
    _changeNoteController = TextEditingController();
    _loadTemplates();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    _changeNoteController.dispose();
    // Guard against missing ServiceLocator registration (tests) — the
    // notifier reads services that may not be registered in pure widget
    // tests.
    try {
      _publishNotifier.silentCleanup();
    } catch (_) {
      // Ignore — nothing to clean up in a test context.
    }
    super.dispose();
  }

  String _applyTemplate(String template, String modName) {
    if (template.isEmpty) return '';
    return template.replaceAll('\$modName', modName);
  }

  Future<void> _loadTemplates() async {
    // Guard against missing ServiceLocator registration (tests) so the
    // fire-and-forget call doesn't surface a ProviderException in the UI.
    final String titleTemplate;
    final String descTemplate;
    final String visibilityName;
    try {
      final service = ref.read(settingsServiceProvider);
      titleTemplate =
          await service.getString(SettingsKeys.workshopTitleTemplate);
      descTemplate =
          await service.getString(SettingsKeys.workshopDescriptionTemplate);
      visibilityName =
          await service.getString(SettingsKeys.workshopDefaultVisibility);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final modName = _item?.displayName ?? '';
    if (titleTemplate.isNotEmpty) {
      _titleController.text = _applyTemplate(titleTemplate, modName);
    }
    if (descTemplate.isNotEmpty) {
      _descriptionController.text = _applyTemplate(descTemplate, modName);
    }
    final match = WorkshopVisibility.values
        .where((v) => v.name == visibilityName)
        .firstOrNull;
    if (match != null) {
      setState(() => _visibility = match);
    }
  }

  Future<bool> _confirmLeaveIfActive() async {
    final state = ref.read(workshopPublishProvider);
    if (!state.isActive) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publication in progress'),
        content: const Text(
          'A publication is currently in progress. Are you sure you want to '
          'leave? The upload will be cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _handleBack() async {
    if (await _confirmLeaveIfActive()) {
      if (mounted) {
        ref.invalidate(publishableItemsProvider);
        if (context.canPop()) context.pop();
      }
    }
  }

  Future<void> _startPublish() async {
    // Check steamcmd availability.
    final isAvailable = await SteamCmdManager().isAvailable();
    if (!mounted) return;
    if (!isAvailable) {
      final installed = await SteamCmdInstallDialog.show(context);
      if (!installed || !mounted) return;
    }

    // Use saved credentials if available, otherwise show login dialog.
    var credentials = await SteamLoginDialog.getSavedCredentials();
    if (credentials == null) {
      if (!mounted) return;
      credentials = await SteamLoginDialog.show(context);
    }
    if (credentials == null || !mounted) return;

    final (username, password, steamGuardCode) = credentials;

    // Regenerate preview image if missing.
    var previewPath = _previewImagePath;
    if (previewPath == null) {
      final packFileName = p.basename(_packFilePath);
      final gameDataPath = File(_packFilePath).parent.path;
      final item = _item!;

      String languageCode = 'en';
      String? modImageUrl;
      bool useAppIcon = true;

      if (item is ProjectPublishItem) {
        final langs = item.languagesList;
        if (langs.isNotEmpty) languageCode = langs.first;
        modImageUrl = item.project.imageUrl;
        useAppIcon = item.project.isGameTranslation;
      } else if (item is CompilationPublishItem) {
        languageCode = item.languageCode ?? 'en';
      }

      final imageGenerator = ref.read(packImageGeneratorServiceProvider);
      await imageGenerator.ensurePackImage(
        packFileName: packFileName,
        gameDataPath: gameDataPath,
        languageCode: languageCode,
        modImageUrl: modImageUrl,
        generateImage: true,
        useAppIcon: useAppIcon,
      );
      if (!mounted) return;

      previewPath = _previewImagePath;
      if (previewPath == null) {
        FluentToast.warning(
          context,
          'Failed to generate preview image for the .pack file',
        );
        return;
      }
    }

    final packDir = File(_packFilePath).parent.path;

    final params = WorkshopPublishParams(
      appId: '1142710', // TW:WH3
      publishedFileId: _item!.publishedSteamId!,
      contentFolder: packDir,
      previewFile: previewPath,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      changeNote: _changeNoteController.text.trim(),
      visibility: _visibility,
    );

    String? projectId;
    String? compilationId;
    if (_item is ProjectPublishItem) {
      projectId = (_item as ProjectPublishItem).project.id;
    } else if (_item is CompilationPublishItem) {
      compilationId = (_item as CompilationPublishItem).compilation.id;
    }

    ref.read(workshopPublishProvider.notifier).publish(
          params: params,
          username: username,
          password: password,
          steamGuardCode: steamGuardCode,
          projectId: projectId,
          compilationId: compilationId,
        );
  }

  String _fileSizeForItem(PublishableItem item) {
    switch (item) {
      case ProjectPublishItem i:
        return i.fileSizeFormatted;
      case CompilationPublishItem i:
        return i.fileSizeFormatted;
    }
  }

  String _projectName() => _item?.displayName ?? 'Untitled';

  String? _formatElapsed() {
    if (_uploadStartTime == null) return null;
    final elapsed = DateTime.now().difference(_uploadStartTime!);
    final m = elapsed.inMinutes;
    final s = elapsed.inSeconds % 60;
    return m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workshopPublishProvider);
    final tokens = context.tokens;

    // Fallback when no item has been staged or the item cannot be updated
    // (no prior Workshop ID). Renders a simple toolbar + empty message so
    // users can still navigate back.
    if (_item == null || !_isUpdate) {
      return Material(
        color: tokens.bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DetailScreenToolbar(
              crumb: 'Publishing > Steam Workshop > No pack staged',
              onBack: () {
                if (context.canPop()) context.pop();
              },
            ),
            Expanded(
              child: Center(
                child: Text(
                  'No pack staged — please set a Workshop ID first.',
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: tokens.textDim,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Manage the elapsed timer based on the current phase.
    if (state.isActive && _uploadStartTime == null) {
      _uploadStartTime = DateTime.now();
      _elapsedTimer?.cancel();
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!state.isActive && _elapsedTimer != null) {
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
    }

    // Surface the Steam Guard dialog when the notifier reaches that phase.
    if (state.phase == PublishPhase.awaitingSteamGuard &&
        !_showingSteamGuardDialog) {
      _showingSteamGuardDialog = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          _showingSteamGuardDialog = false;
          return;
        }
        final code = await SteamGuardDialog.show(context);
        _showingSteamGuardDialog = false;
        if (code != null && mounted) {
          ref.read(workshopPublishProvider.notifier).retryWithSteamGuard(code);
        } else if (mounted) {
          ref.read(workshopPublishProvider.notifier).cancel();
        }
      });
    }

    final isIdle = state.phase == PublishPhase.idle;
    final isActive = state.isActive;
    final isCompleted = state.phase == PublishPhase.completed;
    final isError = state.phase == PublishPhase.error;
    final isCancelled = state.phase == PublishPhase.cancelled;
    final canSubmit =
        isIdle && _titleController.text.trim().isNotEmpty;

    return WizardScreenLayout(
      toolbar: DetailScreenToolbar(
        crumb:
            'Publishing > Steam Workshop > ${_projectName()}',
        onBack: _handleBack,
        trailing: [
          SmallIconButton(
            icon: FluentIcons.settings_24_regular,
            tooltip: 'Workshop templates',
            onTap: () async {
              final saved =
                  await WorkshopPublishSettingsDialog.show(context);
              if (saved && mounted) _loadTemplates();
            },
          ),
        ],
      ),
      formPanel: StickyFormPanel(
        sections: [
          FormSection(
            label: 'Publication',
            children: [
              LabeledField(
                label: 'Title',
                child: TokenTextField(
                  controller: _titleController,
                  hint: 'Workshop item title',
                  enabled: isIdle,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              LabeledField(
                label: 'Description',
                child: TokenTextField(
                  controller: _descriptionController,
                  hint: 'Describe your translation mod...',
                  enabled: isIdle,
                  maxLines: 6,
                ),
              ),
              LabeledField(
                label: 'Visibility',
                child: _VisibilityDropdown(
                  value: _visibility,
                  enabled: isIdle,
                  onChanged: (v) {
                    if (v != null) setState(() => _visibility = v);
                  },
                ),
              ),
              LabeledField(
                label: 'Change note',
                child: TokenTextField(
                  controller: _changeNoteController,
                  hint: 'What changed in this update...',
                  enabled: isIdle,
                  maxLines: 3,
                ),
              ),
            ],
          ),
          FormSection(
            label: 'Pack',
            children: [
              ReadonlyField(
                label: 'Pack file',
                value: _packFilePath,
              ),
              if (_isUpdate)
                ReadonlyField(
                  label: 'Steam ID',
                  value: _item!.publishedSteamId!,
                ),
            ],
          ),
        ],
        summary: SummaryBox(
          label: 'Will update',
          semantics: SummarySemantics.accent,
          lines: [
            SummaryLine(
              key: 'Mode',
              value: _isUpdate ? 'Update existing' : 'Publish new',
            ),
            SummaryLine(
              key: 'Pack size',
              value: _fileSizeForItem(_item!),
            ),
            SummaryLine(
              key: 'Visibility',
              value: _visibility.label,
            ),
            if (_isUpdate)
              SummaryLine(
                key: 'Steam ID',
                value: _item!.publishedSteamId!,
              ),
          ],
        ),
        actions: [
          SmallTextButton(
            label: 'Cancel',
            icon: FluentIcons.dismiss_24_regular,
            onTap: isActive ? null : _handleBack,
          ),
          SmallTextButton(
            label: _isUpdate ? 'Update' : 'Publish',
            icon: FluentIcons.cloud_arrow_up_24_regular,
            onTap: canSubmit ? _startPublish : null,
          ),
        ],
      ),
      dynamicZone: DynamicZonePanel(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _buildPhaseChild(
            state: state,
            isCompleted: isCompleted,
            isError: isError,
            isCancelled: isCancelled,
          ),
        ),
      ),
    );
  }

  Widget _buildPhaseChild({
    required WorkshopPublishState state,
    required bool isCompleted,
    required bool isError,
    required bool isCancelled,
  }) {
    if (isCompleted) {
      return _PublishResultPanel(
        key: const ValueKey('done'),
        state: state,
        onOpenInSteam: () {
          final id = state.publishedWorkshopId;
          if (id == null) return;
          launchUrl(Uri.parse(
            'https://steamcommunity.com/sharedfiles/filedetails/?id=$id',
          ));
        },
        onClose: () {
          ref.invalidate(publishableItemsProvider);
          if (context.canPop()) context.pop();
        },
      );
    }
    if (isError || isCancelled) {
      return _PublishErrorPanel(
        key: const ValueKey('failed'),
        state: state,
        onRetry: () => ref.read(workshopPublishProvider.notifier).reset(),
        onClose: () {
          if (context.canPop()) context.pop();
        },
      );
    }
    if (state.isActive ||
        state.phase == PublishPhase.awaitingSteamGuard ||
        state.phase == PublishPhase.awaitingCredentials) {
      return _PublishProgressView(
        key: const ValueKey('progress'),
        state: state,
        elapsed: _formatElapsed(),
        onCancel: () =>
            ref.read(workshopPublishProvider.notifier).cancel(),
      );
    }
    // idle
    return _PublishPreview(
      key: const ValueKey('preview'),
      title: _titleController.text,
      description: _descriptionController.text,
      visibility: _visibility,
      isUpdate: _isUpdate,
      previewImagePath: _previewImagePath,
      pack: _item!,
    );
  }
}

// ---------------------------------------------------------------------------
// Dynamic zone sub-views
// ---------------------------------------------------------------------------

/// Idle-phase live preview of the Workshop post.
class _PublishPreview extends StatelessWidget {
  final String title;
  final String description;
  final WorkshopVisibility visibility;
  final bool isUpdate;
  final String? previewImagePath;
  final PublishableItem pack;

  const _PublishPreview({
    super.key,
    required this.title,
    required this.description,
    required this.visibility,
    required this.isUpdate,
    required this.previewImagePath,
    required this.pack,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isUpdate ? 'Preview (update)' : 'Preview',
            style: tokens.fontMono.copyWith(
              fontSize: 10,
              color: tokens.textDim,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PreviewImage(path: previewImagePath),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? 'Untitled' : title,
                      style: tokens.fontDisplay.copyWith(
                        fontSize: 18,
                        color: tokens.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pack.outputPath,
                      style: tokens.fontMono.copyWith(
                        fontSize: 11,
                        color: tokens.textFaint,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _Chip(text: visibility.label),
                        const SizedBox(width: 6),
                        if (pack is ProjectPublishItem)
                          _Chip(
                            text:
                                '${(pack as ProjectPublishItem).entryCount} entries',
                          )
                        else if (pack is CompilationPublishItem)
                          _Chip(
                            text:
                                '${(pack as CompilationPublishItem).projectCount} projects',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tokens.panel2,
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: Text(
              description.isEmpty
                  ? 'No description provided yet.'
                  : description,
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: description.isEmpty ? tokens.textFaint : tokens.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewImage extends StatelessWidget {
  final String? path;
  const _PreviewImage({required this.path});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (path == null) {
      return Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: tokens.panel2,
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
        ),
        alignment: Alignment.center,
        child: Icon(
          FluentIcons.image_off_24_regular,
          size: 28,
          color: tokens.textFaint,
        ),
      );
    }
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.file(
        File(path!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Icon(
          FluentIcons.image_24_regular,
          size: 32,
          color: tokens.textFaint,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({required this.text});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tokens.panel2,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusPill),
      ),
      child: Text(
        text,
        style: tokens.fontMono.copyWith(
          fontSize: 10,
          color: tokens.textMid,
        ),
      ),
    );
  }
}

/// Active-phase view: progress card + inline log terminal.
class _PublishProgressView extends StatefulWidget {
  final WorkshopPublishState state;
  final String? elapsed;
  final VoidCallback onCancel;

  const _PublishProgressView({
    super.key,
    required this.state,
    required this.elapsed,
    required this.onCancel,
  });

  @override
  State<_PublishProgressView> createState() => _PublishProgressViewState();
}

class _PublishProgressViewState extends State<_PublishProgressView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final progressPercent = (widget.state.progress * 100).toStringAsFixed(1);

    // Auto-scroll the output terminal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients &&
          widget.state.steamcmdOutput.isNotEmpty) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.panel2,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    FluentIcons.cloud_arrow_up_24_regular,
                    size: 18,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Uploading to Steam Workshop...',
                      style: tokens.fontDisplay.copyWith(
                        fontSize: 14,
                        color: tokens.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.elapsed != null) ...[
                    Text(
                      widget.elapsed!,
                      style: tokens.fontMono.copyWith(
                        fontSize: 11,
                        color: tokens.textDim,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    '$progressPercent%',
                    style: tokens.fontMono.copyWith(
                      fontSize: 12,
                      color: tokens.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SmallIconButton(
                    icon: FluentIcons.dismiss_24_regular,
                    tooltip: 'Cancel',
                    onTap: widget.onCancel,
                    foreground: tokens.err,
                    background: tokens.errBg,
                    borderColor: tokens.err.withValues(alpha: 0.3),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: widget.state.progress.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: tokens.panel,
                  valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
                ),
              ),
              if (widget.state.statusMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  widget.state.statusMessage!,
                  style: tokens.fontMono.copyWith(
                    fontSize: 11,
                    color: tokens.textDim,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'STEAMCMD OUTPUT',
          style: tokens.fontMono.copyWith(
            fontSize: 10,
            color: tokens.textDim,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(color: tokens.border),
            ),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: widget.state.steamcmdOutput.length,
              itemBuilder: (context, index) {
                return Text(
                  widget.state.steamcmdOutput[index],
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 11,
                    color: Color(0xFFCCCCCC),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Completed-phase panel: success banner + open-in-Steam / close actions.
class _PublishResultPanel extends StatelessWidget {
  final WorkshopPublishState state;
  final VoidCallback onOpenInSteam;
  final VoidCallback onClose;

  const _PublishResultPanel({
    super.key,
    required this.state,
    required this.onOpenInSteam,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: tokens.okBg,
                border: Border.all(color: tokens.ok.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        FluentIcons.checkmark_circle_24_filled,
                        size: 22,
                        color: tokens.ok,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          state.wasUpdate
                              ? 'Workshop item updated!'
                              : 'Workshop item published!',
                          style: tokens.fontDisplay.copyWith(
                            fontSize: 15,
                            color: tokens.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (state.publishedWorkshopId != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Workshop ID: ${state.publishedWorkshopId}',
                      style: tokens.fontMono.copyWith(
                        fontSize: 12,
                        color: tokens.textMid,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SmallTextButton(
                  label: 'Open in Steam',
                  icon: FluentIcons.open_24_regular,
                  onTap: state.publishedWorkshopId != null
                      ? onOpenInSteam
                      : null,
                ),
                const SizedBox(width: 8),
                SmallTextButton(
                  label: 'Close',
                  icon: FluentIcons.checkmark_24_regular,
                  onTap: onClose,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Error / cancelled panel.
class _PublishErrorPanel extends StatelessWidget {
  final WorkshopPublishState state;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const _PublishErrorPanel({
    super.key,
    required this.state,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isCancelled = state.phase == PublishPhase.cancelled;
    final title = isCancelled ? 'Publication cancelled' : 'Publication failed';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: tokens.errBg,
                border: Border.all(color: tokens.err.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        FluentIcons.error_circle_24_filled,
                        size: 22,
                        color: tokens.err,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: tokens.fontDisplay.copyWith(
                            fontSize: 15,
                            color: tokens.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (state.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      state.errorMessage!,
                      style: tokens.fontBody.copyWith(
                        fontSize: 12,
                        color: tokens.err,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SmallTextButton(
                  label: 'Retry',
                  icon: FluentIcons.arrow_counterclockwise_24_regular,
                  onTap: onRetry,
                ),
                const SizedBox(width: 8),
                SmallTextButton(
                  label: 'Close',
                  icon: FluentIcons.dismiss_24_regular,
                  onTap: onClose,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VisibilityDropdown extends StatelessWidget {
  final WorkshopVisibility value;
  final bool enabled;
  final ValueChanged<WorkshopVisibility?> onChanged;

  const _VisibilityDropdown({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.panel2,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<WorkshopVisibility>(
          value: value,
          isExpanded: true,
          isDense: true,
          style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.text),
          dropdownColor: tokens.panel,
          icon: Icon(
            FluentIcons.chevron_down_24_regular,
            size: 14,
            color: tokens.textDim,
          ),
          items: WorkshopVisibility.values
              .map(
                (v) => DropdownMenuItem<WorkshopVisibility>(
                  value: v,
                  child: Text(
                    v.label,
                    style: tokens.fontBody
                        .copyWith(fontSize: 13, color: tokens.text),
                  ),
                ),
              )
              .toList(),
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}
