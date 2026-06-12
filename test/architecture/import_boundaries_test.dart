import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'import_graph.dart';

/// Known, intentionally-tolerated violations. EACH entry must be removed by
/// the lot that fixes it. Format: '<importerLibPath> -> <importedLibPath>'.
/// The allowlist shrinks to empty; do NOT add new entries.
const _allowlist = <String>{
  // === Seeded in Lot 0 (run with TWMT_PRINT_VIOLATIONS=1 to regenerate) ===
  'lib/features/bootstrap/widgets/mod_scan_boot_dialog.dart -> lib/features/mods/models/scan_log_message.dart', // lot:2
  'lib/features/bootstrap/widgets/mod_scan_boot_dialog.dart -> lib/features/mods/providers/mods_screen_providers.dart', // lot:2
  'lib/features/bootstrap/widgets/mod_scan_boot_dialog.dart -> lib/features/mods/widgets/scan_terminal_widget.dart', // lot:2
  'lib/features/bootstrap/widgets/mod_scan_boot_dialog.dart -> lib/features/steam_publish/providers/published_subs_cache_provider.dart', // lot:2
  'lib/features/game_translation/providers/game_translation_providers.dart -> lib/features/projects/providers/projects_screen_providers.dart', // lot:2
  'lib/features/game_translation/screens/game_translation_screen.dart -> lib/features/projects/providers/projects_screen_providers.dart', // lot:2
  'lib/features/game_translation/screens/game_translation_screen.dart -> lib/features/projects/utils/open_project_editor.dart', // lot:2
  'lib/features/game_translation/screens/game_translation_screen.dart -> lib/features/projects/widgets/project_grid.dart', // lot:2
  'lib/features/game_translation/widgets/create_game_translation/create_game_translation_dialog.dart -> lib/features/projects/providers/projects_screen_providers.dart', // lot:2
  'lib/features/game_translation/widgets/create_game_translation/step_select_targets.dart -> lib/features/projects/providers/projects_screen_providers.dart', // lot:2
  'lib/features/game_translation/widgets/create_game_translation/step_select_targets.dart -> lib/features/settings/providers/language_settings_providers.dart', // lot:1
  'lib/features/home/providers/action_grid_providers.dart -> lib/features/projects/providers/projects_screen_providers.dart', // lot:2
  'lib/features/home/providers/workflow_providers.dart -> lib/features/mods/providers/mods_screen_providers.dart', // lot:2
  'lib/features/mods/utils/mods_screen_controller.dart -> lib/features/projects/providers/projects_screen_providers.dart', // lot:2
  'lib/features/mods/utils/mods_screen_controller.dart -> lib/features/projects/utils/open_project_editor.dart', // lot:2
  'lib/features/mods/utils/mods_screen_controller.dart -> lib/features/projects/widgets/project_initialization_dialog.dart', // lot:2
  'lib/features/mods/widgets/whats_new_dialog.dart -> lib/features/projects/utils/open_project_editor.dart', // lot:2
  'lib/features/pack_compilation/providers/compilation_editor_notifier.dart -> lib/features/home/providers/workflow_providers.dart', // lot:2
  'lib/features/pack_compilation/providers/pack_compilation_providers.dart -> lib/features/projects/providers/projects_screen_providers.dart', // lot:2
  'lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart -> lib/features/translation_editor/screens/progress/progress_widgets.dart', // lot:2
  'lib/features/projects/services/bulk_operations_handlers.dart -> lib/features/translation_editor/providers/llm_model_providers.dart', // lot:2
  'lib/features/projects/services/bulk_operations_handlers.dart -> lib/features/translation_editor/providers/translation_settings_provider.dart', // lot:2
  'lib/features/projects/widgets/bulk_review_dialog.dart -> lib/features/translation_editor/providers/llm_model_providers.dart', // lot:2
  'lib/features/projects/widgets/projects_bulk_menu_panel.dart -> lib/features/translation_editor/widgets/editor_toolbar_batch_settings.dart', // lot:2
  'lib/features/projects/widgets/projects_bulk_menu_panel.dart -> lib/features/translation_editor/widgets/editor_toolbar_model_selector.dart', // lot:2
  'lib/features/projects/widgets/projects_bulk_menu_panel.dart -> lib/features/translation_editor/widgets/editor_toolbar_skip_tm.dart', // lot:2
  'lib/features/steam_publish/screens/batch_workshop_publish_screen.dart -> lib/features/translation_editor/screens/progress/progress_widgets.dart', // lot:2
  'lib/features/translation_editor/screens/actions/editor_actions_base.dart -> lib/features/projects/providers/projects_screen_providers.dart', // lot:2
  'lib/features/translation_editor/widgets/editor_datagrid.dart -> lib/features/projects/providers/projects_screen_providers.dart', // lot:2
  'lib/features/translation_editor/widgets/editor_language_switcher.dart -> lib/features/projects/providers/project_detail_providers.dart', // lot:2
  'lib/features/translation_editor/widgets/editor_language_switcher.dart -> lib/features/projects/providers/projects_screen_providers.dart', // lot:2
  'lib/features/translation_editor/widgets/editor_language_switcher.dart -> lib/features/projects/utils/open_project_editor.dart', // lot:2
  'lib/features/translation_editor/widgets/editor_language_switcher.dart -> lib/features/projects/widgets/add_language_dialog.dart', // lot:2
  'lib/features/translation_editor/widgets/editor_toolbar_mod_rule.dart -> lib/features/settings/providers/llm_custom_rules_providers.dart', // lot:1
  'lib/features/translation_editor/widgets/grid_actions_handler.dart -> lib/features/projects/providers/projects_screen_providers.dart', // lot:2
  'lib/features/translation_editor/widgets/mod_rule_editor_dialog.dart -> lib/features/settings/providers/llm_custom_rules_providers.dart', // lot:1
  'lib/models/common/validation_issue_entry.dart -> lib/services/translation/models/translation_exceptions.dart', // lot:2
  'lib/models/common/validation_issue_entry.dart -> lib/services/translation/models/validation_rule.dart', // lot:2
  'lib/models/common/validation_result.dart -> lib/services/translation/models/translation_exceptions.dart', // lot:2
  'lib/services/mods/game_installation_sync_service.dart -> lib/providers/settings_providers.dart', // lot:3 (service→Riverpod leak; was a settings_providers entry, relocated by lot:1 promotion)
  'lib/services/translation/headless_batch_translation_runner.dart -> lib/features/translation_editor/providers/translation_settings_provider.dart', // lot:3
  'lib/services/translation/headless_batch_translation_runner.dart -> lib/providers/shared/service_providers.dart', // lot:3
  'lib/services/translation/headless_validation_rescan_service.dart -> lib/providers/shared/repository_providers.dart', // lot:3
  'lib/services/translation/headless_validation_rescan_service.dart -> lib/providers/shared/service_providers.dart', // lot:3
  'lib/widgets/sidebar_update_checker.dart -> lib/features/release_notes/widgets/all_release_notes_dialog.dart', // lot:2
  'lib/widgets/sidebar_update_checker.dart -> lib/features/settings/providers/update_providers.dart', // lot:1
};

/// Paths that LOOK like Riverpod providers but are not (service purity rule).
bool _isProviderFalsePositive(String libPath) =>
    libPath.startsWith('lib/services/llm/providers/') ||
    libPath.startsWith('lib/services/database/migrations/') ||
    libPath == 'lib/repositories/translation_provider_repository.dart';

String _featureOf(String libPath) {
  const prefix = 'lib/features/';
  if (!libPath.startsWith(prefix)) return '';
  return libPath.substring(prefix.length).split('/').first;
}

bool _isRiverpodProviderImport(String importedLibPath) {
  if (_isProviderFalsePositive(importedLibPath)) return false;
  return importedLibPath.contains('/providers/') ||
      importedLibPath.endsWith('_provider.dart') ||
      importedLibPath.endsWith('_providers.dart');
}

void main() {
  final libDir = Directory('lib');
  final files = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('.g.dart'))
      .where((f) => !f.path.endsWith('.freezed.dart'))
      .map((f) => f.path.replaceAll(r'\', '/'))
      .toList();

  final violations = <String>[];

  for (final libRel in files) {
    final imports = importsOf(libRel, libRel);
    for (final target in imports) {
      final srcF = _featureOf(libRel);
      final tgtF = _featureOf(target);
      if (srcF.isNotEmpty && tgtF.isNotEmpty && srcF != tgtF) {
        violations.add('$libRel -> $target');
        continue;
      }
      if (libRel.startsWith('lib/services/') &&
          _isRiverpodProviderImport(target)) {
        violations.add('$libRel -> $target');
        continue;
      }
      if (libRel.startsWith('lib/models/') &&
          !(target.startsWith('lib/models/'))) {
        violations.add('$libRel -> $target');
        continue;
      }
      if (libRel.startsWith('lib/widgets/') && tgtF.isNotEmpty) {
        violations.add('$libRel -> $target');
        continue;
      }
    }
  }

  if (Platform.environment['TWMT_PRINT_VIOLATIONS'] == '1') {
    for (final v in violations..sort()) {
      // ignore: avoid_print
      print("  '$v',");
    }
  }

  test('no import-boundary violations outside the allowlist', () {
    final unexpected =
        violations.where((v) => !_allowlist.contains(v)).toList()..sort();
    expect(
      unexpected,
      isEmpty,
      reason: 'New layering violations introduced:\n${unexpected.join('\n')}\n'
          'Fix the import (promote shared code to a global layer or inject '
          'via constructor) — do not add to the allowlist.',
    );
  });

  test('allowlist has no stale entries', () {
    final stale = _allowlist.where((v) => !violations.contains(v)).toList()
      ..sort();
    expect(
      stale,
      isEmpty,
      reason: 'Allowlist entries no longer violate — delete them:\n'
          '${stale.join('\n')}',
    );
  });
}
