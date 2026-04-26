import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/common/fluent_spinner.dart';
import '../providers/tm_providers.dart';

/// Statistics panel showing Translation Memory metrics and insights.
///
/// Retokenised in Plan 5a · Task 6 — the 280px sidebar is a preserve-feature
/// of the TM screen, so the panel stays as-is in terms of structure but
/// sources every colour and typography style from [TwmtThemeTokens].
class TmStatisticsPanel extends ConsumerWidget {
  const TmStatisticsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final filtersState = ref.watch(tmFilterStateProvider);
    final statsAsync = ref.watch(tmStatisticsProvider(
      targetLang: filtersState.targetLanguage,
    ));

    return Container(
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(right: BorderSide(color: tokens.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(
                  FluentIcons.data_bar_vertical_24_regular,
                  size: 18,
                  color: tokens.textMid,
                ),
                const SizedBox(width: 8),
                Text(
                  t.translationMemory.labels.statistics,
                  style: tokens.fontDisplay.copyWith(
                    fontSize: 14,
                    color: tokens.text,
                    fontWeight: FontWeight.w600,
                    fontStyle: tokens.fontDisplayStyle,
                  ),
                ),
                const Spacer(),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      ref.invalidate(tmStatisticsProvider);
                    },
                    child: Icon(
                      FluentIcons.arrow_clockwise_24_regular,
                      size: 16,
                      color: tokens.textDim,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Container(height: 1, color: tokens.border),

          // Content
          Expanded(
            child: statsAsync.when(
              data: (stats) => _buildStatsContent(context, tokens, stats),
              loading: () => const Center(child: FluentSpinner()),
              error: (error, stack) => _buildError(tokens),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(TwmtThemeTokens tokens) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 40,
              color: tokens.err,
            ),
            const SizedBox(height: 8),
            Text(
              t.translationMemory.messages.failedToLoadStatistics,
              style: tokens.fontBody
                  .copyWith(fontSize: 12, color: tokens.textDim),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsContent(
    BuildContext context,
    TwmtThemeTokens tokens,
    TmStatistics stats,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total Entries
          _buildBigStat(
            tokens,
            label: t.translationMemory.labels.totalEntries,
            value: stats.totalEntries.toString(),
            icon: FluentIcons.database_24_regular,
          ),

          const SizedBox(height: 20),

          // Language Pairs
          _buildSectionHeader(tokens, t.translationMemory.labels.languagePairs),
          const SizedBox(height: 8),
          ...stats.entriesByLanguagePair.entries.map(
            (entry) => _buildLanguagePairStat(
              tokens,
              languagePair: entry.key,
              count: entry.value,
            ),
          ),

          const SizedBox(height: 20),

          // Performance Stats
          _buildSectionHeader(tokens, t.translationMemory.labels.performance),
          const SizedBox(height: 8),
          _buildSmallStat(
            tokens,
            label: t.translationMemory.labels.totalReuse,
            value: stats.totalReuseCount.toString(),
          ),
          const SizedBox(height: 4),
          _buildSmallStat(
            tokens,
            label: t.translationMemory.labels.tokensSaved,
            value: _formatNumber(stats.tokensSaved),
          ),
          const SizedBox(height: 4),
          _buildSmallStat(
            tokens,
            label: t.translationMemory.labels.reuseRate,
            value: '${(stats.reuseRate * 100).toStringAsFixed(1)}%',
          ),
        ],
      ),
    );
  }

  Widget _buildBigStat(
    TwmtThemeTokens tokens, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.accentBg,
        border: Border.all(color: tokens.accent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, size: 28, color: tokens.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: tokens.fontDisplay.copyWith(
                    fontSize: 22,
                    color: tokens.accent,
                    fontWeight: FontWeight.w700,
                    fontStyle: tokens.fontDisplayStyle,
                  ),
                ),
                Text(
                  label,
                  style: tokens.fontBody
                      .copyWith(fontSize: 11.5, color: tokens.textDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(TwmtThemeTokens tokens, String title) {
    return Text(
      title.toUpperCase(),
      style: tokens.fontMono.copyWith(
        fontSize: 11,
        color: tokens.textDim,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildLanguagePairStat(
    TwmtThemeTokens tokens, {
    required String languagePair,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        children: [
          Icon(
            FluentIcons.translate_24_regular,
            size: 14,
            color: tokens.textMid,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              languagePair,
              style: tokens.fontBody
                  .copyWith(fontSize: 12, color: tokens.textMid),
            ),
          ),
          Text(
            count.toString(),
            style: tokens.fontMono.copyWith(
              fontSize: 12,
              color: tokens.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallStat(
    TwmtThemeTokens tokens, {
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: tokens.fontBody
              .copyWith(fontSize: 12, color: tokens.textMid),
        ),
        Text(
          value,
          style: tokens.fontMono.copyWith(
            fontSize: 12,
            color: tokens.text,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }
}
