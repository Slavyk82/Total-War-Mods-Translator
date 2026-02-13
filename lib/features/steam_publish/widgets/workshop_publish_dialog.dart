import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../features/settings/providers/settings_providers.dart';
import '../../../services/settings/settings_service.dart';
import '../../../services/service_locator.dart';
import '../../../services/steam/models/workshop_publish_params.dart';
import '../../../services/steam/steamcmd_manager.dart';
import '../../../widgets/fluent/fluent_progress_indicator.dart';
import '../providers/steam_publish_providers.dart';
import '../providers/workshop_publish_notifier.dart';
import 'steam_guard_dialog.dart';
import 'steam_login_dialog.dart';
import 'steamcmd_install_dialog.dart';
import 'workshop_publish_settings_dialog.dart';

/// Dialog for publishing a pack export to Steam Workshop.
///
/// Has two modes:
/// - Form mode: configure title, description, visibility, etc.
/// - Progress mode: shows upload progress and steamcmd output.
class WorkshopPublishDialog extends ConsumerStatefulWidget {
  final PublishableItem item;

  const WorkshopPublishDialog({super.key, required this.item});

  /// Show the publish dialog.
  static Future<void> show(
    BuildContext context, {
    required PublishableItem item,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkshopPublishDialog(item: item),
    );
  }

  @override
  ConsumerState<WorkshopPublishDialog> createState() =>
      _WorkshopPublishDialogState();
}

class _WorkshopPublishDialogState
    extends ConsumerState<WorkshopPublishDialog> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _changeNoteController;
  WorkshopVisibility _visibility = WorkshopVisibility.public_;
  final ScrollController _outputScrollController = ScrollController();
  DateTime? _uploadStartTime;
  Timer? _elapsedTimer;
  bool _showingSteamGuardDialog = false;
  late final WorkshopPublishNotifier _publishNotifier;

  bool get _isUpdate =>
      widget.item.publishedSteamId != null &&
      widget.item.publishedSteamId!.isNotEmpty;

  String get _packFilePath => widget.item.outputPath;

  String? get _previewImagePath {
    final packPath = _packFilePath;
    final imagePath =
        '${packPath.substring(0, packPath.lastIndexOf('.'))}.png';
    if (File(imagePath).existsSync()) return imagePath;
    return null;
  }

  @override
  void initState() {
    super.initState();
    _publishNotifier = ref.read(workshopPublishProvider.notifier);
    // Reset any leftover state from a previous publish (deferred to avoid
    // modifying a provider during a widget lifecycle method).
    Future.microtask(() {
      _publishNotifier.reset();
    });

    _titleController = TextEditingController(
      text: widget.item.displayName,
    );
    _descriptionController = TextEditingController();
    _changeNoteController = TextEditingController();
    _loadTemplates();
  }

  String _applyTemplate(String template, String modName) {
    if (template.isEmpty) return '';
    return template.replaceAll('\$modName', modName);
  }

  Future<void> _loadTemplates() async {
    final service = ServiceLocator.get<SettingsService>();
    final titleTemplate =
        await service.getString(SettingsKeys.workshopTitleTemplate);
    final descTemplate =
        await service.getString(SettingsKeys.workshopDescriptionTemplate);
    final visibilityName =
        await service.getString(SettingsKeys.workshopDefaultVisibility);
    if (!mounted) return;
    final modName = widget.item.displayName;
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

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    _changeNoteController.dispose();
    _outputScrollController.dispose();
    _publishNotifier.silentCleanup();
    super.dispose();
  }

  Future<void> _startPublish() async {
    // Check steamcmd availability
    final isAvailable = await SteamCmdManager().isAvailable();
    if (!mounted) return;
    if (!isAvailable) {
      final installed = await SteamCmdInstallDialog.show(context);
      if (!installed || !mounted) return;
    }

    // Show login dialog
    final credentials = await SteamLoginDialog.show(context);
    if (credentials == null || !mounted) return;

    final (username, password, steamGuardCode) = credentials;

    final previewPath = _previewImagePath;
    if (previewPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No preview image found next to the .pack file')),
        );
      }
      return;
    }

    final packDir = File(_packFilePath).parent.path;

    final params = WorkshopPublishParams(
      appId: '1142710', // TW:WH3
      publishedFileId:
          _isUpdate ? widget.item.publishedSteamId! : '0',
      contentFolder: packDir,
      previewFile: previewPath,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      changeNote: _changeNoteController.text.trim(),
      visibility: _visibility,
    );

    // Determine project/compilation ID
    String? projectId;
    String? compilationId;
    if (widget.item is ProjectPublishItem) {
      projectId = (widget.item as ProjectPublishItem).project.id;
    } else if (widget.item is CompilationPublishItem) {
      compilationId = (widget.item as CompilationPublishItem).compilation.id;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(workshopPublishProvider);

    // Start/stop elapsed timer based on phase
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

    // Auto-scroll output terminal
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_outputScrollController.hasClients &&
          state.steamcmdOutput.isNotEmpty) {
        _outputScrollController.jumpTo(
          _outputScrollController.position.maxScrollExtent,
        );
      }
    });

    // Handle Steam Guard dialog (guard against multiple openings)
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

    final showForm = state.phase == PublishPhase.idle;

    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(theme),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: showForm
                    ? _buildForm(theme)
                    : _buildProgress(theme, state),
              ),
            ),
            const Divider(height: 1),
            _buildFooter(theme, state),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(
            FluentIcons.cloud_arrow_up_24_regular,
            size: 28,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isUpdate ? 'Update Workshop Item' : 'Publish to Workshop',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.item.displayName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          // Settings button
          IconButton(
            icon: const Icon(FluentIcons.settings_24_regular, size: 20),
            tooltip: 'Workshop templates',
            onPressed: () async {
              final saved = await WorkshopPublishSettingsDialog.show(context);
              if (saved && mounted) _loadTemplates();
            },
          ),
          const SizedBox(width: 4),
          // New / Update badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _isUpdate
                  ? Colors.blue.withValues(alpha: 0.1)
                  : Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isUpdate
                    ? Colors.blue.withValues(alpha: 0.3)
                    : Colors.green.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              _isUpdate
                  ? 'Update #${widget.item.publishedSteamId}'
                  : 'New Item',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _isUpdate ? Colors.blue.shade700 : Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    final mutedColor =
        theme.colorScheme.onSurface.withValues(alpha: 0.6);

    // Build info section based on item type
    final String fileSizeText;
    final String entriesText;
    switch (widget.item) {
      case ProjectPublishItem item:
        fileSizeText = item.fileSizeFormatted;
        entriesText = '${item.entryCount} entries';
      case CompilationPublishItem item:
        fileSizeText = item.fileSizeFormatted;
        entriesText = '${item.projectCount} projects';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Preview image + pack info
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview image
            if (_previewImagePath != null)
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.file(
                  File(_previewImagePath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    FluentIcons.image_24_regular,
                    size: 40,
                    color: mutedColor,
                  ),
                ),
              )
            else
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(FluentIcons.image_off_24_regular,
                        size: 32, color: mutedColor),
                    const SizedBox(height: 4),
                    Text('No preview',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: mutedColor)),
                  ],
                ),
              ),
            const SizedBox(width: 16),
            // Pack file info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pack File',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _packFilePath,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: mutedColor,
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fileSizeText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: mutedColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entriesText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: mutedColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Title
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),

        // Description
        TextField(
          controller: _descriptionController,
          decoration: const InputDecoration(
            labelText: 'Description',
            border: OutlineInputBorder(),
            hintText: 'Describe your translation mod...',
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 12),

        // Visibility dropdown
        DropdownButtonFormField<WorkshopVisibility>(
          initialValue: _visibility,
          decoration: const InputDecoration(
            labelText: 'Visibility',
            border: OutlineInputBorder(),
          ),
          items: WorkshopVisibility.values.map((v) {
            return DropdownMenuItem(
              value: v,
              child: Text(v.label),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _visibility = value);
            }
          },
        ),

        // Change notes (only for updates)
        if (_isUpdate) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _changeNoteController,
            decoration: const InputDecoration(
              labelText: 'Change Notes',
              border: OutlineInputBorder(),
              hintText: 'What changed in this update...',
            ),
            maxLines: 2,
          ),
        ],
      ],
    );
  }

  String? _formatElapsed() {
    if (_uploadStartTime == null) return null;
    final elapsed = DateTime.now().difference(_uploadStartTime!);
    final m = elapsed.inMinutes;
    final s = elapsed.inSeconds % 60;
    return m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${s}s';
  }

  Widget _buildProgress(ThemeData theme, WorkshopPublishState state) {
    final progressPercent = (state.progress * 100).toStringAsFixed(1);
    final isComplete = state.phase == PublishPhase.completed;
    final isError = state.phase == PublishPhase.error;
    final isCancelled = state.phase == PublishPhase.cancelled;
    final elapsedStr = _formatElapsed();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        isComplete
                            ? 'Upload Complete'
                            : isError
                                ? 'Upload Failed'
                                : isCancelled
                                    ? 'Cancelled'
                                    : 'Uploading...',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (elapsedStr != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          elapsedStr,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '$progressPercent%',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isComplete
                          ? Colors.green.shade700
                          : isError
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FluentProgressBar(
                value: state.progress,
                height: 8,
                color: isComplete
                    ? Colors.green.shade700
                    : isError
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                backgroundColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.1),
              ),
              if (state.statusMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.statusMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Success banner
        if (isComplete && state.publishedWorkshopId != null)
          _buildSuccessBanner(theme, state),

        // Error banner
        if (isError && state.errorMessage != null)
          _buildErrorBanner(theme, state),

        const SizedBox(height: 16),

        // Steamcmd output terminal
        Text(
          'steamcmd Output',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: ListView.builder(
            controller: _outputScrollController,
            padding: const EdgeInsets.all(12),
            itemCount: state.steamcmdOutput.length,
            itemBuilder: (context, index) {
              return Text(
                state.steamcmdOutput[index],
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 11,
                  color: Color(0xFFCCCCCC),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessBanner(ThemeData theme, WorkshopPublishState state) {
    final workshopUrl =
        'https://steamcommunity.com/sharedfiles/filedetails/?id=${state.publishedWorkshopId}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(FluentIcons.checkmark_circle_24_filled,
              size: 24, color: Colors.green.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.wasUpdate
                      ? 'Workshop item updated!'
                      : 'Published to Workshop!',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => launchUrl(Uri.parse(workshopUrl)),
                    child: Text(
                      'Workshop ID: ${state.publishedWorkshopId}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.blue.shade700,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme, WorkshopPublishState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(FluentIcons.error_circle_24_filled,
              size: 24, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Publication failed',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  state.errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme, WorkshopPublishState state) {
    final showForm = state.phase == PublishPhase.idle;
    final isActive = state.isActive;
    final isDone = state.phase == PublishPhase.completed ||
        state.phase == PublishPhase.error ||
        state.phase == PublishPhase.cancelled;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (showForm) ...[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _titleController.text.trim().isNotEmpty
                  ? _startPublish
                  : null,
              icon: const Icon(FluentIcons.cloud_arrow_up_24_regular, size: 18),
              label: Text(_isUpdate ? 'Update' : 'Publish'),
            ),
          ],
          if (isActive)
            TextButton.icon(
              onPressed: () {
                ref.read(workshopPublishProvider.notifier).cancel();
              },
              icon: const Icon(FluentIcons.dismiss_24_regular, size: 18),
              label: const Text('Cancel'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
            ),
          if (isDone)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(FluentIcons.checkmark_24_regular, size: 18),
              label: const Text('Close'),
            ),
        ],
      ),
    );
  }
}
