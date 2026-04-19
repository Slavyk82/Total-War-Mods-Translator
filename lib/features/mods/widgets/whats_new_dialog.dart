import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/mods/mod_update_provider.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'mod_update_dialog.dart';

/// Token-themed popup shown at startup when new mod updates are detected.
class WhatsNewDialog extends ConsumerStatefulWidget {
  final List<Project> projectsWithUpdates;

  const WhatsNewDialog({
    super.key,
    required this.projectsWithUpdates,
  });

  @override
  ConsumerState<WhatsNewDialog> createState() => _WhatsNewDialogState();
}

class _WhatsNewDialogState extends ConsumerState<WhatsNewDialog> {
  static const String _dontShowAgainKey = 'whats_new_dont_show_again';
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final count = widget.projectsWithUpdates.length;

    return TokenDialog(
      icon: FluentIcons.info_24_regular,
      iconColor: tokens.info,
      title: "What's New in Your Mods",
      subtitle:
          '$count ${count == 1 ? 'mod has' : 'mods have'} updates available',
      width: 640,
      body: SizedBox(
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView.separated(
                itemCount: widget.projectsWithUpdates.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final project = widget.projectsWithUpdates[index];
                  return _ModUpdateItem(
                    project: project,
                    onViewDetails: () => _viewModDetails(project),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            _DontShowAgainToggle(
              value: _dontShowAgain,
              onChanged: (v) => setState(() => _dontShowAgain = v),
            ),
          ],
        ),
      ),
      actions: [
        SmallTextButton(
          label: 'Remind Me Later',
          onTap: () => _closeDialog(),
        ),
        SmallTextButton(
          label: 'Update All',
          icon: FluentIcons.arrow_download_24_regular,
          filled: true,
          onTap: _updateAll,
        ),
      ],
    );
  }

  void _viewModDetails(Project project) {
    Navigator.of(context).pop();
    context.go(AppRoutes.projectDetail(project.id));
  }

  void _updateAll() async {
    ref.read(modUpdateQueueProvider.notifier).addMultipleToQueue(
          widget.projectsWithUpdates,
        );

    Navigator.of(context).pop();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ModUpdateDialog(),
    );

    ref.read(modUpdateQueueProvider.notifier).startUpdates();
  }

  void _closeDialog() async {
    if (_dontShowAgain) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_dontShowAgainKey, true);
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _DontShowAgainToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _DontShowAgainToggle({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Row(
          children: [
            Icon(
              value
                  ? FluentIcons.checkbox_checked_24_filled
                  : FluentIcons.checkbox_unchecked_24_regular,
              size: 18,
              color: value ? tokens.accent : tokens.textFaint,
            ),
            const SizedBox(width: 10),
            Text(
              "Don't show this again",
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModUpdateItem extends StatefulWidget {
  final Project project;
  final VoidCallback onViewDetails;

  const _ModUpdateItem({
    required this.project,
    required this.onViewDetails,
  });

  @override
  State<_ModUpdateItem> createState() => _ModUpdateItemState();
}

class _ModUpdateItemState extends State<_ModUpdateItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _hovered ? tokens.accentBg : tokens.panel2,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(
            color: _hovered ? tokens.accent : tokens.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  FluentIcons.cube_24_regular,
                  color: tokens.accent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.project.name,
                    style: tokens.fontBody.copyWith(
                      fontSize: 13,
                      color: tokens.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.ok.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                  child: Text(
                    'NEW',
                    style: tokens.fontBody.copyWith(
                      fontSize: 10.5,
                      color: tokens.ok,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Current version: ${widget.project.modVersion ?? 'Unknown'}',
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.textDim,
              ),
            ),
            const SizedBox(height: 10),
            SmallTextButton(
              label: 'View Details',
              icon: FluentIcons.arrow_right_24_regular,
              onTap: widget.onViewDetails,
            ),
          ],
        ),
      ),
    );
  }
}
