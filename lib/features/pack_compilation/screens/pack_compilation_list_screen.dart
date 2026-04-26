import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_confirm_dialog.dart';
import 'package:twmt/widgets/fluent/fluent_toast.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_row.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/list_toolbar_leading.dart';
import 'package:twmt/widgets/lists/project_cover_thumbnail.dart';
import 'package:twmt/widgets/lists/relative_date.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/lists/status_pill.dart';
import 'package:twmt/widgets/detail/home_back_toolbar.dart';
import 'package:twmt/i18n/strings.g.dart';
import '../providers/pack_compilation_providers.dart';

/// Column layout shared between [_CompilationRow] and the list header so
/// rows stay aligned with their column titles. Mirrors the Projects-screen
/// layout (cover / name+meta / language / modified / status).
const List<ListRowColumn> _compilationColumns = [
  ListRowColumn.fixed(80), // cover thumbnail
  ListRowColumn.flex(3), // name + meta line
  ListRowColumn.flex(2), // language
  ListRowColumn.fixed(180), // modified
  ListRowColumn.fixed(150), // status pill
];

/// Trailing action width reserved in the header to mirror each row's
/// delete IconButton (16 px icon + 12 px padding) and the right-side gap
/// kept between the icon and the list scrollbar. Same value as the
/// Projects screen.
const double _compilationRowTrailingActionWidth = 52;

/// Pack compilations list screen (§7.1 archetype).
///
/// Mirrors the Projects-list visual: 80 px cover thumbnail, name + meta
/// (.pack filename + last generation), language, modified date, and a
/// [StatusPill] reflecting whether the pack must be (re)generated. Tapping
/// a row opens the editor; the trailing delete icon pops a confirmation
/// dialog and invalidates the provider on success.
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
              title: t.packCompilation.labels.title,
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
                label: t.packCompilation.actions.newCompilation,
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
                  t.packCompilation.messages.errorLoadingCompilations(error: err.toString()),
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
                          labels: [
                            '',
                            t.packCompilation.labels.compilation,
                            t.packCompilation.labels.language,
                            t.packCompilation.labels.modified,
                            t.packCompilation.labels.status,
                          ],
                          trailingActionWidth:
                              _compilationRowTrailingActionWidth,
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
        title: t.packCompilation.dialogs.deleteTitle,
        message: t.packCompilation.dialogs.deleteMessage(name: d.compilation.name),
        warningMessage: t.packCompilation.dialogs.deleteWarning,
        confirmLabel: t.common.actions.delete,
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
      FluentToast.success(context, t.packCompilation.messages.deletedSuccess(name: d.compilation.name));
    } else {
      FluentToast.error(context, t.packCompilation.messages.deleteFailed(error: r.error.toString()));
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
              t.packCompilation.messages.noCompilationsYet,
              style: tokens.fontDisplay.copyWith(
                fontSize: 16,
                color: tokens.textMid,
                fontStyle: tokens.fontDisplayStyle,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t.packCompilation.messages.createCompilationHint,
              style:
                  tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
            ),
            const SizedBox(height: 16),
            SmallTextButton(
              label: t.packCompilation.actions.newCompilation,
              icon: FluentIcons.add_24_regular,
              onTap: onNew,
            ),
          ],
        ),
      ),
    );
  }
}

/// Single row in the compilation list, mirroring the Projects-list layout.
///
/// Columns: 80 px game cover (game-specific Fluent icon fallback) /
/// compilation name + .pack filename + relative last-pack timestamp /
/// language label / absolute modified date / status pill (Draft /
/// Regenerate pack / Generated). Tap on the row opens the editor; the
/// trailing icon deletes the compilation after a confirmation dialog.
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
    // Compilation timestamps are stored as Unix *seconds* (see
    // `compilation_repository.dart`), so multiply by 1000 before passing
    // to `DateTime.fromMillisecondsSinceEpoch`.
    final updatedAt =
        DateTime.fromMillisecondsSinceEpoch(compilation.updatedAt * 1000);
    final lastModified = DateFormat('dd/MM/yyyy HH:mm').format(updatedAt);
    final lastGeneratedAt = compilation.lastGeneratedAt;
    final lastGeneratedRelative = lastGeneratedAt == null
        ? null
        : formatRelativeSince(
            DateTime.fromMillisecondsSinceEpoch(lastGeneratedAt * 1000),
            now: now,
          );
    // A compilation pack is stale when at least one bundled project was
    // updated after the last successful generation.
    final needsRegeneration = lastGeneratedAt != null &&
        details.projects.any((p) => p.updatedAt > lastGeneratedAt);

    return ListRow(
      columns: _compilationColumns,
      onTap: onEdit,
      // Null height → the row grows to fit the 80×80 cover, mirroring the
      // Projects-list footprint.
      height: null,
      trailingAction: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: IconButton(
          key: Key('compilation-row-delete-${compilation.id}'),
          icon: const Icon(FluentIcons.delete_24_regular, size: 16),
          tooltip: t.packCompilation.actions.deleteCompilation,
          onPressed: onDelete,
          color: Theme.of(context).colorScheme.error,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ),
      children: [
        // Cover — compilations don't carry an image; fall back to the game
        // icon resolved by ProjectCoverThumbnail's gameCode switch.
        ProjectCoverThumbnail(
          imageUrl: null,
          isGameTranslation: false,
          gameCode: details.gameInstallation?.gameCode,
        ),
        // Name + meta
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                compilation.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (compilation.packName.isNotEmpty)
                    Flexible(
                      child: Text(
                        compilation.packName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.fontMono.copyWith(
                          fontSize: 11,
                          color: tokens.textDim,
                        ),
                      ),
                    ),
                  if (lastGeneratedRelative != null) ...[
                    const SizedBox(width: 10),
                    Icon(
                      FluentIcons.arrow_export_24_regular,
                      size: 12,
                      color: tokens.textFaint,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      lastGeneratedRelative,
                      style: tokens.fontMono.copyWith(
                        fontSize: 10.5,
                        color: tokens.textFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        // Language — single language per compilation; rendered like a
        // Projects-row language line, sans progress bar.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            details.language?.name ?? t.packCompilation.labels.noLanguage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: details.language != null
                  ? tokens.textMid
                  : tokens.textFaint,
            ),
          ),
        ),
        // Modified — absolute date matching the Projects row.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            lastModified,
            style: tokens.fontMono.copyWith(
              fontSize: 11.5,
              color: tokens.textDim,
            ),
          ),
        ),
        // Status pill
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _CompilationStatusPill(
            lastGeneratedAt: lastGeneratedAt,
            needsRegeneration: needsRegeneration,
          ),
        ),
      ],
    );
  }
}

/// Status badge used in the right-most column of [_CompilationRow].
///
/// Three mutually-exclusive states:
///   * never generated         → neutral "Draft" pill
///   * stale (project changed) → warn "Regenerate pack" pill
///   * up to date              → ok    "Generated" pill
class _CompilationStatusPill extends StatelessWidget {
  final int? lastGeneratedAt;
  final bool needsRegeneration;

  const _CompilationStatusPill({
    required this.lastGeneratedAt,
    required this.needsRegeneration,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (lastGeneratedAt == null) {
      return StatusPill(
        label: t.packCompilation.status.draft,
        foreground: tokens.textDim,
        background: tokens.panel,
      );
    }
    if (needsRegeneration) {
      return StatusPill(
        label: t.packCompilation.status.regeneratePack,
        foreground: tokens.warn,
        background: tokens.warnBg,
        tooltip: t.packCompilation.status.regenerateTooltip,
      );
    }
    return StatusPill(
      label: t.packCompilation.status.generated,
      foreground: tokens.ok,
      background: tokens.okBg,
    );
  }
}
