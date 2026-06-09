import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/logs/log_console_window.dart';

class _FakeLogger implements ILoggingService {
  final _controller = StreamController<LogEntry>.broadcast();
  final List<LogEntry> _recent = [];

  void seed(LogEntry e) => _recent.add(e);
  void emit(LogEntry e) {
    _recent.add(e);
    _controller.add(e);
  }

  void close() => _controller.close();

  @override
  List<LogEntry> get recentLogs => List.unmodifiable(_recent);
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
  void error(String message, [dynamic error, StackTrace? stackTrace]) {}
}

LogEntry _entry(String level, String message) =>
    LogEntry(timestamp: DateTime(2026, 1, 1), level: level, message: message);

Future<void> _pump(WidgetTester tester, _FakeLogger fake) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [loggingServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: const Scaffold(
          body: Stack(children: [LogConsoleWindow()]),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('seeds from recentLogs', (tester) async {
    final fake = _FakeLogger()..seed(_entry('INFO', 'seeded-line'));
    addTearDown(fake.close);
    await _pump(tester, fake);
    expect(find.textContaining('seeded-line'), findsOneWidget);
  });

  testWidgets('appends live entries from the stream', (tester) async {
    final fake = _FakeLogger();
    addTearDown(fake.close);
    await _pump(tester, fake);
    fake.emit(_entry('INFO', 'live-line'));
    await tester.pump(); // deliver broadcast microtask
    await tester.pump(); // flush rebuild
    expect(find.textContaining('live-line'), findsOneWidget);
  });

  testWidgets('level filter hides deselected levels', (tester) async {
    final fake = _FakeLogger()
      ..seed(_entry('INFO', 'an-info'))
      ..seed(_entry('ERROR', 'an-error'));
    addTearDown(fake.close);
    await _pump(tester, fake);
    expect(find.textContaining('an-info'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('log-level-INFO')));
    await tester.pump();

    expect(find.textContaining('an-info'), findsNothing);
    expect(find.textContaining('an-error'), findsOneWidget);
  });

  testWidgets('search filters lines', (tester) async {
    final fake = _FakeLogger()
      ..seed(_entry('INFO', 'apple'))
      ..seed(_entry('INFO', 'banana'));
    addTearDown(fake.close);
    await _pump(tester, fake);

    await tester.enterText(
        find.byKey(LogConsoleWindow.searchFieldKey), 'banana');
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(SelectableText),
        matching: find.textContaining('banana'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('apple'), findsNothing);
  });

  testWidgets('clear empties the view', (tester) async {
    final fake = _FakeLogger()..seed(_entry('INFO', 'will-be-cleared'));
    addTearDown(fake.close);
    await _pump(tester, fake);
    expect(find.textContaining('will-be-cleared'), findsOneWidget);

    await tester.tap(find.byKey(LogConsoleWindow.clearButtonKey));
    await tester.pump();

    expect(find.textContaining('will-be-cleared'), findsNothing);
  });
}
