import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../providers/tm_providers.dart';

/// Token-themed popup for cleaning up low-quality / stale TM entries.
class TmCleanupDialog extends ConsumerStatefulWidget {
  const TmCleanupDialog({super.key});

  @override
  ConsumerState<TmCleanupDialog> createState() => _TmCleanupDialogState();
}

class _TmCleanupDialogState extends ConsumerState<TmCleanupDialog> {
  int _unusedDays = 365;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final cleanupState = ref.watch(tmCleanupStateProvider);

    return TokenDialog(
      icon: FluentIcons.broom_24_regular,
      title: t.translationMemory.dialogs.cleanupTitle,
      width: 520,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.translationMemory.messages.removeUnusedHint,
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.textDim,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t.translationMemory.labels.deleteIfUnusedDays,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _unusedDays == 0 ? t.translationMemory.labels.deleteAll : '$_unusedDays',
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: _unusedDays == 0 ? tokens.err : tokens.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: tokens.accent,
              inactiveTrackColor: tokens.panel2,
              thumbColor: tokens.accent,
              overlayColor: tokens.accentBg,
            ),
            child: Slider(
              value: _unusedDays.toDouble(),
              min: 0,
              max: 730,
              divisions: 73,
              onChanged: (value) =>
                  setState(() => _unusedDays = value.toInt()),
            ),
          ),
          if (_unusedDays == 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                t.translationMemory.messages.allEntriesWillBeDeleted,
                style: tokens.fontBody.copyWith(
                  fontSize: 12,
                  color: tokens.err,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 20),
          cleanupState.when(
            data: (deletedCount) {
              if (deletedCount != null) {
                return _ResultBanner(
                  color: tokens.ok,
                  bgColor: tokens.okBg,
                  icon: FluentIcons.checkmark_circle_24_filled,
                  message: t.translationMemory.messages.deletedEntries(count: deletedCount),
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => LinearProgressIndicator(
              color: tokens.accent,
              backgroundColor: tokens.panel2,
            ),
            error: (error, stack) => Text(
              error.toString(),
              style: tokens.fontBody.copyWith(
                fontSize: 12.5,
                color: tokens.err,
              ),
            ),
          ),
        ],
      ),
      actions: cleanupState.asData?.value != null
          ? [
              SmallTextButton(
                label: t.common.ok,
                filled: true,
                onTap: () {
                  ref.read(tmCleanupStateProvider.notifier).reset();
                  Navigator.of(context).pop();
                },
              ),
            ]
          : [
              SmallTextButton(
                label: t.common.actions.cancel,
                onTap: cleanupState.isLoading
                    ? null
                    : () {
                        ref.read(tmCleanupStateProvider.notifier).reset();
                        Navigator.of(context).pop();
                      },
              ),
              SmallTextButton(
                label: t.translationMemory.actions.cleanup,
                icon: FluentIcons.broom_24_regular,
                filled: true,
                onTap: cleanupState.isLoading
                    ? null
                    : () async {
                        await ref
                            .read(tmCleanupStateProvider.notifier)
                            .cleanup(unusedDays: _unusedDays);
                      },
              ),
            ],
    );
  }
}

class _ResultBanner extends StatelessWidget {
  final Color color;
  final Color bgColor;
  final IconData icon;
  final String message;

  const _ResultBanner({
    required this.color,
    required this.bgColor,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
