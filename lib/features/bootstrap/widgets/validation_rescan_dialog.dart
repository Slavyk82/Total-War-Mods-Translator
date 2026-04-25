import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
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

/// Blocking dialog that owns every piece of validation-data bootstrap work.
///
/// Order inside the dialog:
/// 1. Normalize legacy `validation_issues` JSON payloads (fast, silent-ish
///    progress bar).
/// 2. Calibrate the rescan and build a [RescanPlan].
/// 3. If nothing to rescan, close immediately so boot continues.
/// 4. Otherwise show the first-run or resume wording with a Start button.
/// 5. On start, switch to a determinate progress view with live ETA.
/// 6. Close on completion, firing a success toast.
class ValidationRescanDialog extends ConsumerStatefulWidget {
  const ValidationRescanDialog({super.key});

  /// Open the dialog only if there is work to do. The dialog itself drives
  /// preparation internally, so the host doesn't freeze the UI while legacy
  /// payloads are rewritten.
  static Future<void> showAndRun(
      BuildContext context, WidgetRef ref) async {
    final hasWork = await ref
        .read(validationRescanControllerProvider.notifier)
        .hasPendingWork();
    if (!hasWork) return;
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
  bool _prepareTriggered = false;

  @override
  void initState() {
    super.initState();
    // Drive preparation from inside the dialog so the modal is already on
    // screen while the JSON normalization (potentially slow) runs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_prepareTriggered) {
        _prepareTriggered = true;
        ref.read(validationRescanControllerProvider.notifier).prepare();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final state = ref.watch(validationRescanControllerProvider);
    final plan = state.plan;

    // Completion: close and fire a success toast once.
    if (state.isDone && !_toastFired) {
      _toastFired = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop();
        // Only show a toast when an actual rescan finished. Pure-
        // normalization runs (no plan) complete silently.
        if (plan != null) {
          FluentToast.success(
            context,
            t.bootstrap.validationRescan.toasts.updateComplete,
          );
        }
      });
    }

    final title = _titleFor(state);

    return PopScope(
      canPop: false,
      child: TokenDialog(
        icon: FluentIcons.shield_checkmark_24_regular,
        title: title,
        width: 520,
        body: _body(tokens, state),
      ),
    );
  }

  String _titleFor(RescanState state) {
    if (state.isNormalizing) return t.bootstrap.validationRescan.titles.preparing;
    if (state.progress != null || state.isRunning) {
      return t.bootstrap.validationRescan.titles.updating;
    }
    final plan = state.plan;
    if (plan != null) {
      return plan.isResume
          ? t.bootstrap.validationRescan.titles.resuming
          : t.bootstrap.validationRescan.titles.required;
    }
    return t.bootstrap.validationRescan.titles.preparing;
  }

  Widget _body(TwmtThemeTokens tokens, RescanState state) {
    if (state.isNormalizing) {
      return _normalizingBody(tokens, state);
    }
    // Once Start has been pressed, stay on the progress lane even before
    // the first progress event arrives. Otherwise the title flips to
    // "Updating validation data" while the body still offers another
    // "Start rescan" button — a confusing transient the user reported.
    if (state.isRunning || state.progress != null) {
      return _progressBody(tokens, state.progress);
    }
    final plan = state.plan;
    if (plan != null) {
      return _planBody(tokens, plan);
    }
    // Plan not yet computed (between normalization end and calibration).
    return _preparingBody(tokens);
  }

  Widget _normalizingBody(TwmtThemeTokens tokens, RescanState state) {
    final total = state.normalizeTotal;
    final processed = state.normalizeProcessed;
    final value = total == 0 ? null : (processed / total).clamp(0.0, 1.0);
    final label = total == 0
        ? t.bootstrap.validationRescan.labels.scanningEntries
        : t.bootstrap.validationRescan.labels.normalizedOf(
            processed: formatCount(processed),
            total: formatCount(total),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: tokens.fontBody),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: value),
        ),
        const SizedBox(height: 12),
        Text(
          t.bootstrap.validationRescan.labels.upgradingLegacy,
          style: tokens.fontBody.copyWith(
            fontSize: 11,
            color: tokens.textDim,
          ),
        ),
      ],
    );
  }

  Widget _preparingBody(TwmtThemeTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          t.bootstrap.validationRescan.labels.preparing,
          style: tokens.fontBody,
        ),
        const SizedBox(height: 12),
        const ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          child: LinearProgressIndicator(),
        ),
      ],
    );
  }

  Widget _planBody(TwmtThemeTokens tokens, RescanPlan plan) {
    final totalAll = plan.total + plan.already;
    final bodyText = plan.isResume
        ? t.bootstrap.validationRescan.plan.resumeBody(
            already: formatCount(plan.already),
            totalAll: formatCount(totalAll),
            remaining: formatCount(plan.total),
            estimated: formatDuration(plan.estimated),
          )
        : t.bootstrap.validationRescan.plan.freshBody(
            total: formatCount(plan.total),
            estimated: formatDuration(plan.estimated),
          );

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
            label: plan.isResume
                ? t.bootstrap.validationRescan.actions.kContinue
                : t.bootstrap.validationRescan.actions.startRescan,
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

  Widget _progressBody(TwmtThemeTokens tokens, RescanProgress? progress) {
    // The rescan service only emits progress once a commit batch lands
    // (every ~10k rows), so the first event can be seconds away. Show an
    // indeterminate bar in the meantime rather than leaving the dialog
    // looking like it's still awaiting user input.
    final double? value;
    final String headline;
    if (progress == null) {
      value = null;
      headline = t.bootstrap.validationRescan.labels.startingRescan;
    } else {
      value = progress.total == 0
          ? 1.0
          : (progress.done / progress.total).clamp(0.0, 1.0);
      headline = progress.eta == null
          ? t.bootstrap.validationRescan.labels.rescannedOf(
              done: formatCount(progress.done),
              total: formatCount(progress.total),
            )
          : t.bootstrap.validationRescan.labels.rescannedOfEta(
              done: formatCount(progress.done),
              total: formatCount(progress.total),
              eta: formatDuration(progress.eta!),
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(headline, style: tokens.fontBody),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: value),
        ),
        const SizedBox(height: 12),
        Text(
          t.bootstrap.validationRescan.labels.closingWillPause,
          style: tokens.fontBody.copyWith(
            fontSize: 11,
            color: tokens.textDim,
          ),
        ),
      ],
    );
  }
}
