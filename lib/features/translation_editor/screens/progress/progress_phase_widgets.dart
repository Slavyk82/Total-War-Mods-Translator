import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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
                'Current Phase',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isPaused ? 'Paused' : getPhaseDisplayName(phase),
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
                  'LLM Exchange Logs (${logs.length})',
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
                        'No LLM exchanges yet. Logs will appear as translation progresses.',
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
  if (phase == null) return 'Initializing...';

  switch (phase) {
    case TranslationPhase.initializing:
      return 'Initializing...';
    case TranslationPhase.tmExactLookup:
      return 'Checking Translation Memory (Exact)';
    case TranslationPhase.tmFuzzyLookup:
      return 'Checking Translation Memory (Fuzzy)';
    case TranslationPhase.buildingPrompt:
      return 'Building Translation Prompt';
    case TranslationPhase.llmTranslation:
      return 'Translating with LLM';
    case TranslationPhase.validating:
      return 'Validating Translations';
    case TranslationPhase.saving:
      return 'Saving Translations';
    case TranslationPhase.updatingTm:
      return 'Updating Translation Memory';
    case TranslationPhase.finalizing:
      return 'Finalizing Batch';
    case TranslationPhase.completed:
      return 'Completed';
  }
}

/// Get estimated time display string
String getEstimatedTimeDisplay(int seconds) {
  if (seconds < 60) {
    return 'About $seconds seconds remaining';
  } else {
    final minutes = (seconds / 60).ceil();
    return 'About $minutes minute${minutes > 1 ? 's' : ''} remaining';
  }
}

/// Get elapsed time display string
String getElapsedTimeDisplay(DateTime startTime) {
  final elapsed = DateTime.now().difference(startTime);
  final seconds = elapsed.inSeconds;

  if (seconds < 60) {
    return 'Elapsed: $seconds seconds';
  } else {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return 'Elapsed: $minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
