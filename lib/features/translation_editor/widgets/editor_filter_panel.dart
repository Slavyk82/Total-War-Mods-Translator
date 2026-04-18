import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/translation_editor/providers/editor_filter_notifier.dart';
import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';
import 'package:twmt/features/translation_editor/providers/grid_data_providers.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Left filter panel of the translation editor (200px).
///
/// Two groups: État (status) and Source mémoire (TM source).
/// Reads [editorFilterProvider] for active state, mutates via its notifier.
/// Status counts come from [editorStatsProvider]. TM source counts are not
/// yet wired to a provider — we display nothing (not "0") to avoid implying
/// a real zero count.
class EditorFilterPanel extends ConsumerWidget {
  final String projectId;
  final String languageId;

  const EditorFilterPanel({
    super.key,
    required this.projectId,
    required this.languageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final filterState = ref.watch(editorFilterProvider);
    final statsAsync = ref.watch(editorStatsProvider(projectId, languageId));
    final stats = statsAsync.value;

    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(right: BorderSide(color: tokens.border)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(label: 'État', tokens: tokens),
            const SizedBox(height: 10),
            _StatusChip(
              label: 'Pending',
              status: TranslationVersionStatus.pending,
              dotColor: tokens.warn,
              count: stats?.pendingCount,
            ),
            _StatusChip(
              label: 'Translated',
              status: TranslationVersionStatus.translated,
              dotColor: tokens.ok,
              count: stats?.translatedCount,
            ),
            _StatusChip(
              label: 'Needs review',
              status: TranslationVersionStatus.needsReview,
              dotColor: tokens.err,
              count: stats?.needsReviewCount,
            ),
            const SizedBox(height: 20),
            _SectionHeader(label: 'Source mémoire', tokens: tokens),
            const SizedBox(height: 10),
            const _TmSourceChip(label: 'Exact match', type: TmSourceType.exactMatch),
            const _TmSourceChip(label: 'Fuzzy match', type: TmSourceType.fuzzyMatch),
            const _TmSourceChip(label: 'LLM', type: TmSourceType.llm),
            const _TmSourceChip(label: 'Manual', type: TmSourceType.manual),
            const _TmSourceChip(label: 'None', type: TmSourceType.none),
            if (filterState.hasActiveFilters) ...[
              const SizedBox(height: 16),
              const _ClearFiltersButton(),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final TwmtThemeTokens tokens;
  const _SectionHeader({required this.label, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: tokens.fontDisplay.copyWith(
              fontStyle: tokens.fontDisplayStyle,
              fontSize: 13,
              color: tokens.accent,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [tokens.border, Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends ConsumerWidget {
  final String label;
  final TranslationVersionStatus status;
  final Color dotColor;
  final int? count;
  const _StatusChip({
    required this.label,
    required this.status,
    required this.dotColor,
    required this.count,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final filterState = ref.watch(editorFilterProvider);
    final isActive = filterState.statusFilters.contains(status);
    return _ChipShell(
      isActive: isActive,
      onTap: () {
        final updated = Set<TranslationVersionStatus>.from(filterState.statusFilters);
        if (isActive) {
          updated.remove(status);
        } else {
          updated.add(status);
        }
        ref.read(editorFilterProvider.notifier).setStatusFilters(updated);
      },
      child: Row(
        children: [
          _Checkbox(isActive: isActive),
          const SizedBox(width: 9),
          _Dot(color: dotColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: tokens.textMid),
            ),
          ),
          if (count != null)
            Text(
              count.toString(),
              style: tokens.fontMono.copyWith(
                fontSize: 10.5,
                color: tokens.textFaint,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

class _TmSourceChip extends ConsumerWidget {
  final String label;
  final TmSourceType type;
  const _TmSourceChip({required this.label, required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final filterState = ref.watch(editorFilterProvider);
    final isActive = filterState.tmSourceFilters.contains(type);
    return _ChipShell(
      isActive: isActive,
      onTap: () {
        final updated = Set<TmSourceType>.from(filterState.tmSourceFilters);
        if (isActive) {
          updated.remove(type);
        } else {
          updated.add(type);
        }
        ref.read(editorFilterProvider.notifier).setTmSourceFilters(updated);
      },
      child: Row(
        children: [
          _Checkbox(isActive: isActive),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: tokens.textMid),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipShell extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final Widget child;
  const _ChipShell({required this.isActive, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? tokens.accentBg : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  final bool isActive;
  const _Checkbox({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: isActive ? tokens.accent : Colors.transparent,
        border: Border.all(color: isActive ? tokens.accent : tokens.border),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _ClearFiltersButton extends ConsumerWidget {
  const _ClearFiltersButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    return SizedBox(
      width: double.infinity,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(editorFilterProvider.notifier).clearFilters(),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              'Clear filters',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: tokens.textMid,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
