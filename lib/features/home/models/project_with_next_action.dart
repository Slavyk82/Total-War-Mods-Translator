import 'package:twmt/models/domain/project.dart';

import 'next_project_action.dart';

class ProjectWithNextAction {
  final Project project;
  final NextProjectAction action;
  final int translatedPct;

  const ProjectWithNextAction({
    required this.project,
    required this.action,
    required this.translatedPct,
  });
}
