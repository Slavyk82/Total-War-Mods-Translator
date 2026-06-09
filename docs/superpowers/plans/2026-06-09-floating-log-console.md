# Floating Log Console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a draggable, resizable, non-blocking floating window that shows the current session's logs live, opened from a "Logs" button under "Settings" in the sidebar.

**Architecture:** A Riverpod-codegen `Notifier` (`LogWindowController`) holds only the window visibility (closed/open/minimized). A `ConsumerStatefulWidget` (`LogConsoleWindow`) — mounted by `LogConsoleOverlay` inside `MaterialApp.router`'s `builder` `Stack` so it floats above all routes but below modal dialogs — seeds from `ILoggingService.recentLogs` and appends from `logStream` live. Position/size/filters/search are local widget state (not persisted). A sidebar tile toggles the controller.

**Tech Stack:** Flutter, Riverpod (codegen `@riverpod` + `build_runner`), slang i18n (`dart run slang`, `base_locale` fallback), `fluentui_system_icons`, `flutter_test`.

---

## File Structure

**Create:**
- `lib/providers/log_window_provider.dart` — visibility enum + `LogWindowController` notifier. (codegen → `log_window_provider.g.dart`)
- `lib/widgets/logs/log_console_window.dart` — the floating window widget (full + minimized rendering).
- `lib/widgets/logs/log_console_overlay.dart` — thin `ConsumerWidget` that mounts the window when not closed.
- `test/services/shared/logging_service_test.dart` — buffer-cap test.
- `test/providers/log_window_provider_test.dart` — visibility transitions.
- `test/widgets/logs/log_console_window_test.dart` — seed/live/filter/search/clear.

**Modify:**
- `lib/services/shared/i_logging_service.dart` — add `String? get logFilePath;`.
- `lib/services/shared/logging_service.dart` — `maxRecentLogs` 500 → 5000.
- `lib/services/shared/log_entry.dart` — add `static int colorForLevel(String)`; delegate `levelColor`.
- `lib/main.dart` — wrap router child in a `Stack` with `LogConsoleOverlay`.
- `lib/widgets/navigation/navigation_sidebar.dart` — add `_LogConsoleButton` under the nav groups + `logButtonKey`.
- `lib/i18n/en/widgets.i18n.json`, `lib/i18n/fr/widgets.i18n.json` — `navigationSidebar.items.logs` + `logConsole` block.
- `test/widgets/navigation/navigation_sidebar_test.dart` — add Logs-button test.

---

## Task 1: Logging service — capacity bump + path & color exposure

**Files:**
- Modify: `lib/services/shared/log_entry.dart`
- Modify: `lib/services/shared/i_logging_service.dart`
- Modify: `lib/services/shared/logging_service.dart:37` (`maxRecentLogs`)
- Test: `test/services/shared/logging_service_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/services/shared/logging_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/shared/log_entry.dart';

void main() {
  group('LoggingService recent-logs buffer', () {
    setUp(() => LoggingService.instance.clearRecentLogs());

    test('caps recentLogs at maxRecentLogs and evicts oldest', () {
      expect(LoggingService.maxRecentLogs, 5000);
      final logger = LoggingService.instance;
      for (var i = 0; i < LoggingService.maxRecentLogs + 10; i++) {
        logger.info('entry $i');
      }
      expect(logger.recentLogs.length, LoggingService.maxRecentLogs);
      expect(
        logger.recentLogs.last.message,
        'entry ${LoggingService.maxRecentLogs + 9}',
      );
    });
  });

  group('LogEntry.colorForLevel', () {
    test('maps known levels and defaults unknown to gray', () {
      expect(LogEntry.colorForLevel('ERROR'), 0xFFE53935);
      expect(LogEntry.colorForLevel('WARN'), 0xFFFFA726);
      expect(LogEntry.colorForLevel('INFO'), 0xFF42A5F5);
      expect(LogEntry.colorForLevel('DEBUG'), 0xFF78909C);
      expect(LogEntry.colorForLevel('ANYTHING'), 0xFF78909C);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/shared/logging_service_test.dart`
Expected: FAIL — `maxRecentLogs` is 500 (not 5000) and `LogEntry.colorForLevel` is undefined.

- [ ] **Step 3a: Refactor `log_entry.dart` to expose a static color map**

In `lib/services/shared/log_entry.dart`, replace the `levelColor` getter (lines ~25-38) with:

```dart
  /// Get the color (ARGB int) for this log level (for terminal display).
  int get levelColor => colorForLevel(level);

  /// ARGB color for a log level string. Shared so UI code can color a level
  /// without constructing a [LogEntry].
  static int colorForLevel(String level) {
    switch (level) {
      case 'ERROR':
        return 0xFFE53935; // Red
      case 'WARN':
        return 0xFFFFA726; // Orange
      case 'INFO':
        return 0xFF42A5F5; // Blue
      case 'DEBUG':
      default:
        return 0xFF78909C; // Gray
    }
  }
```

- [ ] **Step 3b: Add `logFilePath` to the interface**

In `lib/services/shared/i_logging_service.dart`, add inside `abstract class ILoggingService` (after the `recentLogs` getter):

```dart

  /// Absolute path of the current day's log file, or null if logging has not
  /// been initialized. Its parent directory holds all session log files.
  String? get logFilePath;
```

(The concrete `LoggingService` already declares `String? get logFilePath` at line ~179, so it now satisfies the interface — no change needed there for the getter.)

- [ ] **Step 3c: Bump the buffer cap**

In `lib/services/shared/logging_service.dart`, change line 37:

```dart
  static const int maxRecentLogs = 5000;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/shared/logging_service_test.dart`
Expected: PASS (both groups).

- [ ] **Step 5: Verify no analyzer regressions in touched files**

Run: `flutter analyze lib/services/shared`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/services/shared/log_entry.dart lib/services/shared/i_logging_service.dart lib/services/shared/logging_service.dart test/services/shared/logging_service_test.dart
git commit -m "feat(logging): raise session buffer to 5000, expose logFilePath and static level color"
```

---

## Task 2: Log window visibility provider

**Files:**
- Create: `lib/providers/log_window_provider.dart`
- Test: `test/providers/log_window_provider_test.dart`

- [ ] **Step 1: Write the provider source**

Create `lib/providers/log_window_provider.dart`:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'log_window_provider.g.dart';

/// Visibility state of the floating log console window.
enum LogWindowVisibility { closed, open, minimized }

/// App-level controller for the floating log console.
///
/// Holds ONLY the visibility. The window widget owns its own position, size,
/// level filters and search text — intentionally not persisted (reset on each
/// open). Kept alive because the toggle is app-global UI state.
@Riverpod(keepAlive: true)
class LogWindowController extends _$LogWindowController {
  @override
  LogWindowVisibility build() => LogWindowVisibility.closed;

  /// Open from closed or minimized.
  void open() => state = LogWindowVisibility.open;

  /// Fully hide the window.
  void close() => state = LogWindowVisibility.closed;

  /// Collapse to the minimized bar.
  void minimize() => state = LogWindowVisibility.minimized;

  /// Restore from minimized to the full window.
  void restore() => state = LogWindowVisibility.open;

  /// Sidebar button behavior: open when not open, otherwise close.
  void toggleOpen() {
    state = state == LogWindowVisibility.open
        ? LogWindowVisibility.closed
        : LogWindowVisibility.open;
  }
}
```

- [ ] **Step 2: Generate the `.g.dart`**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: creates `lib/providers/log_window_provider.g.dart` with `logWindowControllerProvider`. No errors.

- [ ] **Step 3: Write the failing test**

Create `test/providers/log_window_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/providers/log_window_provider.dart';

void main() {
  late ProviderContainer container;
  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  LogWindowController ctrl() =>
      container.read(logWindowControllerProvider.notifier);
  LogWindowVisibility state() => container.read(logWindowControllerProvider);

  test('starts closed', () {
    expect(state(), LogWindowVisibility.closed);
  });

  test('toggleOpen opens then closes', () {
    ctrl().toggleOpen();
    expect(state(), LogWindowVisibility.open);
    ctrl().toggleOpen();
    expect(state(), LogWindowVisibility.closed);
  });

  test('minimize then restore', () {
    ctrl().open();
    ctrl().minimize();
    expect(state(), LogWindowVisibility.minimized);
    ctrl().restore();
    expect(state(), LogWindowVisibility.open);
  });

  test('toggleOpen from minimized opens (not closes)', () {
    ctrl().minimize();
    ctrl().toggleOpen();
    expect(state(), LogWindowVisibility.open);
  });

  test('close from open', () {
    ctrl().open();
    ctrl().close();
    expect(state(), LogWindowVisibility.closed);
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/log_window_provider_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/providers/log_window_provider.dart lib/providers/log_window_provider.g.dart test/providers/log_window_provider_test.dart
git commit -m "feat(logs): add LogWindowController visibility provider"
```

---

## Task 3: i18n strings

**Files:**
- Modify: `lib/i18n/en/widgets.i18n.json`
- Modify: `lib/i18n/fr/widgets.i18n.json`
- (Other locales fall back to `en` automatically — `slang.yaml` has `fallback_strategy: base_locale`.)

- [ ] **Step 1: Add the `logs` nav item + `logConsole` block (English)**

In `lib/i18n/en/widgets.i18n.json`, add `"logs": "Logs"` to `navigationSidebar.items` (after `"settings"`):

```json
      "settings": "Settings",
      "logs": "Logs"
```

Then add a new top-level `logConsole` block (e.g. after the `navigationSidebar` object):

```json
  "logConsole": {
    "title": "Logs",
    "search": "Search logs...",
    "copyAll": "Copy all",
    "clear": "Clear",
    "openFolder": "Open logs folder",
    "minimize": "Minimize",
    "restore": "Restore",
    "close": "Close",
    "empty": "No logs for this session yet",
    "levels": {
      "debug": "Debug",
      "info": "Info",
      "warn": "Warn",
      "error": "Error"
    },
    "errors": {
      "openFolderFailed": "Could not open the logs folder"
    }
  },
```

- [ ] **Step 2: Add the French translations**

In `lib/i18n/fr/widgets.i18n.json`, add `"logs": "Logs"` to `navigationSidebar.items` (after `"settings"`), and the `logConsole` block:

```json
  "logConsole": {
    "title": "Logs",
    "search": "Rechercher dans les logs...",
    "copyAll": "Tout copier",
    "clear": "Effacer",
    "openFolder": "Ouvrir le dossier des logs",
    "minimize": "Réduire",
    "restore": "Restaurer",
    "close": "Fermer",
    "empty": "Aucun log pour cette session",
    "levels": {
      "debug": "Debug",
      "info": "Info",
      "warn": "Warn",
      "error": "Erreur"
    },
    "errors": {
      "openFolderFailed": "Impossible d'ouvrir le dossier des logs"
    }
  },
```

- [ ] **Step 3: Regenerate slang strings**

Run: `dart run slang`
Expected: regenerates `lib/i18n/strings.g.dart` exposing `t.widgets.navigationSidebar.items.logs` and `t.widgets.logConsole.*`. No errors.

- [ ] **Step 4: Verify generated accessors compile**

Run: `flutter analyze lib/i18n`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/i18n/en/widgets.i18n.json lib/i18n/fr/widgets.i18n.json lib/i18n/strings.g.dart
git commit -m "i18n: add log console + Logs nav strings (en, fr)"
```

---

## Task 4: LogConsoleWindow + LogConsoleOverlay widgets

**Files:**
- Create: `lib/widgets/logs/log_console_window.dart`
- Create: `lib/widgets/logs/log_console_overlay.dart`
- Test: `test/widgets/logs/log_console_window_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/widgets/logs/log_console_window_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/shared/log_entry.dart';
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
    await tester.pump();
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

    expect(find.textContaining('banana'), findsOneWidget);
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/logs/log_console_window_test.dart`
Expected: FAIL — `log_console_window.dart` does not exist.

- [ ] **Step 3: Write the window widget**

Create `lib/widgets/logs/log_console_window.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/log_window_provider.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/toast_notification_service.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Floating, draggable, resizable, non-blocking log console. Reads the live
/// log stream from [ILoggingService] and shows the current session's entries.
/// Mounted by `LogConsoleOverlay` in the app's `MaterialApp.builder` stack.
class LogConsoleWindow extends ConsumerStatefulWidget {
  const LogConsoleWindow({super.key});

  static const Key searchFieldKey = ValueKey('log-search-field');
  static const Key clearButtonKey = ValueKey('log-clear-button');

  @override
  ConsumerState<LogConsoleWindow> createState() => _LogConsoleWindowState();
}

class _LogConsoleWindowState extends ConsumerState<LogConsoleWindow> {
  static const List<String> _allLevels = ['DEBUG', 'INFO', 'WARN', 'ERROR'];
  static const double _minWidth = 360;
  static const double _minHeight = 220;
  static const int _maxEntries = 5000;

  Offset _position = const Offset(80, 80);
  Size _size = const Size(640, 380);
  final Set<String> _activeLevels = {..._allLevels};
  String _search = '';
  final List<LogEntry> _entries = [];
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  StreamSubscription<LogEntry>? _sub;
  bool _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    final logger = ref.read(loggingServiceProvider);
    _entries.addAll(logger.recentLogs);
    _sub = logger.logStream.listen(_onEntry, onError: (_) {});
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onEntry(LogEntry e) {
    if (!mounted) return;
    setState(() {
      _entries.add(e);
      if (_entries.length > _maxEntries) {
        _entries.removeRange(0, _entries.length - _maxEntries);
      }
    });
    if (_stickToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom =
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 24;
    if (atBottom != _stickToBottom) {
      setState(() => _stickToBottom = atBottom);
    }
  }

  void _jumpToBottom() {
    if (_scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  List<LogEntry> get _visible {
    final q = _search.trim().toLowerCase();
    return _entries.where((e) {
      if (!_activeLevels.contains(e.level)) return false;
      if (q.isEmpty) return true;
      return e.format().toLowerCase().contains(q);
    }).toList();
  }

  void _toggleLevel(String level) {
    setState(() {
      if (!_activeLevels.remove(level)) _activeLevels.add(level);
    });
  }

  Future<void> _copyAll() async {
    final text = _visible.map((e) => e.format()).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
  }

  void _clear() => setState(_entries.clear);

  void _openLogsFolder() {
    final path = ref.read(loggingServiceProvider).logFilePath;
    if (path == null) return;
    final dir = File(path).parent.path;
    try {
      if (Platform.isWindows) {
        Process.start('explorer', [dir], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        Process.start('open', [dir], mode: ProcessStartMode.detached);
      } else {
        Process.start('xdg-open', [dir], mode: ProcessStartMode.detached);
      }
    } catch (_) {
      if (!mounted) return;
      ToastNotificationService.showError(
        context,
        t.widgets.logConsole.errors.openFolderFailed,
      );
    }
  }

  String _levelLabel(String level) {
    final l = t.widgets.logConsole.levels;
    return switch (level) {
      'DEBUG' => l.debug,
      'INFO' => l.info,
      'WARN' => l.warn,
      'ERROR' => l.error,
      _ => level,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final minimized =
        ref.watch(logWindowControllerProvider) == LogWindowVisibility.minimized;
    return minimized ? _minimizedBar(tokens) : _window(context, tokens);
  }

  Widget _window(BuildContext context, TwmtThemeTokens tokens) {
    final screen = MediaQuery.of(context).size;
    final left = _position.dx.clamp(0.0, (screen.width - 80).clamp(0.0, 1e6));
    final top = _position.dy.clamp(0.0, (screen.height - 40).clamp(0.0, 1e6));
    return Positioned(
      left: left,
      top: top,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: _size.width,
          height: _size.height,
          decoration: BoxDecoration(
            color: tokens.panel,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              _header(tokens),
              _toolbar(tokens),
              Divider(height: 1, color: tokens.border),
              Expanded(child: _body(tokens)),
              _resizeFooter(tokens),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(TwmtThemeTokens tokens) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => setState(() => _position += d.delta),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: tokens.panel2,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(tokens.radiusMd - 1)),
          border: Border(bottom: BorderSide(color: tokens.border)),
        ),
        child: Row(
          children: [
            Icon(FluentIcons.window_console_20_regular,
                size: 16, color: tokens.textDim),
            const SizedBox(width: 8),
            Text(
              t.widgets.logConsole.title,
              style: tokens.fontMono.copyWith(
                  color: tokens.text, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            _iconBtn(tokens, FluentIcons.subtract_16_regular,
                t.widgets.logConsole.minimize,
                () => ref.read(logWindowControllerProvider.notifier).minimize()),
            _iconBtn(tokens, FluentIcons.dismiss_16_regular,
                t.widgets.logConsole.close,
                () => ref.read(logWindowControllerProvider.notifier).close()),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          for (final level in _allLevels) _levelChip(tokens, level),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 30,
              child: TextField(
                key: LogConsoleWindow.searchFieldKey,
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _search = v),
                style: tokens.fontMono.copyWith(fontSize: 12, color: tokens.text),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: t.widgets.logConsole.search,
                  hintStyle: tokens.fontMono
                      .copyWith(fontSize: 12, color: tokens.textFaint),
                  prefixIcon: Icon(FluentIcons.search_16_regular,
                      size: 14, color: tokens.textDim),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                ),
              ),
            ),
          ),
          _iconBtn(tokens, FluentIcons.copy_16_regular,
              t.widgets.logConsole.copyAll, _copyAll),
          _iconBtn(tokens, FluentIcons.delete_16_regular,
              t.widgets.logConsole.clear, _clear,
              key: LogConsoleWindow.clearButtonKey),
          _iconBtn(tokens, FluentIcons.folder_16_regular,
              t.widgets.logConsole.openFolder, _openLogsFolder),
        ],
      ),
    );
  }

  Widget _levelChip(TwmtThemeTokens tokens, String level) {
    final active = _activeLevels.contains(level);
    final color = Color(LogEntry.colorForLevel(level));
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        key: ValueKey('log-level-$level'),
        onTap: () => _toggleLevel(level),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(
                color: active ? color.withValues(alpha: 0.6) : tokens.border),
          ),
          child: Text(
            _levelLabel(level),
            style: tokens.fontMono.copyWith(
              fontSize: 11,
              color: active ? color : tokens.textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(TwmtThemeTokens tokens) {
    final visible = _visible;
    if (visible.isEmpty) {
      return Center(
        child: Text(
          t.widgets.logConsole.empty,
          style: tokens.fontMono.copyWith(fontSize: 12, color: tokens.textFaint),
        ),
      );
    }
    return Scrollbar(
      controller: _scroll,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(10),
        itemCount: visible.length,
        itemBuilder: (context, i) {
          final e = visible[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: SelectableText(
              e.format(),
              style: tokens.fontMono.copyWith(
                fontSize: 12,
                height: 1.35,
                color: Color(LogEntry.colorForLevel(e.level)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _resizeFooter(TwmtThemeTokens tokens) {
    return Align(
      alignment: Alignment.bottomRight,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _size = Size(
            (_size.width + d.delta.dx).clamp(_minWidth, 1400.0),
            (_size.height + d.delta.dy).clamp(_minHeight, 1000.0),
          );
        }),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeDownRight,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.south_east, size: 14, color: tokens.textFaint),
          ),
        ),
      ),
    );
  }

  Widget _minimizedBar(TwmtThemeTokens tokens) {
    return Positioned(
      left: 16,
      bottom: 16,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: tokens.panel2,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.window_console_20_regular,
                  size: 16, color: tokens.textDim),
              const SizedBox(width: 8),
              Text(
                t.widgets.logConsole.title,
                style: tokens.fontMono.copyWith(
                    fontSize: 12,
                    color: tokens.text,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              _iconBtn(tokens, FluentIcons.arrow_maximize_16_regular,
                  t.widgets.logConsole.restore,
                  () => ref.read(logWindowControllerProvider.notifier).restore()),
              _iconBtn(tokens, FluentIcons.dismiss_16_regular,
                  t.widgets.logConsole.close,
                  () => ref.read(logWindowControllerProvider.notifier).close()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(
    TwmtThemeTokens tokens,
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    Key? key,
  }) {
    return IconButton(
      key: key,
      tooltip: tooltip,
      icon: Icon(icon, size: 16, color: tokens.textDim),
      splashRadius: 16,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      onPressed: onTap,
    );
  }
}
```

- [ ] **Step 4: Write the overlay widget**

Create `lib/widgets/logs/log_console_overlay.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/providers/log_window_provider.dart';
import 'package:twmt/widgets/logs/log_console_window.dart';

/// Mounts [LogConsoleWindow] above all routes when the window is not closed.
/// Designed to sit as a direct child of the `MaterialApp.builder` [Stack].
class LogConsoleOverlay extends ConsumerWidget {
  const LogConsoleOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(logWindowControllerProvider) !=
        LogWindowVisibility.closed;
    return visible ? const LogConsoleWindow() : const SizedBox.shrink();
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/widgets/logs/log_console_window_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/widgets/logs`
Expected: No issues. (If any `FluentIcons.*_16_regular` constant fails to resolve in the installed `fluentui_system_icons` version, the analyzer will name it — substitute the nearest existing regular variant, e.g. `dismiss_20_regular`, and re-run.)

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/logs/log_console_window.dart lib/widgets/logs/log_console_overlay.dart test/widgets/logs/log_console_window_test.dart
git commit -m "feat(logs): add floating LogConsoleWindow + overlay"
```

---

## Task 5: Mount the overlay in the app shell

**Files:**
- Modify: `lib/main.dart:151` (the `MaterialApp.router` `builder`)

- [ ] **Step 1: Add the import**

In `lib/main.dart`, add with the other `widgets/` imports:

```dart
import 'package:twmt/widgets/logs/log_console_overlay.dart';
```

- [ ] **Step 2: Wrap the router child in a Stack with the overlay**

Replace line 151:

```dart
      builder: (context, child) => _AppStartupTasks(child: child!),
```

with:

```dart
      builder: (context, child) => _AppStartupTasks(
        child: Stack(
          children: [
            child!,
            const LogConsoleOverlay(),
          ],
        ),
      ),
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/main.dart`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat(logs): mount log console overlay above all routes"
```

---

## Task 6: Sidebar "Logs" button

**Files:**
- Modify: `lib/widgets/navigation/navigation_sidebar.dart`
- Test: `test/widgets/navigation/navigation_sidebar_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `void main()` in `test/widgets/navigation/navigation_sidebar_test.dart`:

```dart
  testWidgets('renders Logs button and toggles the log window',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/system/settings',
      routes: [
        GoRoute(
          path: '/system/settings',
          builder: (_, _) =>
              const Scaffold(body: Row(children: [NavigationSidebar()])),
        ),
      ],
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.atelierDarkTheme,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
    _drainOverflowExceptions(tester);

    expect(find.text('Logs'), findsOneWidget);
    expect(container.read(logWindowControllerProvider),
        LogWindowVisibility.closed);

    await tester.tap(find.byKey(NavigationSidebar.logButtonKey));
    await tester.pump();
    _drainOverflowExceptions(tester);

    expect(container.read(logWindowControllerProvider),
        LogWindowVisibility.open);
  });
```

Add these imports at the top of the test file:

```dart
import 'package:twmt/providers/log_window_provider.dart';
```

(`flutter_riverpod` and `go_router` are already imported.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/navigation/navigation_sidebar_test.dart -n "renders Logs button"`
Expected: FAIL — no `Logs` text / `logButtonKey` undefined.

- [ ] **Step 3: Add the button key and import**

In `lib/widgets/navigation/navigation_sidebar.dart`, add the import (near the other project imports):

```dart
import '../../providers/log_window_provider.dart';
```

Add a key constant next to `activeItemKey` (after line 32):

```dart
  /// Widget key for the Logs toggle button, for tests.
  static const Key logButtonKey = ValueKey('nav-sidebar-log-button');
```

- [ ] **Step 4: Render the button under the nav groups**

In `build`, inside the `ListView(children: [...])`, after the closing `]` of the `for (var i = 0; ...)` collection-for block and before the `ListView`'s children list ends, add:

```dart
                const SizedBox(height: 12),
                const _LogConsoleButton(),
```

So the tail of the `children` list reads:

```dart
                for (var i = 0; i < navigationTree.length; i++) ...[
                  // ...unchanged...
                ],
                const SizedBox(height: 12),
                const _LogConsoleButton(),
              ],
```

- [ ] **Step 5: Implement `_LogConsoleButton`**

Add this widget at the end of `navigation_sidebar.dart` (top-level, after `_ThemeSwatch`):

```dart
/// Sidebar tile that toggles the floating log console. Mirrors [_NavItemTile]'s
/// styling but, instead of navigating, flips [LogWindowController]. Highlights
/// while the window is open or minimized.
class _LogConsoleButton extends ConsumerStatefulWidget {
  const _LogConsoleButton();

  @override
  ConsumerState<_LogConsoleButton> createState() => _LogConsoleButtonState();
}

class _LogConsoleButtonState extends ConsumerState<_LogConsoleButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isOpen = ref.watch(logWindowControllerProvider) !=
        LogWindowVisibility.closed;
    final bg = isOpen
        ? tokens.accentBg
        : (_hover ? tokens.panel2 : Colors.transparent);
    final fg = isOpen ? tokens.accent : tokens.text;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          key: NavigationSidebar.logButtonKey,
          onTap: () =>
              ref.read(logWindowControllerProvider.notifier).toggleOpen(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: isOpen
                  ? Border(left: BorderSide(color: tokens.accent, width: 2))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  isOpen
                      ? FluentIcons.window_console_20_filled
                      : FluentIcons.window_console_20_regular,
                  size: 20,
                  color: fg,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t.widgets.navigationSidebar.items.logs,
                    style: TextStyle(
                      color: fg,
                      fontWeight:
                          isOpen ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/widgets/navigation/navigation_sidebar_test.dart`
Expected: PASS (all existing tests + the new one).

- [ ] **Step 7: Analyze**

Run: `flutter analyze lib/widgets/navigation/navigation_sidebar.dart`
Expected: No issues. (`FluentIcons.window_console_20_filled` is used alongside the already-working `_20_regular`; if `_filled` is absent in the installed version, reuse `_20_regular` for both states.)

- [ ] **Step 8: Commit**

```bash
git add lib/widgets/navigation/navigation_sidebar.dart test/widgets/navigation/navigation_sidebar_test.dart
git commit -m "feat(logs): add Logs toggle button under Settings in sidebar"
```

---

## Task 7: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the whole test suite**

Run: `flutter test`
Expected: All tests pass (no regressions).

- [ ] **Step 2: Analyze the whole project**

Run: `flutter analyze`
Expected: No new issues introduced by this work.

- [ ] **Step 3: Manual smoke test (Windows)**

Run: `flutter run -d windows`
Verify:
- A "Logs" button appears directly under "Settings" in the sidebar.
- Clicking it opens the floating window; logs from this session are listed.
- Dragging the header moves the window; the rest of the app stays usable underneath.
- The resize handle (bottom-right) resizes the window.
- Toggling a level chip and typing in search filter the lines live; new logs keep arriving.
- "Copy all" puts the visible lines on the clipboard; "Clear" empties the view.
- "Open logs folder" opens `AppData\Local\TWMT\logs` in Explorer.
- Minimize collapses to the bottom bar; restore reopens; close hides it (button un-highlights).

- [ ] **Step 4: Final commit (if manual testing required tweaks)**

```bash
git add -A
git commit -m "fix(logs): manual-test adjustments"
```

---

## Self-Review Notes

- **Spec coverage:** live stream + seed (Task 4); current-session-only source = in-memory buffer (Task 4 `initState`); 5000 cap (Task 1 + Task 4 `_maxEntries`); draggable/resizable/close/minimize (Task 4); level filter + search + copy + clear + open-folder (Task 4); button under Settings (Task 6); non-blocking via builder Stack below dialogs (Task 5); no position persistence (local state, reset on close→reopen). All covered.
- **No persistence** of position/size is intentional (spec §2): state lives in `_LogConsoleWindowState` and is recreated when the overlay remounts the window after a close.
- **Type consistency:** generated provider is `logWindowControllerProvider` (from class `LogWindowController`); `LogWindowVisibility` enum reused everywhere; keys `searchFieldKey`/`clearButtonKey`/`logButtonKey` and `log-level-$level` match between widgets and tests; `LogEntry.colorForLevel` defined in Task 1, used in Task 4.
- **Open-folder** reuses the established `Process.start('explorer', …)` pattern (`pack_compilation_editor_screen.dart`).
