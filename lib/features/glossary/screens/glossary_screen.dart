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
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';

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

  void _showEntryEditor(dynamic entry, Glossary glossary) async {
    print('[GlossaryScreen._showEntryEditor] Opening entry editor');
    print('  glossaryId: ${glossary.id}');
    print('  glossary.targetLanguageId: ${glossary.targetLanguageId}');
    print('  entry: ${entry != null ? "EDIT ${entry.id}" : "NEW"}');
    
    // Get target language code from glossary's target language ID
    String? targetLanguageCode;
    if (glossary.targetLanguageId != null) {
      try {
        final languageRepo = ServiceLocator.get<LanguageRepository>();
        final langResult = await languageRepo.getById(glossary.targetLanguageId!);
        langResult.when(
          ok: (language) {
            targetLanguageCode = language.code;
            print('[GlossaryScreen._showEntryEditor] Target language code: $targetLanguageCode');
          },
          err: (error) {
            print('[GlossaryScreen._showEntryEditor] ERROR getting language: $error');
          },
        );
      } catch (e) {
        print('[GlossaryScreen._showEntryEditor] Exception getting language: $e');
      }
    }
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => GlossaryEntryEditorDialog(
        glossaryId: glossary.id,
        targetLanguageCode: targetLanguageCode,
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

        if (mounted) {
          // Clear selection and refresh
          ref.read(selectedGlossaryProvider.notifier).clear();
          ref.invalidate(glossariesProvider);

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
  String? _selectedLanguageId;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadLanguages();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadLanguages() async {
    final repository = ServiceLocator.get<LanguageRepository>();
    final settingsService = ServiceLocator.get<SettingsService>();
    
    // Get the default target language from settings
    final defaultLanguageCode = await settingsService.getString(
      SettingsKeys.defaultTargetLanguage,
      defaultValue: 'fr',
    );
    
    final result = await repository.getActive();
    result.when(
      ok: (languages) {
        if (mounted && languages.isNotEmpty) {
          // Find language matching the default code, or fallback to first
          final defaultLang = languages.firstWhere(
            (lang) => lang.code == defaultLanguageCode,
            orElse: () => languages.first,
          );
          setState(() {
            _selectedLanguageId = defaultLang.id;
          });
        }
      },
      err: (_) {},
    );
  }

  Widget _buildLanguageSelector() {
    final repository = ServiceLocator.get<LanguageRepository>();
    return FutureBuilder(
      future: repository.getActive(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const FluentInlineSpinner();
        }

        return snapshot.data?.when(
          ok: (languages) {
            if (languages.isEmpty) {
              return const Text('No active languages available');
            }

            return DropdownButtonFormField<String>(
              initialValue: _selectedLanguageId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Select target language',
              ),
              items: languages.map((lang) {
                return DropdownMenuItem<String>(
                  value: lang.id,
                  child: Text(lang.displayName),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedLanguageId = value;
                });
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Target language is required';
                }
                return null;
              },
            );
          },
          err: (_) => const Text('Error loading languages'),
        ) ?? const Text('Error loading languages');
      },
    );
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
                const SizedBox(height: 16),

                // Target Language
                Text(
                  'Target Language *',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _buildLanguageSelector(),
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
    print('[NewGlossaryDialog] Starting glossary creation...');
    print('[NewGlossaryDialog] Form validation: ${_formKey.currentState!.validate()}');
    
    if (!_formKey.currentState!.validate()) {
      print('[NewGlossaryDialog] Form validation failed');
      return;
    }

    print('[NewGlossaryDialog] Setting isCreating to true');
    setState(() {
      _isCreating = true;
    });

    try {
      print('[NewGlossaryDialog] Getting service...');
      final service = ServiceLocator.get<IGlossaryService>();
      
      if (_selectedLanguageId == null) {
        print('[NewGlossaryDialog] No language selected');
        if (mounted) {
          FluentToast.error(context, 'Please select a target language');
        }
        return;
      }

      print('[NewGlossaryDialog] Calling service.createGlossary with:');
      print('  name: ${_nameController.text.trim()}');
      print('  description: ${_descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null}');
      print('  isGlobal: $_isGlobal');
      print('  projectId: $_projectId');
      print('  targetLanguageId: $_selectedLanguageId');
      
      final result = await service.createGlossary(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        isGlobal: _isGlobal,
        projectId: _projectId,
        targetLanguageId: _selectedLanguageId!,
      );

      print('[NewGlossaryDialog] Service returned result');
      
      result.when(
        ok: (glossary) {
          print('[NewGlossaryDialog] SUCCESS: Glossary created: ${glossary.id}');
          
          if (mounted) {
            // Select the new glossary
            ref.read(selectedGlossaryProvider.notifier).select(glossary);
            // Refresh glossaries list
            ref.invalidate(glossariesProvider);

            Navigator.of(context).pop();
            FluentToast.success(
              context,
              'Glossary "${glossary.name}" created successfully',
            );
          }
        },
        err: (error) {
          print('[NewGlossaryDialog] ERROR: $error');
          if (mounted) {
            FluentToast.error(context, 'Error creating glossary: $error');
          }
        },
      );
    } catch (e, stackTrace) {
      print('[NewGlossaryDialog] EXCEPTION caught: $e');
      print('[NewGlossaryDialog] Stack trace: $stackTrace');
      if (mounted) {
        FluentToast.error(context, 'Unexpected error: $e');
      }
    } finally {
      print('[NewGlossaryDialog] Finally block - resetting isCreating');
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }
}
