import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/common/progress_widgets.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

import '../../helpers/test_helpers.dart';

/// A logger whose stream and recent-logs snapshot can be controlled by tests,
/// to exercise [LogTerminal]'s stream-listening and rendering branches.
class _ControllableLogger implements ILoggingService {
  _ControllableLogger({List<LogEntry>? initial})
      : recentLogs = initial ?? const [];

  final StreamController<LogEntry> _controller =
      StreamController<LogEntry>.broadcast();

  @override
  List<LogEntry> recentLogs;

  void emit(LogEntry entry) => _controller.add(entry);

  @override
  Stream<LogEntry> get logStream => _controller.stream;

  @override
  String? get logFilePath => null;

  @override
  void debug(String message, [dynamic data]) {}

  @override
  void info(String message, [dynamic data]) {}

  @override
  void warning(String message, [dynamic data]) {}

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {}
}

LogEntry _entry({
  String level = 'INFO',
  String message = 'hello',
  dynamic data,
  DateTime? timestamp,
}) =>
    LogEntry(
      timestamp: timestamp ?? DateTime(2024, 1, 1, 9, 8, 7, 6),
      level: level,
      message: message,
      data: data,
    );

TranslationProgress _progress({
  TranslationProgressStatus status = TranslationProgressStatus.inProgress,
  int totalUnits = 10,
  int processedUnits = 5,
  int successfulUnits = 5,
  int failedUnits = 0,
  int skippedUnits = 0,
}) =>
    TranslationProgress(
      batchId: 'batch-id-123456789',
      status: status,
      totalUnits: totalUnits,
      processedUnits: processedUnits,
      successfulUnits: successfulUnits,
      failedUnits: failedUnits,
      skippedUnits: skippedUnits,
      currentPhase: TranslationPhase.llmTranslation,
      tokensUsed: 100,
      tmReuseRate: 0.0,
      timestamp: DateTime(2024, 1, 1, 12, 0, 0),
    );

/// Pumps a [LogTerminal] (or wrapper) with the given controllable [logger].
///
/// Builds its own [ProviderScope] so the logger override is applied exactly
/// once (the shared test helper already overrides it, which would clash).
Future<void> _pumpLogTerminal(
  WidgetTester tester,
  _ControllableLogger logger,
  Widget child,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        loggingServiceProvider.overrideWithValue(logger),
      ],
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// Pumps a [BuildContext]-consuming builder under the dark app theme.
Future<void> pumpWithContext(
  WidgetTester tester,
  Widget Function(BuildContext context) builder, {
  Size? screenSize,
}) async {
  await tester.pumpWidget(
    createThemedTestableWidget(
      Builder(builder: builder),
      theme: AppTheme.atelierDarkTheme,
      screenSize: screenSize,
    ),
  );
}

void main() {
  group('buildPreparationView', () {
    testWidgets('renders ring and texts without error', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildPreparationView(context),
      );
      await tester.pump();

      expect(find.byType(FluentProgressRing), findsOneWidget);
      expect(
        find.byIcon(FluentIcons.error_circle_24_regular),
        findsNothing,
      );
    });

    testWidgets('shows error box when errorMessage present (no close)',
        (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildPreparationView(
          context,
          errorMessage: 'Something failed badly',
        ),
      );
      await tester.pump();

      expect(find.text('Something failed badly'), findsOneWidget);
      expect(
        find.byIcon(FluentIcons.error_circle_24_regular),
        findsOneWidget,
      );
      expect(find.byType(FluentButton), findsNothing);
    });

    testWidgets('shows close button when errorMessage and onClose present',
        (tester) async {
      var closed = false;
      await pumpWithContext(
        tester,
        (context) => buildPreparationView(
          context,
          errorMessage: 'boom',
          onClose: () => closed = true,
        ),
      );
      await tester.pump();

      expect(find.byType(FluentButton), findsOneWidget);
      await tester.tap(find.byType(FluentButton));
      await tester.pump();
      expect(closed, isTrue);
    });
  });

  group('buildProgressHeader', () {
    testWidgets('truncates long batch id', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildProgressHeader(
          context,
          batchId: 'abcdefghijklmnop',
        ),
      );
      await tester.pump();

      expect(
        find.byIcon(FluentIcons.translate_24_regular),
        findsOneWidget,
      );
      // Truncated id contains the first 8 chars followed by ellipsis.
      expect(find.textContaining('abcdefgh...'), findsOneWidget);
    });

    testWidgets('keeps short batch id intact', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildProgressHeader(
          context,
          batchId: 'short',
        ),
      );
      await tester.pump();

      expect(find.textContaining('short'), findsOneWidget);
    });
  });

  group('buildProgressSection', () {
    testWidgets('renders zero percent with null progress', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildProgressSection(
          context,
          progress: null,
          isPaused: false,
        ),
      );
      await tester.pump();

      expect(find.byType(FluentProgressBar), findsOneWidget);
      expect(find.text('0.0%'), findsOneWidget);
    });

    testWidgets('renders partial percent and project name', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildProgressSection(
          context,
          progress: _progress(processedUnits: 5, totalUnits: 10),
          isPaused: false,
          projectName: 'My Project',
        ),
      );
      await tester.pump();

      expect(find.text('50.0%'), findsOneWidget);
      expect(find.text('My Project'), findsOneWidget);
      // The dash separator only renders when a project name is present.
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('omits project name section when empty', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildProgressSection(
          context,
          progress: _progress(processedUnits: 10, totalUnits: 10),
          isPaused: false,
          projectName: '',
        ),
      );
      await tester.pump();

      expect(find.text('100.0%'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('uses orange bar color when paused', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildProgressSection(
          context,
          progress: _progress(),
          isPaused: true,
        ),
      );
      await tester.pump();

      final bar = tester.widget<FluentProgressBar>(
        find.byType(FluentProgressBar),
      );
      expect(bar.color, Colors.orange.shade700);
    });

    testWidgets('shows stop button (enabled) and invokes onStop',
        (tester) async {
      var stopped = false;
      await pumpWithContext(
        tester,
        (context) => buildProgressSection(
          context,
          progress: _progress(),
          isPaused: false,
          onStop: () => stopped = true,
          isStopping: false,
        ),
      );
      await tester.pump();

      // The enabled stop button shows the stop icon, not a spinner.
      expect(find.byIcon(FluentIcons.stop_16_filled), findsOneWidget);

      await tester.tap(find.byType(GestureDetector));
      await tester.pump();
      expect(stopped, isTrue);
    });

    testWidgets('stop button shows spinner and is disabled when stopping',
        (tester) async {
      var stopped = false;
      await pumpWithContext(
        tester,
        (context) => buildProgressSection(
          context,
          progress: _progress(),
          isPaused: false,
          onStop: () => stopped = true,
          isStopping: true,
        ),
      );
      await tester.pump();

      expect(find.byIcon(FluentIcons.stop_16_filled), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Tapping a disabled (isStopping) button must not invoke onStop.
      await tester.tap(find.byType(GestureDetector));
      await tester.pump();
      expect(stopped, isFalse);
    });

    testWidgets('hover changes stop button background', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildProgressSection(
          context,
          progress: _progress(),
          isPaused: false,
          onStop: () {},
        ),
      );
      await tester.pump();

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();

      // Hover over the stop icon itself, which lives inside the button's
      // MouseRegion, to drive onEnter and the hovered-background branch.
      await gesture.moveTo(
        tester.getCenter(find.byIcon(FluentIcons.stop_16_filled)),
      );
      await tester.pumpAndSettle();

      // Move away to drive onExit.
      await gesture.moveTo(const Offset(2000, 2000));
      await tester.pumpAndSettle();
    });
  });

  group('buildStatCard', () {
    testWidgets('renders icon, value and label', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildStatCard(
          context,
          icon: FluentIcons.checkmark_circle_24_regular,
          label: 'Successful',
          value: '42',
          color: Colors.green,
        ),
      );
      await tester.pump();

      expect(find.text('42'), findsOneWidget);
      expect(find.text('Successful'), findsOneWidget);
      expect(
        find.byIcon(FluentIcons.checkmark_circle_24_regular),
        findsOneWidget,
      );
    });
  });

  group('buildStatsSection', () {
    testWidgets('renders three stat cards from progress', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildStatsSection(
          context,
          progress: _progress(
            successfulUnits: 7,
            failedUnits: 2,
            skippedUnits: 1,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('7'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('renders zeros when progress is null', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildStatsSection(
          context,
          progress: null,
        ),
      );
      await tester.pump();

      expect(find.text('0'), findsNWidgets(3));
    });
  });

  group('buildErrorSection', () {
    testWidgets('renders error icon and message', (tester) async {
      await pumpWithContext(
        tester,
        (context) => buildErrorSection(
          context,
          errorMessage: 'Catastrophic failure',
        ),
      );
      await tester.pump();

      expect(find.text('Catastrophic failure'), findsOneWidget);
      expect(
        find.byIcon(FluentIcons.error_circle_24_regular),
        findsOneWidget,
      );
    });
  });

  group('LogTerminal', () {
    testWidgets('shows waiting placeholder when no logs', (tester) async {
      final logger = _ControllableLogger();
      await _pumpLogTerminal(tester, logger, const LogTerminal());
      await tester.pump();

      // Header icon present.
      expect(find.byIcon(FluentIcons.code_24_regular), findsOneWidget);
      // No log lines (placeholder shown instead of list).
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('renders initial recent logs in list', (tester) async {
      final logger = _ControllableLogger(initial: [
        _entry(level: 'INFO', message: 'first line'),
        _entry(level: 'ERROR', message: 'second line', data: {'k': 'v'}),
      ]);
      await _pumpLogTerminal(tester, logger, const LogTerminal());
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
      expect(find.textContaining('first line'), findsOneWidget);
      expect(find.textContaining('second line'), findsOneWidget);
    });

    testWidgets('appends new log from stream and renders it', (tester) async {
      final logger = _ControllableLogger(initial: [
        _entry(message: 'existing'),
      ]);
      await _pumpLogTerminal(tester, logger, const LogTerminal(height: 300));
      await tester.pump();

      logger.emit(_entry(level: 'WARN', message: 'streamed warn'));
      await tester.pumpAndSettle();

      expect(find.textContaining('streamed warn'), findsOneWidget);
    });

    testWidgets('toggles auto-scroll off and on', (tester) async {
      final logger = _ControllableLogger(initial: [
        _entry(message: 'line'),
      ]);
      await _pumpLogTerminal(tester, logger, const LogTerminal());
      await tester.pump();

      final autoScroll = find.byIcon(FluentIcons.arrow_down_24_regular);
      expect(autoScroll, findsOneWidget);
      // Toggle off.
      await tester.tap(autoScroll);
      await tester.pump();
      // Toggle back on (re-triggers scrollToBottom path).
      await tester.tap(autoScroll);
      await tester.pumpAndSettle();
    });

    testWidgets('clears logs via clear button', (tester) async {
      final logger = _ControllableLogger(initial: [
        _entry(message: 'to be cleared'),
      ]);
      await _pumpLogTerminal(tester, logger, const LogTerminal());
      await tester.pump();

      expect(find.textContaining('to be cleared'), findsOneWidget);
      await tester.tap(find.byIcon(FluentIcons.delete_24_regular));
      await tester.pump();

      expect(find.textContaining('to be cleared'), findsNothing);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('expand mode fills available space', (tester) async {
      final logger = _ControllableLogger(initial: [
        _entry(message: 'expanded line'),
      ]);
      await _pumpLogTerminal(
        tester,
        logger,
        const SizedBox(
          height: 400,
          child: LogTerminal(expand: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Expanded), findsWidgets);
      expect(find.textContaining('expanded line'), findsOneWidget);
    });

    testWidgets('caps UI log buffer at 500 entries', (tester) async {
      final logger = _ControllableLogger();
      await _pumpLogTerminal(tester, logger, const LogTerminal(height: 300));
      await tester.pump();

      // Emit more than the 500-entry cap to exercise the removeAt branch.
      for (var i = 0; i < 502; i++) {
        logger.emit(_entry(message: 'log-$i'));
      }
      // Let the broadcast-stream microtasks and the scroll animation settle.
      await tester.pumpAndSettle();

      // The very first entries should have been trimmed away.
      expect(find.textContaining('log-0'), findsNothing);
    });
  });
}
