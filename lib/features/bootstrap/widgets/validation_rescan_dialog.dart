import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/services/validation/validation_rescan_service.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../providers/validation_rescan_provider.dart';

/// Format a [Duration] in a short English form: `3m 20s`, `1h 5m`, `45s`.
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

/// Format an integer with thousands separators (e.g. `12,000`).
String formatCount(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Blocking dialog that runs the one-shot validation rescan at startup.
///
/// The dialog:
/// 1. Asks the controller to `prepare()` (calibration + counts).
/// 2. If no legacy rows, closes itself immediately so boot continues.
/// 3. Otherwise shows the first-run or resume wording with a Start button.
/// 4. On start, switches to a determinate progress view with live ETA.
/// 5. Closes itself when the scan completes, firing a success toast.
class ValidationRescanDialog extends ConsumerStatefulWidget {
  const ValidationRescanDialog({super.key});

  /// Prepare the plan; if there is work to do, block on the dialog until
  /// the rescan completes. Returns normally when nothing to do.
  static Future<void> showAndRun(
      BuildContext context, WidgetRef ref) async {
    await ref.read(validationRescanControllerProvider.notifier).prepare();
    final plan = ref.read(validationRescanControllerProvider).plan;
    if (plan == null) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ValidationRescanDialog(),
    );
  }

  @override
  ConsumerState<ValidationRescanDialog> createState() =>
      _ValidationRescanDialogState();
}

class _ValidationRescanDialogState
    extends ConsumerState<ValidationRescanDialog> {
  bool _toastFired = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final state = ref.watch(validationRescanControllerProvider);
    final plan = state.plan;

    // Nothing to do — close and exit.
    if (plan == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    // Completion: close and fire a success toast once.
    if (state.isDone && !_toastFired) {
      _toastFired = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop();
        FluentToast.success(
          context,
          'Validation data update complete.',
        );
      });
    }

    final title = state.progress != null || state.isRunning
        ? 'Updating validation data'
        : (plan.isResume
            ? 'Resuming validation update'
            : 'Validation data update required');

    return PopScope(
      canPop: false,
      child: TokenDialog(
        icon: FluentIcons.shield_checkmark_24_regular,
        title: title,
        width: 520,
        body: state.progress != null
            ? _progressBody(tokens, state.progress!)
            : _planBody(tokens, plan),
      ),
    );
  }

  Widget _planBody(TwmtThemeTokens tokens, RescanPlan plan) {
    final totalAll = plan.total + plan.already;
    final bodyText = plan.isResume
        ? 'A previous update was interrupted. '
            '${formatCount(plan.already)} of ${formatCount(totalAll)} units '
            'already processed. Remaining: ${formatCount(plan.total)} units '
            '• Estimated: ~${formatDuration(plan.estimated)}.'
        : 'This release uses a new, richer format for translation '
            'validation diagnostics. All existing translations need to be '
            'rescanned once to benefit from it.\n\n'
            '${formatCount(plan.total)} units to rescan • '
            'Estimated: ~${formatDuration(plan.estimated)}\n\n'
            'This will only run once. Do not close the app until it '
            'completes — if interrupted, the update will resume on next launch.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          bodyText,
          style: tokens.fontBody.copyWith(color: tokens.textDim),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: SmallTextButton(
            label: plan.isResume ? 'Continue' : 'Start rescan',
            icon: FluentIcons.play_24_regular,
            filled: true,
            onTap: () => ref
                .read(validationRescanControllerProvider.notifier)
                .start(),
          ),
        ),
      ],
    );
  }

  Widget _progressBody(TwmtThemeTokens tokens, RescanProgress progress) {
    final value = progress.total == 0
        ? 1.0
        : (progress.done / progress.total).clamp(0.0, 1.0);
    final etaText = progress.eta == null
        ? ''
        : ' — ETA ${formatDuration(progress.eta!)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Rescanned ${formatCount(progress.done)} of '
          '${formatCount(progress.total)}$etaText',
          style: tokens.fontBody,
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: value),
        ),
        const SizedBox(height: 12),
        Text(
          'Closing the app will pause the update; it will resume on '
          'next launch.',
          style: tokens.fontBody.copyWith(
            fontSize: 11,
            color: tokens.textDim,
          ),
        ),
      ],
    );
  }
}
