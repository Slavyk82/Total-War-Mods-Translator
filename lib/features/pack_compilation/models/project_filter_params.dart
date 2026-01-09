/// Parameters for filtering projects in the compilation editor.
///
/// Used by projectsWithTranslationProvider to filter projects
/// by game installation and language.
class ProjectFilterParams {
  final String? gameInstallationId;
  final String? languageId;

  const ProjectFilterParams({
    this.gameInstallationId,
    this.languageId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectFilterParams &&
          runtimeType == other.runtimeType &&
          gameInstallationId == other.gameInstallationId &&
          languageId == other.languageId;

  @override
  int get hashCode => gameInstallationId.hashCode ^ languageId.hashCode;
}
