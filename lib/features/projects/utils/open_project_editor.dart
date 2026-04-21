import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/projects/providers/project_detail_providers.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Resolves which `languageId` to land on when opening a project.
///
/// Rule: if the project contains a language whose `code` matches
/// `SettingsKeys.defaultTargetLanguage`, return that language's id. Otherwise
/// return the first project language. Returns `null` when the project has no
/// language.
Future<String?> resolveTargetLanguageId(
  T Function<T>(ProviderListenable<T>) read,
  String projectId,
) async {
  final langs = await read(projectLanguagesProvider(projectId).future);
  if (langs.isEmpty) return null;

  final settings = read(settingsServiceProvider);
  final defaultCode = await settings.getString(
    SettingsKeys.defaultTargetLanguage,
    defaultValue: SettingsKeys.defaultTargetLanguageValue,
  );

  final match = langs.where((l) => l.language.code == defaultCode).firstOrNull;
  return (match ?? langs.first).projectLanguage.languageId;
}

/// Navigate to the translation editor for the given project, resolving the
/// target language automatically. Shows a toast and returns to the projects
/// list when the project has no language yet.
Future<void> openProjectEditor(
  BuildContext context,
  WidgetRef ref,
  String projectId,
) async {
  final languageId = await resolveTargetLanguageId(ref.read, projectId);
  if (!context.mounted) return;
  if (languageId == null) {
    FluentToast.warning(context, 'This project has no target language');
    context.go(AppRoutes.projects);
    return;
  }
  context.go(AppRoutes.translationEditor(projectId, languageId));
}
