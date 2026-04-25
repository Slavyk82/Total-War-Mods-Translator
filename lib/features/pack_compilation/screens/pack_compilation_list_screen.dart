import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_confirm_dialog.dart';
import 'package:twmt/widgets/fluent/fluent_toast.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_row.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/list_toolbar_leading.dart';
import 'package:twmt/widgets/lists/relative_date.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/detail/home_back_toolbar.dart';
import '../providers/pack_compilation_providers.dart';

/// Column layout shared between [_CompilationRow] and the list header so
/// rows stay aligned with their column titles.
const List<ListRowColumn> _compilationColumns = [
  ListRowColumn.flex(1),
  ListRowColumn.fixed(120),
  ListRowColumn.fixed(140),
  ListRowColumn.fixed(100),
];

/// Trailing action width reserved in the header to mirror each row's
/// "Edit" SmallTextButton + 6 px gap + delete SmallIconButton(28) plus the
/// 8 px gap that [ListRow] inserts before its `trailingAction`.
const double _compilationTrailingActionWidth = 92;

/// Pack compilations list screen (§7.1 archetype).
///
/// Displays all compilations for the currently selected game with name
/// search, language, project count, pack-status, and relative "updated"
/// timestamp columns. Tapping a row (or its "Edit" action) routes to the
/// editor; the delete action pops a confirmation dialog and invalidates the
/// provider on success.
class PackCompilationListScreen extends ConsumerStatefulWidget {
  const PackCompilationListScreen({super.key});

  @override
  ConsumerState<PackCompilationListScreen> createState() =>
      _PackCompilationListScreenState();
}

class _PackCompilationListScreenState
    extends ConsumerState<PackCompilationListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final async = ref.watch(compilationsWithDetailsProvider);
    final all = async.asData?.value ?? const <CompilationWithDetails>[];
    final filtered = _query.isEmpty
        ? all
        : all
            .where((c) => c.compilation.name
                .toLowerCase()
                .contains(_query.toLowerCase()))
            .toList();

    return Material(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeBackToolbar(
            leading: ListToolbarLeading(
              icon: FluentIcons.archive_multiple_24_regular,
              title: 'Pack compilations',
              countLabel: '${filtered.length} / ${all.length}',
            ),
          ),
          FilterToolbar(
            leading: const SizedBox.shrink(),
            expandLeading: false,
            trailing: [
              Expanded(
                child: ListSearchField(
                  value: _query,
                  width: null,
                  onChanged: (v) => setState(() => _query = v),
                  onClear: () => setState(() => _query = ''),
                ),
              ),
              SmallTextButton(
                label: '+ New compilation',
                icon: FluentIcons.add_24_regular,
                onTap: () => context.push(AppRoutes.packCompilationNew),
              ),
            ],
            pillGroups: const [],
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(
                  'Error loading compilations: $err',
                  style: tokens.fontBody.copyWith(color: tokens.err),
                ),
              ),
              data: (_) => filtered.isEmpty
                  ? _EmptyState(
                      onNew: () => context.push(AppRoutes.packCompilationNew),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListRowHeader(
                          columns: _compilationColumns,
                          labels: const [
                            'Compilation',
                            'Projects',
                            'Pack status',
                            'Updated',
                          ],
                          alignments: const [
                            TextAlign.left,
                            TextAlign.right,
                            TextAlign.right,
                            TextAlign.right,
                          ],
                          trailingActionWidth:
                              _compilationTrailingActionWidth,
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, i) => _CompilationRow(
                              details: filtered[i],
                              onEdit: () => context.push(
                                AppRoutes.packCompilationEdit(
                                  filtered[i].compilation.id,
                                ),
                              ),
                              onDelete: () => _confirmDelete(filtered[i]),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(CompilationWithDetails d) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => TokenConfirmDialog(
        title: 'Delete Compilation',
        message: 'Delete "${d.compilation.name}"?',
        warningMessage: 'This action cannot be undone.',
        confirmLabel: 'Delete',
        confirmIcon: FluentIcons.delete_24_regular,
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;

    final repo = ref.read(compilationRepositoryProvider);
    final r = await repo.delete(d.compilation.id);
    if (!mounted) return;
    if (r.isOk) {
      ref.invalidate(compilationsWithDetailsProvider);
      FluentToast.success(context, 'Deleted "${d.compilation.name}"');
    } else {
      FluentToast.error(context, 'Delete failed: ${r.error}');
    }
  }
}

/// Empty-state card shown when no compilations exist for the current game.
class _EmptyState extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyState({required this.onNew});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.archive_multiple_24_regular,
              size: 56,
              color: tokens.textFaint,
            ),
            const SizedBox(height: 16),
            Text(
              'No compilations yet',
              style: tokens.fontDisplay.copyWith(
                fontSize: 16,
                color: tokens.textMid,
                fontStyle: tokens.fontDisplayStyle,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a compilation to bundle several projects into one .pack.',
              style:
                  tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
            ),
            const SizedBox(height: 16),
            SmallTextButton(
              label: '+ New compilation',
              icon: FluentIcons.add_24_regular,
              onTap: onNew,
            ),
          ],
        ),
      ),
    );
  }
}

/// Single row in the compilation list: name (+ language chip) + packName /
/// project count / pack status (last generation, outdated, or never) /
/// relative updated-at date, with trailing Edit + Delete actions.
class _CompilationRow extends ConsumerWidget {
  final CompilationWithDetails details;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CompilationRow({
    required this.details,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final now = ref.watch(clockProvider)();
    final compilation = details.compilation;
    final updatedAt =
        DateTime.fromMillisecondsSinceEpoch(compilation.updatedAt);
    final lastGeneratedAt = compilation.lastGeneratedAt;
    // A compilation pack is stale when at least one bundled project was
    // updated after the last successful generation.
    final needsRegeneration = lastGeneratedAt != null &&
        details.projects.any((p) => p.updatedAt > lastGeneratedAt);
    return ListRow(
      columns: _compilationColumns,
      onTap: onEdit,
      trailingAction: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SmallTextButton(label: 'Edit', onTap: onEdit),
          const SizedBox(width: 6),
          SmallIconButton(
            icon: FluentIcons.delete_24_regular,
            tooltip: 'Delete compilation',
            onTap: onDelete,
            foreground: tokens.err,
            background: tokens.errBg,
            borderColor: tokens.err.withValues(alpha: 0.3),
          ),
        ],
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    compilation.name,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.fontBody.copyWith(
                      fontSize: 13,
                      color: tokens.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (details.language != null) ...[
                  const SizedBox(width: 8),
                  _LanguageChip(code: details.language!.code),
                ],
              ],
            ),
            if (compilation.packName.isNotEmpty)
              Text(
                compilation.packName,
                overflow: TextOverflow.ellipsis,
                style: tokens.fontMono.copyWith(
                  fontSize: 10,
                  color: tokens.textDim,
                ),
              ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${details.projects.length} packs',
            style: tokens.fontMono.copyWith(
              fontSize: 11,
              color: tokens.textMid,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: _PackStatus(
            lastGeneratedAt: lastGeneratedAt,
            needsRegeneration: needsRegeneration,
            now: now,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            formatRelativeSince(updatedAt, now: now) ?? '—',
            style: tokens.fontMono.copyWith(
              fontSize: 10,
              color: tokens.textFaint,
            ),
          ),
        ),
      ],
    );
  }
}

/// Small bordered chip displaying the compilation's target language code
/// (e.g. `FR`). Rendered next to the compilation name.
class _LanguageChip extends StatelessWidget {
  final String code;

  const _LanguageChip({required this.code});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: tokens.panel2,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        code.toUpperCase(),
        style: tokens.fontMono.copyWith(
          fontSize: 10,
          color: tokens.textMid,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Renders the right-aligned pack-status cell for a compilation row.
/// Three mutually-exclusive states:
///   * never generated → faint "Never generated" text
///   * stale (project changed after last gen) → orange "Pack outdated" badge
///   * up to date → "Last pack: {relative}" mono text
class _PackStatus extends StatelessWidget {
  final int? lastGeneratedAt;
  final bool needsRegeneration;
  final DateTime now;

  const _PackStatus({
    required this.lastGeneratedAt,
    required this.needsRegeneration,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (lastGeneratedAt == null) {
      return Text(
        'Never generated',
        style: tokens.fontMono.copyWith(
          fontSize: 10,
          color: tokens.textFaint,
        ),
      );
    }
    if (needsRegeneration) {
      return Tooltip(
        message:
            'One or more projects changed after the last pack generation',
        waitDuration: const Duration(milliseconds: 400),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: tokens.warnBg,
            border: Border.all(color: tokens.warn.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Text(
            'Pack outdated',
            style: tokens.fontBody.copyWith(
              fontSize: 10,
              color: tokens.warn,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    final generated = DateTime.fromMillisecondsSinceEpoch(lastGeneratedAt!);
    final relative = formatRelativeSince(generated, now: now) ?? '—';
    return Text(
      'Last pack: $relative',
      style: tokens.fontMono.copyWith(
        fontSize: 10,
        color: tokens.textFaint,
      ),
    );
  }
}
