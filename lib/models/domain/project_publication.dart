/// A published Steam Workshop item for one project translation, keyed by
/// project and target language.
///
/// Distinct from `Project.modSteamId` (the source mod being translated): this
/// is the Workshop id of the user's OWN published translation pack. Stored in
/// the `project_publication` table, one row per (project, language).
class ProjectPublication {
  final String projectId;
  final String languageCode;
  final String? steamId;
  final int? publishedAt;

  const ProjectPublication({
    required this.projectId,
    required this.languageCode,
    this.steamId,
    this.publishedAt,
  });

  factory ProjectPublication.fromJson(Map<String, dynamic> json) {
    return ProjectPublication(
      projectId: json['project_id'] as String,
      languageCode: json['language_code'] as String,
      steamId: json['steam_id'] as String?,
      publishedAt: json['published_at'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'project_id': projectId,
        'language_code': languageCode,
        'steam_id': steamId,
        'published_at': publishedAt,
      };
}

/// Resolve which target language's published id applies to a per-project
/// publish row. `project_publication` is keyed by (project, language) but the
/// publish list shows one row per project. Prefer 'fr' when it is a target
/// language, else the first target language, else 'fr'.
String resolvePublicationLanguage(List<String> targetLanguages) {
  if (targetLanguages.contains('fr')) return 'fr';
  if (targetLanguages.isNotEmpty) return targetLanguages.first;
  return 'fr';
}

/// Pick the publication row for a project: the one matching the resolved
/// target language, else the first available row, else null.
ProjectPublication? resolvePublication(
    List<ProjectPublication> rows, List<String> targetLanguages) {
  if (rows.isEmpty) return null;
  final lang = resolvePublicationLanguage(targetLanguages);
  for (final row in rows) {
    if (row.languageCode == lang) return row;
  }
  return rows.first;
}
