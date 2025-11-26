import 'package:flutter/material.dart';
import '../providers/projects_screen_providers.dart';
import 'project_card.dart';

/// List layout for displaying project cards.
///
/// Displays project cards in full width.
class ProjectGrid extends StatelessWidget {
  final List<ProjectWithDetails> projects;
  final Function(String projectId)? onProjectTap;

  const ProjectGrid({
    super.key,
    required this.projects,
    this.onProjectTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: projects.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final projectWithDetails = projects[index];
        return ProjectCard(
          projectWithDetails: projectWithDetails,
          onTap: () => onProjectTap?.call(projectWithDetails.project.id),
        );
      },
    );
  }

}
