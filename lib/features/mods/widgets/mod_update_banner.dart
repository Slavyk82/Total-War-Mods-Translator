import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/mods/mod_list_provider.dart';
import 'whats_new_dialog.dart';

/// Dismissible banner that appears when mod updates are available
class ModUpdateBanner extends ConsumerWidget {
  const ModUpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modsWithUpdatesAsync = ref.watch(modsWithUpdatesProvider);
    final bannerVisibleAsync = ref.watch(updateBannerVisibleProvider);

    return bannerVisibleAsync.when(
      data: (isVisible) {
        if (!isVisible) {
          return const SizedBox.shrink();
        }

        return modsWithUpdatesAsync.when(
          data: (modsWithUpdates) {
            if (modsWithUpdates.isEmpty) {
              return const SizedBox.shrink();
            }

            return _BannerContent(
              updateCount: modsWithUpdates.length,
              onDismiss: () {
                ref.read(updateBannerVisibleProvider.notifier).dismiss();
              },
              onViewUpdates: () {
                _showWhatsNewDialog(context, modsWithUpdates);
              },
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  void _showWhatsNewDialog(BuildContext context, dynamic modsWithUpdates) {
    final projects = (modsWithUpdates as List).cast<Project>();
    showDialog(
      context: context,
      builder: (context) => WhatsNewDialog(
        projectsWithUpdates: projects,
      ),
    );
  }
}

class _BannerContent extends StatefulWidget {
  final int updateCount;
  final VoidCallback onDismiss;
  final VoidCallback onViewUpdates;

  const _BannerContent({
    required this.updateCount,
    required this.onDismiss,
    required this.onViewUpdates,
  });

  @override
  State<_BannerContent> createState() => _BannerContentState();
}

class _BannerContentState extends State<_BannerContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -1),
        end: Offset.zero,
      ).animate(_slideAnimation),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4CE),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFFFD666),
              width: 1,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Row(
            children: [
              const Icon(
                FluentIcons.info_24_regular,
                color: Color(0xFFCC8800),
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.updateCount == 1
                      ? '1 mod update available'
                      : '${widget.updateCount} mod updates available',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF664400),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _ActionButton(
                label: 'View Updates',
                onTap: widget.onViewUpdates,
              ),
              const SizedBox(width: 12),
              _DismissButton(onTap: widget.onDismiss),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _isPressed
                ? const Color(0xFFCC8800)
                : _isHovered
                    ? const Color(0xFFEE9900)
                    : const Color(0xFFFFAA00),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _DismissButton extends StatefulWidget {
  final VoidCallback onTap;

  const _DismissButton({required this.onTap});

  @override
  State<_DismissButton> createState() => _DismissButtonState();
}

class _DismissButtonState extends State<_DismissButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _isHovered
                ? const Color(0xFFFFE8B3)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Icon(
            FluentIcons.dismiss_24_regular,
            color: Color(0xFF664400),
            size: 20,
          ),
        ),
      ),
    );
  }
}
