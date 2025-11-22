// Re-export the refactored CreateProjectDialog for backward compatibility.
//
// The original 870-line file has been refactored into separate components
// following CLAUDE.md Single Responsibility principle:
// - create_project/create_project_dialog.dart (wizard coordinator)
// - create_project/step_basic_info.dart (step 1)
// - create_project/step_languages.dart (step 2)
// - create_project/step_settings.dart (step 3)
// - create_project/project_creation_state.dart (shared state)

export 'create_project/create_project_dialog.dart';
