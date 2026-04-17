import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/game_translation/providers/game_translation_providers.dart';
import 'package:twmt/features/projects/providers/project_detail_providers.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/widgets/add_language_dialog.dart';
import 'package:twmt/features/projects/widgets/language_progress_row.dart';
import 'package:twmt/services/game/game_localization_service.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/utils/string_initials.dart';
import 'package:twmt/widgets/detail/detail_cover.dart';
import 'package:twmt/widgets/detail/detail_meta_banner.dart';
import 'package:twmt/widgets/detail/detail_overview_layout.dart';
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';
import 'package:twmt/widgets/detail/stats_rail.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/list_row.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/lists/status_pill.dart';

/// Project detail screen (§7.2 archetype).
class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final detailsAsync = ref.watch(projectDetailsProvider(widget.projectId));

    return Material(
      color: tokens.bg,
      child: detailsAsync.when(
        data: (details) => _Content(
          details: details,
          onBack: _handleBack,
          onAddLanguage: () => _handleAddLanguage(details),
          onDeleteProject: () => _handleDeleteProject(details),
          onOpenEditor: (ld) => _handleOpenEditor(ld),
          onDeleteLanguage: (ld) => _handleDeleteLanguage(details, ld),
          onLaunchSteam: (modId) => _launchSteamWorkshop(modId),
        ),
        loading: () => const _LoadingView(),
        error: (err, _) => _ErrorView(
          error: err,
          onBack: _handleBack,
        ),
      ),
    );
  }

  void _handleBack() {
    ref.read(translationStatsVersionProvider.notifier).increment();
    Navigator.of(context).pop();
  }

  void _handleAddLanguage(ProjectDetails details) {
    final existing =
        details.languages.map((l) => l.projectLanguage.languageId).toList();
    showDialog(
      context: context,
      builder: (_) => AddLanguageDialog(
        projectId: details.project.id,
        existingLanguageIds: existing,
      ),
    );
  }

  Future<void> _handleOpenEditor(ProjectLanguageDetails ld) async {
    await context.push(
      AppRoutes.translationEditor(widget.projectId, ld.projectLanguage.languageId),
    );
    if (!mounted) return;
    ref.invalidate(projectDetailsProvider(widget.projectId));
    ref.invalidate(projectsWithDetailsProvider);
  }

  Future<void> _launchSteamWorkshop(String modId) async {
    final url = Uri.parse(
        'https://steamcommunity.com/sharedfiles/filedetails/?id=$modId');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void _handleDeleteProject(ProjectDetails details) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Project'),
        content: Text(
            'Are you sure you want to delete "${details.project.name}"? This action cannot be undone.'),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FluentTextButton(
            onPressed: () => _performDeleteProject(dialogCtx, details),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performDeleteProject(
      BuildContext dialogCtx, ProjectDetails details) async {
    Navigator.of(dialogCtx).pop();
    final loadingCtx = context;
    showDialog(
      context: loadingCtx,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    final result =
        await ref.read(projectRepositoryProvider).delete(details.project.id);
    if (loadingCtx.mounted) {
      Navigator.of(loadingCtx, rootNavigator: true).pop();
    }
    if (!context.mounted) return;
    if (result.isOk) {
      ref.invalidate(projectsWithDetailsProvider);
      ref.invalidate(gameTranslationProjectsProvider);
      if (details.project.isGameTranslation) {
        context.go(AppRoutes.gameFiles);
      } else {
        context.go(AppRoutes.projects);
      }
      if (context.mounted) {
        FluentToast.success(context,
            'Project "${details.project.name}" deleted successfully');
      }
    } else {
      FluentToast.error(context, 'Failed to delete project: ${result.error}');
    }
  }

  void _handleDeleteLanguage(
    ProjectDetails details,
    ProjectLanguageDetails ld,
  ) {
    final name = ld.language.displayName;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Language'),
        content: Text(
            'Remove "$name" from this project? ${ld.translatedUnits} translations will be deleted. This cannot be undone.'),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FluentTextButton(
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              final result = await ref
                  .read(projectLanguageRepositoryProvider)
                  .delete(ld.projectLanguage.id);
              if (!context.mounted) return;
              if (result.isOk) {
                ref.invalidate(projectDetailsProvider(widget.projectId));
                ref.invalidate(projectsWithDetailsProvider);
                FluentToast.success(context, '"$name" removed from project');
              } else {
                FluentToast.error(
                    context, 'Failed to delete language: ${result.error}');
              }
            },
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  final ProjectDetails details;
  final VoidCallback onBack;
  final VoidCallback onAddLanguage;
  final VoidCallback onDeleteProject;
  final ValueChanged<ProjectLanguageDetails> onOpenEditor;
  final ValueChanged<ProjectLanguageDetails> onDeleteLanguage;
  final ValueChanged<String> onLaunchSteam;

  const _Content({
    required this.details,
    required this.onBack,
    required this.onAddLanguage,
    required this.onDeleteProject,
    required this.onOpenEditor,
    required this.onDeleteLanguage,
    required this.onLaunchSteam,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final p = details.project;
    final isGame = p.isGameTranslation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailScreenToolbar(
          crumb:
              'Work › Projects › ${p.name}',
          onBack: onBack,
        ),
        DetailMetaBanner(
          cover: DetailCover(
            imageUrl: p.imageUrl,
            monogramFallback: initials(p.name),
          ),
          title: p.name,
          subtitle: [
            StatusPill(
              label: isGame ? 'GAME' : 'MOD',
              foreground: isGame ? tokens.llm : tokens.accent,
              background: isGame ? tokens.llmBg : tokens.accentBg,
            ),
            if (isGame && p.sourceLanguageCode != null)
              Text(
                  'source: ${GameLocalizationService.languageCodeNames[p.sourceLanguageCode] ?? p.sourceLanguageCode!.toUpperCase()}'),
            if (p.modSteamId != null) Text('steam: ${p.modSteamId}'),
            Text('${details.languages.length} languages'),
          ],
          actions: [
            if (p.modSteamId != null)
              SmallIconButton(
                icon: FluentIcons.open_24_regular,
                tooltip: 'Open in Steam Workshop',
                onTap: () => onLaunchSteam(p.modSteamId!),
              ),
            SmallTextButton(
              label: '+ Language',
              icon: FluentIcons.add_24_regular,
              onTap: onAddLanguage,
            ),
            SmallIconButton(
              icon: FluentIcons.delete_24_regular,
              tooltip: 'Delete project',
              onTap: onDeleteProject,
              foreground: tokens.err,
              borderColor: tokens.err.withValues(alpha: 0.3),
              background: tokens.errBg,
            ),
          ],
        ),
        Expanded(
          child: DetailOverviewLayout(
            main: _LanguagesSection(
              details: details,
              onOpenEditor: onOpenEditor,
              onDeleteLanguage: onDeleteLanguage,
              onAddLanguage: onAddLanguage,
            ),
            rail: _ProjectStatsRail(stats: details.stats),
          ),
        ),
      ],
    );
  }
}

class _LanguagesSection extends StatelessWidget {
  final ProjectDetails details;
  final ValueChanged<ProjectLanguageDetails> onOpenEditor;
  final ValueChanged<ProjectLanguageDetails> onDeleteLanguage;
  final VoidCallback onAddLanguage;

  const _LanguagesSection({
    required this.details,
    required this.onOpenEditor,
    required this.onDeleteLanguage,
    required this.onAddLanguage,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (details.languages.isEmpty) {
      return _EmptyLanguages(onAdd: onAddLanguage);
    }
    return Container(
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListRowHeader(
            columns: const [
              ListRowColumn.flex(1),
              ListRowColumn.fixed(60),
              ListRowColumn.fixed(120),
              ListRowColumn.fixed(100),
            ],
            labels: const ['Language', '%', 'Progress', 'Units'],
          ),
          for (final ld in details.languages)
            LanguageProgressRow(
              langDetails: ld,
              onOpenEditor: () => onOpenEditor(ld),
              onDelete: () => onDeleteLanguage(ld),
            ),
        ],
      ),
    );
  }
}

class _EmptyLanguages extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyLanguages({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusLg),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FluentIcons.translate_off_24_regular,
                size: 48, color: tokens.textFaint),
            const SizedBox(height: 16),
            Text(
              'No target languages',
              style: tokens.fontDisplay.copyWith(
                fontSize: 16,
                color: tokens.textMid,
                fontStyle:
                    tokens.fontDisplayItalic ? FontStyle.italic : FontStyle.normal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a target language to start translating',
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.textDim,
              ),
            ),
            const SizedBox(height: 16),
            SmallTextButton(
              label: 'Add language',
              icon: FluentIcons.add_24_regular,
              onTap: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectStatsRail extends StatelessWidget {
  final TranslationStats stats;
  const _ProjectStatsRail({required this.stats});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final percent = stats.progressPercent;
    return StatsRail(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Overall progress',
                  style: tokens.fontBody.copyWith(
                    fontSize: 12,
                    color: tokens.textMid,
                  ),
                ),
              ),
              Text(
                '${percent.toInt()}%',
                style: tokens.fontMono.copyWith(
                  fontSize: 15,
                  color: tokens.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 4,
              backgroundColor: tokens.border,
              valueColor: AlwaysStoppedAnimation(tokens.accent),
            ),
          ),
        ],
      ),
      sections: [
        StatsRailSection(
          label: 'Overview',
          rows: [
            StatsRailRow(
              label: 'Translated',
              value: stats.translatedUnits.toString(),
              semantics: StatsSemantics.ok,
            ),
            StatsRailRow(
              label: 'Pending',
              value: stats.pendingUnits.toString(),
              semantics: StatsSemantics.warn,
            ),
            StatsRailRow(
              label: 'Needs review',
              value: stats.needsReviewUnits.toString(),
              semantics: StatsSemantics.err,
            ),
            StatsRailRow(
              label: 'Total',
              value: stats.totalUnits.toString(),
            ),
          ],
        ),
        StatsRailSection(
          label: 'Efficiency',
          rows: [
            StatsRailRow(
              label: 'TM reuse',
              value: '${(stats.tmReuseRate * 100).toStringAsFixed(1)}%',
            ),
            StatsRailRow(
              label: 'Tokens used',
              value: _formatNumber(stats.tokensUsed),
            ),
          ],
        ),
      ],
      hint: _computeHint(stats),
    );
  }

  StatsRailHint? _computeHint(TranslationStats stats) {
    if (stats.needsReviewUnits > 0) {
      return StatsRailHint(
        kicker: 'NEXT',
        message: '${stats.needsReviewUnits} units to review',
        semantics: StatsSemantics.err,
      );
    }
    if (stats.pendingUnits == 0 && stats.totalUnits > 0) {
      return const StatsRailHint(
        kicker: 'NEXT',
        message: 'Ready to compile a pack',
        semantics: StatsSemantics.ok,
      );
    }
    return null;
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onBack;
  const _ErrorView({required this.error, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FluentIcons.error_circle_24_regular,
                size: 48, color: tokens.err),
            const SizedBox(height: 12),
            Text(
              'Failed to load project',
              style: tokens.fontDisplay.copyWith(
                fontSize: 16,
                color: tokens.err,
                fontStyle:
                    tokens.fontDisplayItalic ? FontStyle.italic : FontStyle.normal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style:
                  tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
            ),
            const SizedBox(height: 16),
            SmallTextButton(label: 'Go back', onTap: onBack),
          ],
        ),
      ),
    );
  }
}
