import '../../../models/domain/compilation.dart';
import '../../../models/domain/game_installation.dart';
import '../../../models/domain/project.dart';

/// Compilation with related data.
///
/// Contains the compilation entity along with its associated
/// game installation and project list for display purposes.
class CompilationWithDetails {
  final Compilation compilation;
  final GameInstallation? gameInstallation;
  final List<Project> projects;
  final int projectCount;

  const CompilationWithDetails({
    required this.compilation,
    this.gameInstallation,
    required this.projects,
    required this.projectCount,
  });
}
