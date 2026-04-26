import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/translation_editor/providers/grid_data_providers.dart';
import 'package:twmt/features/translation_editor/providers/tm_reuse_stats_provider.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Bottom statusbar of the translation editor.
///
/// Reads [editorStatsProvider] and [tmReuseStatsProvider]. Loading state shows
/// dotted skeletons; error state is silent (left side hidden) and the failure
/// is forwarded to [loggingServiceProvider] (logged once per distinct error to
/// avoid spamming on rebuilds).
class EditorStatusBar extends ConsumerStatefulWidget {
  final String projectId;
  final String languageId;

  const EditorStatusBar({
    super.key,
    required this.projectId,
    required this.languageId,
  });

  @override
  ConsumerState<EditorStatusBar> createState() => _EditorStatusBarState();
}

class _EditorStatusBarState extends ConsumerState<EditorStatusBar> {
  // Track the last logged error per provider so we only emit a log entry when
  // the error transitions to a *new* value. Recovery (error -> null) is not
  // logged. `build` runs many times per second; unconditional logging would
  // flood the log.
  Object? _lastStatsError;
  Object? _lastReuseError;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final statsAsync = ref.watch(editorStatsProvider(widget.projectId, widget.languageId));
    final reuseAsync = ref.watch(tmReuseStatsProvider(widget.projectId, widget.languageId));

    if (statsAsync.hasError) {
      final err = statsAsync.error;
      if (!identical(err, _lastStatsError)) {
        _lastStatsError = err;
        ref.read(loggingServiceProvider).error(
              'EditorStatusBar: editorStats failed',
              err,
              statsAsync.stackTrace,
            );
      }
    } else {
      _lastStatsError = null;
    }
    if (reuseAsync.hasError) {
      final err = reuseAsync.error;
      if (!identical(err, _lastReuseError)) {
        _lastReuseError = err;
        ref.read(loggingServiceProvider).error(
              'EditorStatusBar: tmReuseStats failed',
              err,
              reuseAsync.stackTrace,
            );
      }
    } else {
      _lastReuseError = null;
    }

    final monoStyle = tokens.fontMono.copyWith(
      fontSize: 10.5,
      color: tokens.textDim,
      letterSpacing: 0.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final accentMonoStyle = monoStyle.copyWith(color: tokens.accent);
    final separator = Text('·', style: monoStyle.copyWith(color: tokens.textFaint));

    final leftChildren = <Widget>[];
    final hasError = statsAsync.hasError || reuseAsync.hasError;
    if (statsAsync.isLoading || reuseAsync.isLoading) {
      leftChildren.addAll([
        Text('· · ·', style: monoStyle),
        const SizedBox(width: 22),
        separator,
        const SizedBox(width: 22),
        Text('· · ·', style: monoStyle),
      ]);
    } else if (!hasError) {
      final stats = statsAsync.value!;
      final reuse = reuseAsync.value!;
      leftChildren.addAll([
        Text(t.translationEditor.statusBar.units(count: stats.totalUnits), style: monoStyle),
        const SizedBox(width: 22),
        separator,
        const SizedBox(width: 22),
        Text(
          t.translationEditor.statusBar.translated(
            count: stats.translatedCount,
            pct: stats.completionPercentage.round(),
          ),
          style: accentMonoStyle,
        ),
        const SizedBox(width: 22),
        separator,
        const SizedBox(width: 22),
        Text(t.translationEditor.statusBar.needReview(count: stats.needsReviewCount), style: monoStyle),
        const SizedBox(width: 22),
        separator,
        const SizedBox(width: 22),
        Text(t.translationEditor.statusBar.tmReuse(pct: reuse.reusePercentage.round()), style: monoStyle),
      ]);
    }

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          ...leftChildren,
          const Spacer(),
          Text('UTF-8 · CRLF', style: monoStyle),
        ],
      ),
    );
  }
}
