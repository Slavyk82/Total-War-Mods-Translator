import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../providers/pack_compilation_providers.dart';

/// Section displaying BBCode links for Steam Workshop publication.
class CompilationBBCodeSection extends ConsumerStatefulWidget {
  const CompilationBBCodeSection({super.key});

  @override
  ConsumerState<CompilationBBCodeSection> createState() => _CompilationBBCodeSectionState();
}

class _CompilationBBCodeSectionState extends ConsumerState<CompilationBBCodeSection> {
  bool _copied = false;

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bbCodeAsync = ref.watch(compilationBBCodeProvider);
    final state = ref.watch(compilationEditorProvider);

    // Don't show if no projects selected
    if (state.selectedProjectIds.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.link_24_regular,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Steam Workshop BBCode',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              bbCodeAsync.when(
                data: (bbCode) {
                  if (bbCode.isEmpty) return const SizedBox.shrink();
                  return _CopyButton(
                    onTap: () => _copyToClipboard(bbCode),
                    isCopied: _copied,
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Copy this BBCode to use in your Steam Workshop description:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          bbCodeAsync.when(
            data: (bbCode) {
              if (bbCode.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Text(
                    'No mods with Steam Workshop IDs selected',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color
                          ?.withValues(alpha: 0.5),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                );
              }
              return Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    bbCode,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              );
            },
            loading: () => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: theme.dividerColor),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (error, _) => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
                border:
                    Border.all(color: theme.colorScheme.error.withValues(alpha: 0.5)),
              ),
              child: Text(
                'Error generating BBCode',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Copy button with hover state and feedback.
class _CopyButton extends StatefulWidget {
  const _CopyButton({
    required this.onTap,
    required this.isCopied,
  });

  final VoidCallback onTap;
  final bool isCopied;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: widget.isCopied
                ? Colors.green.withValues(alpha: 0.1)
                : _isHovered
                    ? theme.colorScheme.primary.withValues(alpha: 0.1)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: widget.isCopied
                  ? Colors.green.withValues(alpha: 0.5)
                  : theme.colorScheme.outline.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isCopied
                    ? FluentIcons.checkmark_16_regular
                    : FluentIcons.copy_16_regular,
                size: 16,
                color: widget.isCopied ? Colors.green : theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                widget.isCopied ? 'Copied!' : 'Copy',
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      widget.isCopied ? Colors.green : theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
