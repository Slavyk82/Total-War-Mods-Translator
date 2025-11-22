import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import 'package:twmt/widgets/common/fluent_spinner.dart';
import '../providers/glossary_providers.dart';
import '../widgets/glossary_selector.dart';
import '../widgets/glossary_datagrid.dart';
import '../widgets/glossary_statistics_panel.dart';
import '../widgets/glossary_entry_editor.dart';
import '../widgets/glossary_import_dialog.dart';
import '../widgets/glossary_export_dialog.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/glossary/i_glossary_service.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Main screen for Glossary management
class GlossaryScreen extends ConsumerStatefulWidget {
  const GlossaryScreen({super.key});

  @override
  ConsumerState<GlossaryScreen> createState() => _GlossaryScreenState();
}

class _GlossaryScreenState extends ConsumerState<GlossaryScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedGlossary = ref.watch(selectedGlossaryProvider);

    return FluentScaffold(
      body: Column(
        children: [
          // Header
          _buildHeader(context),

          const Divider(height: 1),

          // Glossary selector
          _buildGlossarySelector(context, selectedGlossary),

          const Divider(height: 1),

          // Main content
          Expanded(
            child: selectedGlossary == null
                ? _buildEmptyState(context)
                : Row(
                    children: [
                      // Statistics panel (left sidebar) with fixed width
                      SizedBox(
                        width: 280,
                        child: GlossaryStatisticsPanel(
                          glossaryId: selectedGlossary.id,
                        ),
                      ),

                      const VerticalDivider(width: 1),

                      // Main content area
                      Expanded(
                        child: Column(
                          children: [
                            // Toolbar
                            _buildToolbar(context, selectedGlossary),

                            const Divider(height: 1),

                            // DataGrid
                            Expanded(
                              child: GlossaryDataGrid(
                                glossaryId: selectedGlossary.id,
                              ),
                            ),

                            const Divider(height: 1),

                            // Footer info
                            _buildFooter(context, selectedGlossary),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          Icon(
            FluentIcons.book_24_regular,
            size: 32,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Text(
            'Glossary Management',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const Spacer(),
          // Action buttons
          _buildActionButton(
            context,
            icon: FluentIcons.add_24_regular,
            label: 'New',
            onPressed: () => _showNewGlossaryDialog(),
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            context,
            icon: FluentIcons.arrow_import_24_regular,
            label: 'Import',
            onPressed: () => _showImportDialog(),
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            context,
            icon: FluentIcons.arrow_export_24_regular,
            label: 'Export',
            onPressed: () => _showExportDialog(),
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            context,
            icon: FluentIcons.delete_24_regular,
            label: 'Delete',
            onPressed:
                ref.watch(selectedGlossaryProvider) != null ? _deleteGlossary : null,
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _buildGlossarySelector(BuildContext context, Glossary? selectedGlossary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Row(
        children: [
          Text(
            'Glossary:',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GlossarySelector(
              selectedGlossary: selectedGlossary,
              onGlossarySelected: (glossary) {
                ref.read(selectedGlossaryProvider.notifier).select(glossary);
              },
              onCreateNew: () => _showNewGlossaryDialog(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, Glossary glossary) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          // Search bar
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search entries...',
                prefixIcon: const Icon(FluentIcons.search_24_regular),
                suffixIcon: _searchController.text.isNotEmpty
                    ? MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            ref.read(glossaryFilterStateProvider.notifier).setSearchText('');
                          },
                          child: const Icon(FluentIcons.dismiss_24_regular),
                        ),
                      )
                    : null,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
              ),
              onChanged: (value) {
                ref.read(glossaryFilterStateProvider.notifier).setSearchText(value);
              },
            ),
          ),
          const SizedBox(width: 16),

          // Add Entry button
          _buildActionButton(
            context,
            icon: FluentIcons.add_24_regular,
            label: 'Add Entry',
            onPressed: () => _showEntryEditor(null, glossary),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, Glossary glossary) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Text(
            'Glossary: ${glossary.name}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(width: 16),
          Text(
            '${glossary.entryCount} entries',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const Spacer(),
          Text(
            glossary.isGlobal ? 'Global Glossary' : 'Project Glossary',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: glossary.isGlobal
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.secondary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.book_24_regular,
            size: 64,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No glossary selected',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a glossary from the dropdown or create a new one',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
          ),
          const SizedBox(height: 24),
          _buildActionButton(
            context,
            icon: FluentIcons.add_24_regular,
            label: 'Create New Glossary',
            onPressed: () => _showNewGlossaryDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool isDestructive = false,
  }) {
    final isEnabled = onPressed != null;
    final bgColor = isDestructive
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    final fgColor = isDestructive
        ? Theme.of(context).colorScheme.onError
        : Theme.of(context).colorScheme.onPrimary;

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: AnimatedOpacity(
        opacity: isEnabled ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 150),
        child: GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: fgColor),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: fgColor,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showNewGlossaryDialog() {
    showDialog(
      context: context,
      builder: (context) => _NewGlossaryDialog(),
    );
  }

  void _showEntryEditor(dynamic entry, Glossary glossary) {
    showDialog(
      context: context,
      builder: (context) => GlossaryEntryEditorDialog(
        glossaryId: glossary.id,
        entry: entry,
      ),
    );
  }

  void _showImportDialog() {
    final selectedGlossary = ref.read(selectedGlossaryProvider);
    if (selectedGlossary == null) return;

    showDialog(
      context: context,
      builder: (context) => GlossaryImportDialog(
        glossaryId: selectedGlossary.id,
      ),
    );
  }

  void _showExportDialog() {
    final selectedGlossary = ref.read(selectedGlossaryProvider);
    if (selectedGlossary == null) return;

    showDialog(
      context: context,
      builder: (context) => GlossaryExportDialog(
        glossaryId: selectedGlossary.id,
      ),
    );
  }

  Future<void> _deleteGlossary() async {
    final selectedGlossary = ref.read(selectedGlossaryProvider);
    if (selectedGlossary == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Glossary'),
        content: Text(
          'Are you sure you want to delete "${selectedGlossary.name}"? '
          'This will permanently delete all ${selectedGlossary.entryCount} entries.',
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(true),
            foregroundColor: Theme.of(context).colorScheme.error,
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final service = ServiceLocator.get<IGlossaryService>();
        await service.deleteGlossary(selectedGlossary.id);

        // Clear selection and refresh
        ref.read(selectedGlossaryProvider.notifier).clear();
        ref.invalidate(glossariesProvider);

        if (mounted) {
          FluentToast.success(
            context,
            'Glossary "${selectedGlossary.name}" deleted successfully',
          );
        }
      } catch (e) {
        if (mounted) {
          FluentToast.error(context, 'Error deleting glossary: $e');
        }
      }
    }
  }
}

/// Dialog for creating a new glossary
class _NewGlossaryDialog extends ConsumerStatefulWidget {
  @override
  ConsumerState<_NewGlossaryDialog> createState() => _NewGlossaryDialogState();
}

class _NewGlossaryDialogState extends ConsumerState<_NewGlossaryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isGlobal = true;
  String? _projectId;
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Glossary'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Name is required';
                    }
                    if (value.trim().length > 100) {
                      return 'Name must be 100 characters or less';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Description
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  maxLength: 300,
                ),
                const SizedBox(height: 16),

                // Type
                Text(
                  'Type *',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Column(
                  children: [
                    // ignore: deprecated_member_use
                    RadioListTile<bool>(
                      value: true,
                      // ignore: deprecated_member_use
                      groupValue: _isGlobal,
                      // ignore: deprecated_member_use
                      onChanged: (value) {
                        setState(() {
                          _isGlobal = value ?? true;
                        });
                      },
                      title: const Text('Global glossary (shared across all projects)'),
                    ),
                    // ignore: deprecated_member_use
                    RadioListTile<bool>(
                      value: false,
                      // ignore: deprecated_member_use
                      groupValue: _isGlobal,
                      // ignore: deprecated_member_use
                      onChanged: (value) {
                        setState(() {
                          _isGlobal = value ?? false;
                        });
                      },
                      title: const Text('Project glossary (specific to one project)'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        FluentTextButton(
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FluentTextButton(
          onPressed: _isCreating ? null : _createGlossary,
          child: _isCreating
              ? const FluentInlineSpinner(size: 16)
              : const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _createGlossary() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isCreating = true;
    });

    try {
      final service = ServiceLocator.get<IGlossaryService>();
      final result = await service.createGlossary(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        isGlobal: _isGlobal,
        projectId: _projectId,
      );

      result.when(
        ok: (glossary) {
          // Select the new glossary
          ref.read(selectedGlossaryProvider.notifier).select(glossary);
          // Refresh glossaries list
          ref.invalidate(glossariesProvider);

          if (mounted) {
            Navigator.of(context).pop();
            FluentToast.success(
              context,
              'Glossary "${glossary.name}" created successfully',
            );
          }
        },
        err: (error) {
          if (mounted) {
            FluentToast.error(context, 'Error creating glossary: $error');
          }
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }
}
