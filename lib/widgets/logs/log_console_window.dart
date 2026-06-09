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

  // Memoised view of the filtered entries. Recomputing the filter on every
  // streamed log line (and again on every frame via the [_visible] getter) is
  // O(n) per entry — with up to [_maxEntries] (5000) buffered and a non-empty
  // search forcing format()+toLowerCase on each, that is wasteful on the UI
  // thread. Instead we cache the filtered list and only rebuild it when the
  // entries, level filter, or search text actually change (tracked via
  // [_filterDirty]). Per-entry lowercased text is cached in [_lowerCache] so
  // format()+toLowerCase runs once per entry rather than once per frame.
  List<LogEntry>? _visibleCache;
  bool _filterDirty = true;
  final Map<LogEntry, String> _lowerCache = {};

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
        final removed = _entries.sublist(0, _entries.length - _maxEntries);
        _entries.removeRange(0, _entries.length - _maxEntries);
        // Drop evicted entries from the per-entry lowercase cache so it does
        // not grow unbounded.
        for (final old in removed) {
          _lowerCache.remove(old);
        }
      }
      _filterDirty = true;
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

  /// Lazily computed, memoised filtered view. Only recomputes the O(n) scan
  /// when [_filterDirty] is set (entries appended/cleared, level filter toggled,
  /// or search text changed); otherwise returns the cached list so reading it
  /// once per frame is O(1).
  List<LogEntry> get _visible {
    if (!_filterDirty && _visibleCache != null) return _visibleCache!;
    final q = _search.trim().toLowerCase();
    final result = _entries.where((e) {
      if (!_activeLevels.contains(e.level)) return false;
      if (q.isEmpty) return true;
      // Cache format()+toLowerCase per entry so it is computed once rather than
      // on every filter pass.
      final lower = _lowerCache[e] ??= e.format().toLowerCase();
      return lower.contains(q);
    }).toList();
    _visibleCache = result;
    _filterDirty = false;
    return result;
  }

  void _toggleLevel(String level) {
    setState(() {
      if (!_activeLevels.remove(level)) _activeLevels.add(level);
      _filterDirty = true;
    });
  }

  Future<void> _copyAll() async {
    final text = _visible.map((e) => e.format()).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
  }

  void _clear() => setState(() {
        _entries.clear();
        _lowerCache.clear();
        _filterDirty = true;
      });

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
                onChanged: (v) => setState(() {
                  _search = v;
                  _filterDirty = true;
                }),
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
