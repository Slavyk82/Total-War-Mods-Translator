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
