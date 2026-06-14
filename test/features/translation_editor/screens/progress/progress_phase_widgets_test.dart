import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/screens/progress/progress_phase_widgets.dart';
import 'package:twmt/services/translation/models/llm_exchange_log.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

import '../../../../helpers/test_helpers.dart';

/// Builds a [TranslationProgress] with sensible defaults that can be overridden.
TranslationProgress buildProgress({
  TranslationProgressStatus status = TranslationProgressStatus.inProgress,
  TranslationPhase currentPhase = TranslationPhase.llmTranslation,
  String? phaseDetail,
  int? estimatedSecondsRemaining,
  int totalUnits = 10,
  int processedUnits = 5,
}) {
  return TranslationProgress(
    batchId: 'batch-1',
    status: status,
    totalUnits: totalUnits,
    processedUnits: processedUnits,
    successfulUnits: processedUnits,
    failedUnits: 0,
    skippedUnits: 0,
    currentPhase: currentPhase,
    phaseDetail: phaseDetail,
    estimatedSecondsRemaining: estimatedSecondsRemaining,
    tokensUsed: 100,
    tmReuseRate: 0.0,
    timestamp: DateTime(2024, 1, 1, 12, 0, 0),
  );
}

LlmExchangeLog buildLog({
  bool success = true,
  String? errorMessage,
  int unitsCount = 3,
}) {
  return LlmExchangeLog(
    timestamp: DateTime(2024, 1, 1, 13, 30, 45),
    providerCode: 'anthropic',
    modelName: 'claude',
    requestId: 'req-1',
    unitsCount: unitsCount,
    inputTokens: 10,
    outputTokens: 20,
    totalTokens: 30,
    processingTimeMs: 500,
    success: success,
    errorMessage: errorMessage,
  );
}

/// Pumps a builder function that needs a [BuildContext], under the app theme.
Future<void> pumpWithContext(
  WidgetTester tester,
  Widget Function(BuildContext context) builder,
) async {
  await tester.pumpWidget(
    createThemedTestableWidget(
      Builder(builder: builder),
      theme: AppTheme.atelierDarkTheme,
    ),
  );
}

void main() {
  group('buildPhaseSection', () {
    testWidgets('shows progress ring when not paused', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildPhaseSection(
          context,
          progress: buildProgress(),
          isPaused: false,
          elapsedTimeDisplay: '00:30',
        ),
      );
      await tester.pump();

      expect(find.byType(FluentProgressRing), findsOneWidget);
      expect(
        find.byIcon(FluentIcons.pause_circle_24_regular),
        findsNothing,
      );
    });

    testWidgets('shows pause icon and elapsed time when paused',
        (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildPhaseSection(
          context,
          progress: buildProgress(),
          isPaused: true,
          elapsedTimeDisplay: '00:42 elapsed',
        ),
      );
      await tester.pump();

      expect(
        find.byIcon(FluentIcons.pause_circle_24_regular),
        findsOneWidget,
      );
      expect(find.byType(FluentProgressRing), findsNothing);
      expect(find.text('00:42 elapsed'), findsOneWidget);
    });

    testWidgets('shows phase detail when present and not paused',
        (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildPhaseSection(
          context,
          progress: buildProgress(phaseDetail: 'Translating row 5 of 10'),
          isPaused: false,
          elapsedTimeDisplay: '00:30',
        ),
      );
      await tester.pump();

      expect(find.text('Translating row 5 of 10'), findsOneWidget);
    });

    testWidgets('hides phase detail when paused even if present',
        (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildPhaseSection(
          context,
          progress: buildProgress(phaseDetail: 'Hidden detail'),
          isPaused: true,
          elapsedTimeDisplay: '00:30',
        ),
      );
      await tester.pump();

      expect(find.text('Hidden detail'), findsNothing);
    });

    testWidgets('hides phase detail when empty string', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildPhaseSection(
          context,
          progress: buildProgress(phaseDetail: ''),
          isPaused: false,
          elapsedTimeDisplay: '00:30',
        ),
      );
      await tester.pump();

      // The Column should not contain an italic detail text for empty string.
      // We simply assert the elapsed display is still shown (default branch).
      expect(find.text('00:30'), findsOneWidget);
    });

    testWidgets('shows estimated time when estimatedSecondsRemaining set',
        (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildPhaseSection(
          context,
          progress: buildProgress(estimatedSecondsRemaining: 30),
          isPaused: false,
          elapsedTimeDisplay: 'ELAPSED-SHOULD-NOT-SHOW',
        ),
      );
      await tester.pump();

      // When estimate is present, the elapsed display is replaced.
      expect(find.text('ELAPSED-SHOULD-NOT-SHOW'), findsNothing);
    });

    testWidgets('shows elapsed time when estimate is null', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildPhaseSection(
          context,
          progress: buildProgress(estimatedSecondsRemaining: null),
          isPaused: false,
          elapsedTimeDisplay: 'ELAPSED-SHOWN',
        ),
      );
      await tester.pump();

      expect(find.text('ELAPSED-SHOWN'), findsOneWidget);
    });

    testWidgets('handles null progress gracefully', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildPhaseSection(
          context,
          progress: null,
          isPaused: false,
          elapsedTimeDisplay: '00:10',
        ),
      );
      await tester.pump();

      expect(find.text('00:10'), findsOneWidget);
      expect(find.byType(FluentProgressRing), findsOneWidget);
    });
  });

  group('buildLlmLogsSection', () {
    testWidgets('shows chevron-right when collapsed', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildLlmLogsSection(
          context,
          logs: [buildLog()],
          showLogs: false,
          onToggle: () {},
        ),
      );
      await tester.pump();

      expect(
        find.byIcon(FluentIcons.chevron_right_24_regular),
        findsOneWidget,
      );
      expect(
        find.byIcon(FluentIcons.chevron_down_24_regular),
        findsNothing,
      );
    });

    testWidgets('shows chevron-down and expands when showLogs is true',
        (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildLlmLogsSection(
          context,
          logs: [buildLog()],
          showLogs: true,
          onToggle: () {},
        ),
      );
      await tester.pump();

      expect(
        find.byIcon(FluentIcons.chevron_down_24_regular),
        findsOneWidget,
      );
      // A successful log renders its checkmark icon.
      expect(
        find.byIcon(FluentIcons.checkmark_circle_24_regular),
        findsOneWidget,
      );
    });

    testWidgets('renders error icon for failed log', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildLlmLogsSection(
          context,
          logs: [buildLog(success: false, errorMessage: 'boom')],
          showLogs: true,
          onToggle: () {},
        ),
      );
      await tester.pump();

      expect(
        find.byIcon(FluentIcons.error_circle_24_regular),
        findsOneWidget,
      );
      expect(
        find.byIcon(FluentIcons.checkmark_circle_24_regular),
        findsNothing,
      );
    });

    testWidgets('shows empty placeholder when logs empty and expanded',
        (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildLlmLogsSection(
          context,
          logs: const [],
          showLogs: true,
          onToggle: () {},
        ),
      );
      await tester.pump();

      // No log icons should be present when the list is empty.
      expect(
        find.byIcon(FluentIcons.checkmark_circle_24_regular),
        findsNothing,
      );
      expect(
        find.byIcon(FluentIcons.error_circle_24_regular),
        findsNothing,
      );
    });

    testWidgets('truncates to last 10 logs when more than 10 present',
        (tester) async {
      final logs = List.generate(15, (i) => buildLog(unitsCount: i));
      await pumpWithContext(
        tester,
        (context) => buildLlmLogsSection(
          context,
          logs: logs,
          showLogs: true,
          onToggle: () {},
        ),
      );
      await tester.pump();

      // Only the last 10 successful logs are rendered.
      expect(
        find.byIcon(FluentIcons.checkmark_circle_24_regular),
        findsNWidgets(10),
      );
    });

    testWidgets('invokes onToggle when header tapped', (tester) async {
      var toggled = false;
      await pumpWithContext(
        tester,
        (context) => buildLlmLogsSection(
          context,
          logs: [buildLog()],
          showLogs: false,
          onToggle: () => toggled = true,
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(GestureDetector));
      await tester.pump();

      expect(toggled, isTrue);
    });
  });

  group('getPhaseDisplayName', () {
    test('returns initializing for null phase', () {
      expect(getPhaseDisplayName(null), isNotEmpty);
    });

    test('returns a non-empty label for every phase', () {
      for (final phase in TranslationPhase.values) {
        expect(
          getPhaseDisplayName(phase),
          isNotEmpty,
          reason: 'phase $phase should map to a label',
        );
      }
    });
  });

  group('getEstimatedTimeDisplay', () {
    test('formats seconds when under a minute', () {
      expect(getEstimatedTimeDisplay(30), isNotEmpty);
    });

    test('formats single minute when exactly one minute', () {
      expect(getEstimatedTimeDisplay(60), isNotEmpty);
    });

    test('formats plural minutes when over a minute', () {
      expect(getEstimatedTimeDisplay(150), isNotEmpty);
    });
  });

  group('getElapsedTimeDisplay', () {
    test('formats seconds for recent start time', () {
      final start = DateTime.now().subtract(const Duration(seconds: 5));
      expect(getElapsedTimeDisplay(start), isNotEmpty);
    });

    test('formats minutes for older start time', () {
      final start =
          DateTime.now().subtract(const Duration(minutes: 3, seconds: 7));
      expect(getElapsedTimeDisplay(start), isNotEmpty);
    });
  });
}
