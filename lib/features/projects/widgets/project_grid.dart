import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/projects_screen_providers.dart';
import 'project_card.dart';

/// Responsive grid layout for displaying project cards.
///
/// Automatically adjusts column count based on available width:
/// - Wide screens (>1400px): 3 columns
/// - Medium screens (>900px): 2 columns
/// - Narrow screens: 1 column
class ProjectGrid extends ConsumerWidget {
  final List<ProjectWithDetails> projects;
  final Function(String projectId)? onProjectTap;
  final Function(String projectId)? onProjectEdit;
  final Function(String projectId)? onProjectExport;
  final Function(String projectId)? onProjectDelete;

  const ProjectGrid({
    super.key,
    required this.projects,
    this.onProjectTap,
    this.onProjectEdit,
    this.onProjectExport,
    this.onProjectDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(
      projectsFilterProvider.select((state) => state.viewMode),
    );

    if (viewMode == ProjectViewMode.list) {
      return _buildListView(context);
    } else {
      return _buildGridView(context);
    }
  }

  Widget _buildGridView(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = _getColumnCount(constraints.maxWidth);

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            childAspectRatio: 1.3,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: projects.length,
          itemBuilder: (context, index) {
            final projectWithDetails = projects[index];
            return ProjectCard(
              projectWithDetails: projectWithDetails,
              onTap: () => onProjectTap?.call(projectWithDetails.project.id),
              onEdit: () => onProjectEdit?.call(projectWithDetails.project.id),
              onExport: () =>
                  onProjectExport?.call(projectWithDetails.project.id),
              onDelete: () =>
                  onProjectDelete?.call(projectWithDetails.project.id),
            );
          },
        );
      },
    );
  }

  Widget _buildListView(BuildContext context) {
    return ListView.separated(
      itemCount: projects.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final projectWithDetails = projects[index];
        return ProjectCard(
          projectWithDetails: projectWithDetails,
          onTap: () => onProjectTap?.call(projectWithDetails.project.id),
          onEdit: () => onProjectEdit?.call(projectWithDetails.project.id),
          onExport: () =>
              onProjectExport?.call(projectWithDetails.project.id),
          onDelete: () =>
              onProjectDelete?.call(projectWithDetails.project.id),
        );
      },
    );
  }

  int _getColumnCount(double width) {
    if (width > 1400) {
      return 3;
    } else if (width > 900) {
      return 2;
    } else {
      return 1;
    }
  }
}
