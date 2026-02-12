import 'package:flutter/material.dart';
import '../providers/projects_screen_providers.dart';
import 'project_card.dart';

/// List layout for displaying project cards.
///
/// Displays project cards in full width.
class ProjectGrid extends StatelessWidget {
  final List<ProjectWithDetails> projects;
  final Function(String projectId)? onProjectTap;
  final Function(String projectId)? onResync;
  final Set<String> resyncingProjects;
  final bool isSelectionMode;
  final Set<String> selectedProjectIds;
  final Function(String projectId)? onSelectionToggle;

  const ProjectGrid({
    super.key,
    required this.projects,
    this.onProjectTap,
    this.onResync,
    this.resyncingProjects = const {},
    this.isSelectionMode = false,
    this.selectedProjectIds = const {},
    this.onSelectionToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: projects.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final projectWithDetails = projects[index];
        final projectId = projectWithDetails.project.id;
        return ProjectCard(
          projectWithDetails: projectWithDetails,
          onTap: () => onProjectTap?.call(projectId),
          onResync: () => onResync?.call(projectId),
          isResyncing: resyncingProjects.contains(projectId),
          isSelectionMode: isSelectionMode,
          isSelected: selectedProjectIds.contains(projectId),
          onSelectionToggle: () => onSelectionToggle?.call(projectId),
        );
      },
    );
  }
}
