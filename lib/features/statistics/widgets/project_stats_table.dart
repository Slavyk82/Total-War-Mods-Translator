import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../providers/statistics_providers.dart';

/// Table displaying per-project statistics
class ProjectStatsTable extends StatefulWidget {
  final List<ProjectStats> projects;

  const ProjectStatsTable({
    super.key,
    required this.projects,
  });

  @override
  State<ProjectStatsTable> createState() => _ProjectStatsTableState();
}

class _ProjectStatsTableState extends State<ProjectStatsTable> {
  int _sortColumnIndex = 0;
  bool _sortAscending = true;
  List<ProjectStats> _sortedProjects = [];

  @override
  void initState() {
    super.initState();
    _sortedProjects = List.from(widget.projects);
    _sortProjects();
  }

  @override
  void didUpdateWidget(ProjectStatsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.projects != oldWidget.projects) {
      _sortedProjects = List.from(widget.projects);
      _sortProjects();
    }
  }

  void _sortProjects() {
    _sortedProjects.sort((a, b) {
      int comparison = 0;
      switch (_sortColumnIndex) {
        case 0:
          comparison = a.projectName.compareTo(b.projectName);
          break;
        case 1:
          comparison = a.totalUnits.compareTo(b.totalUnits);
          break;
        case 2:
          comparison = a.translatedUnits.compareTo(b.translatedUnits);
          break;
        case 3:
          comparison = a.progressPercentage.compareTo(b.progressPercentage);
          break;
        case 4:
          comparison = a.tmReuseRate.compareTo(b.tmReuseRate);
          break;
        case 5:
          comparison = a.provider.compareTo(b.provider);
          break;
      }
      return _sortAscending ? comparison : -comparison;
    });
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      _sortProjects();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_sortedProjects.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Center(
          child: Text(
            'No projects available',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Project Statistics',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Detailed breakdown by project',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              sortColumnIndex: _sortColumnIndex,
              sortAscending: _sortAscending,
              headingRowColor: WidgetStateProperty.all(
                theme.colorScheme.surfaceContainerHigh,
              ),
              dividerThickness: 0,
              columns: [
                _buildDataColumn('Project', 0),
                _buildDataColumn('Units', 1, numeric: true),
                _buildDataColumn('Translated', 2, numeric: true),
                _buildDataColumn('Progress', 3, numeric: true),
                _buildDataColumn('TM Reuse', 4, numeric: true),
                _buildDataColumn('Provider', 5),
              ],
              rows: _sortedProjects.map((project) {
                return DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 200,
                        child: Text(
                          project.projectName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onTap: () => _navigateToProject(context, project),
                    ),
                    DataCell(
                      Text(project.totalUnits.toString()),
                      onTap: () => _navigateToProject(context, project),
                    ),
                    DataCell(
                      Text(project.translatedUnits.toString()),
                      onTap: () => _navigateToProject(context, project),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 80,
                            child: LinearProgressIndicator(
                              value: project.progressPercentage / 100,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _getProgressColor(
                                    project.progressPercentage, theme),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                              '${project.progressPercentage.toStringAsFixed(0)}%'),
                        ],
                      ),
                      onTap: () => _navigateToProject(context, project),
                    ),
                    DataCell(
                      Text('${project.tmReuseRate.toStringAsFixed(1)}%'),
                      onTap: () => _navigateToProject(context, project),
                    ),
                    DataCell(
                      Text(project.provider),
                      onTap: () => _navigateToProject(context, project),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  DataColumn _buildDataColumn(String label, int index,
      {bool numeric = false}) {
    return DataColumn(
      label: Text(label),
      onSort: _onSort,
      numeric: numeric,
    );
  }

  Color _getProgressColor(double percentage, ThemeData theme) {
    if (percentage >= 80) {
      return Colors.green;
    } else if (percentage >= 50) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  void _navigateToProject(BuildContext context, ProjectStats project) {
    context.go('/projects/${project.projectId}');
  }
}
