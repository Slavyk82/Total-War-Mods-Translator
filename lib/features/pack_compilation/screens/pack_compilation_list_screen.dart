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
import '../providers/pack_compilation_providers.dart';

/// Pack compilations list screen (§7.1 archetype).
///
/// Displays all compilations for the currently selected game with name
/// search, project count, and relative "updated" timestamp columns. Tapping
/// a row (or its "Edit" action) routes to the editor; the delete action
/// pops a confirmation dialog and invalidates the provider on success.
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
          FilterToolbar(
            leading: ListToolbarLeading(
              icon: FluentIcons.archive_multiple_24_regular,
              title: 'Pack compilations',
              countLabel: '${filtered.length} / ${all.length}',
            ),
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
                  : ListView.builder(
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

/// Single row in the compilation list: name + packName / project count /
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
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(
      details.compilation.updatedAt,
    );
    return ListRow(
      columns: const [
        ListRowColumn.flex(1),
        ListRowColumn.fixed(120),
        ListRowColumn.fixed(100),
      ],
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
            Text(
              details.compilation.name,
              overflow: TextOverflow.ellipsis,
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.text,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (details.compilation.packName.isNotEmpty)
              Text(
                details.compilation.packName,
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
