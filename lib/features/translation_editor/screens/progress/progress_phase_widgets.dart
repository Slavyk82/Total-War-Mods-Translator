import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/services/translation/models/llm_exchange_log.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Builds the current phase section
Widget buildPhaseSection(
  BuildContext context, {
  required TranslationProgress? progress,
  required bool isPaused,
  required String elapsedTimeDisplay,
}) {
  final phase = progress?.currentPhase;
  final phaseDetail = progress?.phaseDetail;
  final theme = Theme.of(context);

  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        if (isPaused)
          Icon(
            FluentIcons.pause_circle_24_regular,
            size: 32,
            color: Colors.orange.shade700,
          )
        else
          SizedBox(
            width: 32,
            height: 32,
            child: FluentProgressRing(
              strokeWidth: 3,
              color: theme.colorScheme.primary,
            ),
          ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.translationEditor.progress.translation.currentPhase,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isPaused ? t.translationEditor.progress.translation.paused : getPhaseDisplayName(phase),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              // Phase detail - shows what's happening in detail
              if (!isPaused && phaseDetail != null && phaseDetail.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  phaseDetail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary.withValues(alpha: 0.8),
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 4),
              if (progress?.estimatedSecondsRemaining != null)
                Text(
                  getEstimatedTimeDisplay(progress!.estimatedSecondsRemaining!),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                )
              else
                Text(
                  elapsedTimeDisplay,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Builds the LLM logs section with expandable view
Widget buildLlmLogsSection(
  BuildContext context, {
  required List<LlmExchangeLog> logs,
  required bool showLogs,
  required VoidCallback onToggle,
}) {
  final lastLogs = logs.length > 10 ? logs.sublist(logs.length - 10) : logs;
  final theme = Theme.of(context);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  showLogs
                      ? FluentIcons.chevron_down_24_regular
                      : FluentIcons.chevron_right_24_regular,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  t.translationEditor.progress.translation.llmLogs(count: logs.length),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Icon(
                  FluentIcons.info_24_regular,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
      if (showLogs) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
            ),
          ),
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            child: lastLogs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        t.translationEditor.progress.translation.llmLogsEmpty,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final log in lastLogs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                log.success
                                    ? FluentIcons.checkmark_circle_24_regular
                                    : FluentIcons.error_circle_24_regular,
                                size: 16,
                                color: log.success
                                    ? Colors.green.shade700
                                    : theme.colorScheme.error,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  log.compactDisplay,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontFamily: 'Consolas',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    ],
  );
}

/// Get display name for translation phase
String getPhaseDisplayName(TranslationPhase? phase) {
  final phases = t.translationEditor.progress.translation.phases;
  if (phase == null) return phases.initializing;

  switch (phase) {
    case TranslationPhase.initializing:
      return phases.initializing;
    case TranslationPhase.tmExactLookup:
      return phases.tmExactLookup;
    case TranslationPhase.tmFuzzyLookup:
      return phases.tmFuzzyLookup;
    case TranslationPhase.buildingPrompt:
      return phases.buildingPrompt;
    case TranslationPhase.llmTranslation:
      return phases.llmTranslation;
    case TranslationPhase.validating:
      return phases.validating;
    case TranslationPhase.saving:
      return phases.saving;
    case TranslationPhase.updatingTm:
      return phases.updatingTm;
    case TranslationPhase.finalizing:
      return phases.finalizing;
    case TranslationPhase.completed:
      return phases.completed;
  }
}

/// Get estimated time display string
String getEstimatedTimeDisplay(int seconds) {
  final est = t.translationEditor.progress.translation.estimatedRemaining;
  if (seconds < 60) {
    return est.seconds(n: seconds);
  } else {
    final minutes = (seconds / 60).ceil();
    return minutes > 1 ? est.minutesPlural(n: minutes) : est.minutes(n: minutes);
  }
}

/// Get elapsed time display string
String getElapsedTimeDisplay(DateTime startTime) {
  final elapsed = DateTime.now().difference(startTime);
  final seconds = elapsed.inSeconds;
  final el = t.translationEditor.progress.translation.elapsed;

  if (seconds < 60) {
    return el.seconds(n: seconds);
  } else {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return el.minutes(m: minutes, s: remainingSeconds.toString().padLeft(2, '0'));
  }
}
