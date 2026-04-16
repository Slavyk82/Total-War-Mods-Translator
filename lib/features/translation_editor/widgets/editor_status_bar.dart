import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/translation_editor/providers/grid_data_providers.dart';
import 'package:twmt/features/translation_editor/providers/tm_reuse_stats_provider.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Bottom statusbar of the translation editor.
///
/// Reads [editorStatsProvider] and [tmReuseStatsProvider]. Loading state shows
/// dotted skeletons; error state is silent (left side hidden).
class EditorStatusBar extends ConsumerWidget {
  final String projectId;
  final String languageId;

  const EditorStatusBar({
    super.key,
    required this.projectId,
    required this.languageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final statsAsync = ref.watch(editorStatsProvider(projectId, languageId));
    final reuseAsync = ref.watch(tmReuseStatsProvider(projectId, languageId));

    final monoStyle = TextStyle(
      fontFamily: tokens.fontMono.fontFamily,
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
        Text('${stats.totalUnits} units', style: monoStyle),
        const SizedBox(width: 22),
        separator,
        const SizedBox(width: 22),
        Text(
          '${stats.translatedCount} translated (${stats.completionPercentage.round()}%)',
          style: accentMonoStyle,
        ),
        const SizedBox(width: 22),
        separator,
        const SizedBox(width: 22),
        Text('${stats.needsReviewCount} need review', style: monoStyle),
        const SizedBox(width: 22),
        separator,
        const SizedBox(width: 22),
        Text('TM ${reuse.reusePercentage.round()}%', style: monoStyle),
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
