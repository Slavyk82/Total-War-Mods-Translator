import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/features/translation_editor/screens/progress/progress_widgets.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/wizard/dynamic_zone_panel.dart';
import 'package:twmt/widgets/wizard/form_section.dart';
import 'package:twmt/widgets/wizard/sticky_form_panel.dart';
import 'package:twmt/widgets/wizard/summary_box.dart';
import 'package:twmt/widgets/wizard/wizard_screen_layout.dart';
import '../providers/compilation_conflict_providers.dart';
import '../providers/pack_compilation_providers.dart';
import '../widgets/compilation_bbcode_section.dart';
import '../widgets/compilation_project_selection.dart';
import '../widgets/conflicting_projects_panel.dart';

/// Pack Compilation editor screen (§7.5 wizard archetype).
///
/// When [compilationId] is null, the screen starts in "new" mode (notifier
/// reset on mount). When non-null, it loads the matching compilation via
/// [compilationsWithDetailsProvider] and hydrates the notifier.
///
/// Layout: [WizardScreenLayout] = [DetailScreenToolbar] + [StickyFormPanel]
/// (Basics + Output sections + summary + Cancel/Compile actions) + a
/// [DynamicZonePanel] wrapping an [AnimatedSwitcher] that flips between
/// editing and compiling views.
class PackCompilationEditorScreen extends ConsumerStatefulWidget {
  final String? compilationId;
  const PackCompilationEditorScreen({super.key, required this.compilationId});

  @override
  ConsumerState<PackCompilationEditorScreen> createState() =>
      _PackCompilationEditorScreenState();
}

class _PackCompilationEditorScreenState
    extends ConsumerState<PackCompilationEditorScreen> {
  late final TextEditingController _nameCtl;
  late final TextEditingController _packNameCtl;
  late final TextEditingController _prefixCtl;

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController();
    _packNameCtl = TextEditingController();
    _prefixCtl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final notifier = ref.read(compilationEditorProvider.notifier);
      if (widget.compilationId == null) {
        notifier.reset();
      } else {
        try {
          final list =
              await ref.read(compilationsWithDetailsProvider.future);
          if (!mounted) return;
          final target = list.where(
            (c) => c.compilation.id == widget.compilationId,
          );
          if (target.isNotEmpty) {
            notifier.loadCompilation(target.first);
          } else {
            notifier.reset();
          }
        } catch (_) {
          if (!mounted) return;
          notifier.reset();
        }
      }
      if (!mounted) return;
      // Sync controllers to current state after load.
      final s = ref.read(compilationEditorProvider);
      _nameCtl.text = s.name;
      _packNameCtl.text = s.packName;
      _prefixCtl.text = s.prefix;
    });
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _packNameCtl.dispose();
    _prefixCtl.dispose();
    super.dispose();
  }

  /// Back handler. No-op while compilation is running to avoid orphaning
  /// the RPFM subprocess. Otherwise pops the route.
  void _handleBack() {
    if (ref.read(compilationEditorProvider).isCompiling) return;
    if (context.canPop()) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(compilationEditorProvider);
    final languagesAsync = ref.watch(allLanguagesProvider);
    final currentGameAsync = ref.watch(currentGameInstallationProvider);
    final conflictsAsync = ref.watch(compilationConflictAnalysisProvider);
    final notifier = ref.read(compilationEditorProvider.notifier);
    final languages = languagesAsync.asData?.value ?? const <Language>[];
    final gameInstallation = currentGameAsync.asData?.value;

    // Keep controllers in sync with state when the notifier mutates them
    // externally (e.g. updateLanguage fills the prefix based on code).
    if (_nameCtl.text != state.name) {
      _nameCtl.value = _nameCtl.value.copyWith(
        text: state.name,
        selection: TextSelection.collapsed(offset: state.name.length),
      );
    }
    if (_packNameCtl.text != state.packName) {
      _packNameCtl.value = _packNameCtl.value.copyWith(
        text: state.packName,
        selection: TextSelection.collapsed(offset: state.packName.length),
      );
    }
    if (_prefixCtl.text != state.prefix) {
      _prefixCtl.value = _prefixCtl.value.copyWith(
        text: state.prefix,
        selection: TextSelection.collapsed(offset: state.prefix.length),
      );
    }

    return WizardScreenLayout(
      toolbar: DetailScreenToolbar(
        crumb: state.isEditing
            ? 'Publishing > Pack compilation > ${state.name.isEmpty ? "Untitled" : state.name}'
            : 'Publishing > Pack compilation > New',
        onBack: _handleBack,
      ),
      formPanel: StickyFormPanel(
        sections: [
          FormSection(
            label: 'Basics',
            children: [
              _LabeledField(
                label: 'Name',
                child: _TokenTextField(
                  controller: _nameCtl,
                  hint: 'My French Translations',
                  enabled: !state.isCompiling,
                  onChanged: notifier.updateName,
                ),
              ),
              _LabeledField(
                label: 'Target language',
                child: _LanguageDropdown(
                  languages: languages,
                  selectedId: state.selectedLanguageId,
                  enabled: !state.isCompiling && !state.isEditing,
                  onChanged: (id) => notifier.updateLanguage(id),
                ),
              ),
            ],
          ),
          FormSection(
            label: 'Output',
            children: [
              _LabeledField(
                label: 'Prefix',
                child: _TokenTextField(
                  controller: _prefixCtl,
                  hint: '!!!!!!!!!!_fr_compilation_twmt_',
                  enabled: !state.isCompiling,
                  onChanged: notifier.updatePrefix,
                ),
              ),
              _LabeledField(
                label: 'Pack name',
                child: _TokenTextField(
                  controller: _packNameCtl,
                  hint: 'my_pack',
                  enabled: !state.isCompiling,
                  onChanged: notifier.updatePackName,
                ),
              ),
            ],
          ),
        ],
        summary: SummaryBox(
          label: 'Will generate',
          semantics: _summarySemantics(conflictsAsync),
          lines: _summaryLines(state, conflictsAsync, languages),
        ),
        actions: [
          SmallTextButton(
            label: 'Cancel',
            icon: FluentIcons.dismiss_24_regular,
            onTap: state.isCompiling ? null : _handleBack,
          ),
          SmallTextButton(
            label: state.isCompiling ? 'Compiling...' : 'Compile',
            icon: state.isCompiling
                ? FluentIcons.stop_24_regular
                : FluentIcons.play_24_regular,
            onTap: _buildCompileCallback(state, notifier, gameInstallation),
          ),
        ],
      ),
      dynamicZone: DynamicZonePanel(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: state.isCompiling
              ? _CompilingView(
                  key: const ValueKey('compiling'),
                  state: state,
                  onStop: () => notifier.cancelCompilation(),
                )
              : _EditingView(
                  key: const ValueKey('editing'),
                  state: state,
                  currentGameAsync: currentGameAsync,
                  onToggle: notifier.toggleProject,
                  onSelectAll: notifier.selectAllProjects,
                  onDeselectAll: notifier.deselectAllProjects,
                ),
        ),
      ),
    );
  }

  /// Builds the Compile action callback. Returns null when the action is
  /// unavailable — visually disables the button (SmallTextButton keeps its
  /// outlined look with a null onTap).
  VoidCallback? _buildCompileCallback(
    CompilationEditorState state,
    CompilationEditorNotifier notifier,
    GameInstallation? gameInstallation,
  ) {
    if (state.isCompiling) return null;
    if (gameInstallation == null) return null;
    if (!state.canCompile) return null;
    return () async {
      final success = await notifier.generatePack(gameInstallation.id);
      if (success) {
        ref.invalidate(compilationsWithDetailsProvider);
      }
    };
  }

  SummarySemantics _summarySemantics(
    AsyncValue<dynamic> conflictsAsync,
  ) {
    final analysis = conflictsAsync.asData?.value;
    final count = analysis?.conflicts.length ?? 0;
    return count > 0 ? SummarySemantics.warn : SummarySemantics.accent;
  }

  List<SummaryLine> _summaryLines(
    CompilationEditorState state,
    AsyncValue<dynamic> conflictsAsync,
    List<Language> languages,
  ) {
    // Target language display name ("English (English)") or em dash when not
    // resolved yet.
    String langName = '—';
    if (state.selectedLanguageId != null) {
      for (final l in languages) {
        if (l.id == state.selectedLanguageId) {
          langName = l.displayName;
          break;
        }
      }
    }
    final analysis = conflictsAsync.asData?.value;
    final conflictCount = analysis?.conflicts.length ?? 0;
    final filename = state.fullPackName.isEmpty ? '—' : state.fullPackName;
    return [
      SummaryLine(
        key: 'Filename',
        value: filename,
      ),
      SummaryLine(
        key: 'Projects',
        value: '${state.selectedProjectIds.length} selected',
      ),
      SummaryLine(
        key: 'Target language',
        value: langName,
      ),
      SummaryLine(
        key: 'Conflicts',
        value: conflictCount > 0 ? '$conflictCount' : 'None',
        semantics:
            conflictCount > 0 ? SummarySemantics.warn : SummarySemantics.ok,
      ),
      const SummaryLine(
        key: 'Size estimate',
        value: '—',
      ),
    ];
  }
}

/// Editing view: project selection list, conflict panel when applicable,
/// and BBCode section.
class _EditingView extends ConsumerWidget {
  final CompilationEditorState state;
  final AsyncValue<GameInstallation?> currentGameAsync;
  final void Function(String) onToggle;
  final void Function(List<String>) onSelectAll;
  final VoidCallback onDeselectAll;

  const _EditingView({
    super.key,
    required this.state,
    required this.currentGameAsync,
    required this.onToggle,
    required this.onSelectAll,
    required this.onDeselectAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showConflicts = state.selectedProjectIds.length >= 2 &&
        state.selectedLanguageId != null;
    final hasSelection = state.selectedProjectIds.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary project selection list. Sized region so the internal
        // Expanded/ListView render correctly inside the wizard column.
        SizedBox(
          height: 420,
          child: CompilationProjectSelectionSection(
            state: state,
            currentGameAsync: currentGameAsync,
            onToggle: (id) async {
              final wasSelected = state.selectedProjectIds.contains(id);
              ref.read(compilationEditorProvider.notifier).toggleProject(id);

              // When adding a project brings the count to >= 2, re-run
              // conflict analysis so the panel surfaces the overlap.
              if (!wasSelected && state.selectedLanguageId != null) {
                await Future.delayed(const Duration(milliseconds: 100));
                final current = ref.read(compilationEditorProvider);
                if (current.selectedProjectIds.length >= 2) {
                  ref
                      .read(compilationConflictResolutionsStateProvider
                          .notifier)
                      .clear();
                  await ref
                      .read(compilationConflictAnalysisProvider.notifier)
                      .analyze(
                        projectIds: current.selectedProjectIds.toList(),
                        languageId: current.selectedLanguageId!,
                      );
                }
              }
            },
            onSelectAll: (ids) async {
              ref
                  .read(compilationEditorProvider.notifier)
                  .selectAllProjects(ids);
              if (state.selectedLanguageId != null && ids.length >= 2) {
                await Future.delayed(const Duration(milliseconds: 100));
                final current = ref.read(compilationEditorProvider);
                if (current.selectedProjectIds.length >= 2) {
                  ref
                      .read(compilationConflictResolutionsStateProvider
                          .notifier)
                      .clear();
                  await ref
                      .read(compilationConflictAnalysisProvider.notifier)
                      .analyze(
                        projectIds: current.selectedProjectIds.toList(),
                        languageId: current.selectedLanguageId!,
                      );
                }
              }
            },
            onDeselectAll: () {
              ref
                  .read(compilationEditorProvider.notifier)
                  .deselectAllProjects();
              ref
                  .read(compilationConflictAnalysisProvider.notifier)
                  .clear();
            },
          ),
        ),
        if (showConflicts) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 240,
            child: ConflictingProjectsPanel(
              selectedProjectIds: state.selectedProjectIds,
              onToggleProject: (id) {
                ref.read(compilationEditorProvider.notifier).toggleProject(id);
                Future.delayed(const Duration(milliseconds: 100), () async {
                  final current = ref.read(compilationEditorProvider);
                  if (current.selectedProjectIds.length >= 2 &&
                      current.selectedLanguageId != null) {
                    ref
                        .read(compilationConflictResolutionsStateProvider
                            .notifier)
                        .clear();
                    await ref
                        .read(compilationConflictAnalysisProvider.notifier)
                        .analyze(
                          projectIds: current.selectedProjectIds.toList(),
                          languageId: current.selectedLanguageId!,
                        );
                  } else {
                    ref
                        .read(compilationConflictAnalysisProvider.notifier)
                        .clear();
                  }
                });
              },
            ),
          ),
        ],
        if (hasSelection) ...[
          const SizedBox(height: 16),
          const CompilationBBCodeSection(),
        ],
      ],
    );
  }
}

/// Compiling view: inline progress card + expandable log terminal.
class _CompilingView extends StatelessWidget {
  final CompilationEditorState state;
  final VoidCallback onStop;
  const _CompilingView({
    super.key,
    required this.state,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Inline progress card. Replaces the legacy `CompilationProgressSection`
        // so the wizard panel can evolve independently.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.panel2,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    FluentIcons.play_24_regular,
                    size: 18,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Generating pack...',
                      style: tokens.fontDisplay.copyWith(
                        fontSize: 14,
                        color: tokens.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${(state.progress * 100).toInt()}%',
                    style: tokens.fontMono.copyWith(
                      fontSize: 12,
                      color: tokens.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SmallIconButton(
                    icon: FluentIcons.stop_24_regular,
                    tooltip: state.isCancelled ? 'Cancelling...' : 'Stop',
                    onTap: state.isCancelled ? () {} : onStop,
                    foreground: tokens.err,
                    background: tokens.errBg,
                    borderColor: tokens.err.withValues(alpha: 0.3),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: state.progress.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: tokens.panel,
                  valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
                ),
              ),
              if (state.currentStep != null) ...[
                const SizedBox(height: 10),
                Text(
                  state.currentStep!,
                  style: tokens.fontMono.copyWith(
                    fontSize: 11,
                    color: tokens.textDim,
                  ),
                ),
              ],
              if (state.errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  state.errorMessage!,
                  style: tokens.fontBody.copyWith(
                    fontSize: 12,
                    color: tokens.err,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Expanded(child: LogTerminal(expand: true)),
      ],
    );
  }
}

/// Thin label + child wrapper used inside form sections.
class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: tokens.fontBody.copyWith(
            fontSize: 11,
            color: tokens.textDim,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

/// Token-themed thin TextField matching the wizard visual language.
class _TokenTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _TokenTextField({
    required this.controller,
    required this.hint,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      height: 32,
      child: TextField(
        controller: controller,
        enabled: enabled,
        style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.text),
        onChanged: onChanged,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: tokens.panel2,
          hintText: hint,
          hintStyle: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.textFaint,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            borderSide: BorderSide(color: tokens.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            borderSide: BorderSide(color: tokens.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            borderSide: BorderSide(color: tokens.accent),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            borderSide:
                BorderSide(color: tokens.border.withValues(alpha: 0.4)),
          ),
        ),
      ),
    );
  }
}

/// Token-themed language dropdown.
class _LanguageDropdown extends StatelessWidget {
  final List<Language> languages;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  const _LanguageDropdown({
    required this.languages,
    required this.selectedId,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Guard: if the current id isn't in the list yet, let DropdownButton
    // fall back to the hint instead of throwing.
    final hasSelected = selectedId != null &&
        languages.any((l) => l.id == selectedId);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.panel2,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: hasSelected ? selectedId : null,
          isExpanded: true,
          isDense: true,
          hint: Text(
            'Select a language...',
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.textFaint,
            ),
          ),
          style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.text),
          dropdownColor: tokens.panel,
          icon: Icon(
            FluentIcons.chevron_down_24_regular,
            size: 14,
            color: tokens.textDim,
          ),
          items: languages
              .map(
                (l) => DropdownMenuItem<String>(
                  value: l.id,
                  child: Text(
                    l.displayName,
                    style:
                        tokens.fontBody.copyWith(fontSize: 13, color: tokens.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}
