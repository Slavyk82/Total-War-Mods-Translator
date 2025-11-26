import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:uuid/uuid.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import 'package:twmt/widgets/common/fluent_spinner.dart';
import '../providers/glossary_providers.dart';
import '../widgets/glossary_list.dart';
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
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';
import 'package:twmt/providers/selected_game_provider.dart';

/// Main screen for Glossary management
class GlossaryScreen extends ConsumerStatefulWidget {
  const GlossaryScreen({super.key});

  @override
  ConsumerState<GlossaryScreen> createState() => _GlossaryScreenState();
}

class _GlossaryScreenState extends ConsumerState<GlossaryScreen> {
  final _searchController = TextEditingController();
  Map<String, GameInstallation> _gameInstallations = {};

  @override
  void initState() {
    super.initState();
    _loadGameInstallations();
  }

  Future<void> _loadGameInstallations() async {
    final repository = ServiceLocator.get<GameInstallationRepository>();
    final result = await repository.getAll();
    result.when(
      ok: (games) {
        if (mounted) {
          setState(() {
            _gameInstallations = {for (var g in games) g.id: g};
          });
        }
      },
      err: (_) {},
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedGlossary = ref.watch(selectedGlossaryProvider);

    return FluentScaffold(
      body: selectedGlossary == null
          ? _buildGlossaryListView(context)
          : _buildGlossaryEditorView(context, selectedGlossary),
    );
  }

  /// Build the glossary list view (shown when no glossary selected)
  Widget _buildGlossaryListView(BuildContext context) {
    final glossariesAsync = ref.watch(glossariesProvider());

    return Column(
      children: [
        // Header
        _buildListHeader(context),

        const Divider(height: 1),

        // Glossary cards list
        Expanded(
          child: glossariesAsync.when(
            data: (glossaries) {
              if (glossaries.isEmpty) {
                return _buildEmptyState(context);
              }
              return GlossaryList(
                glossaries: glossaries,
                gameInstallations: _gameInstallations,
                onGlossaryTap: (glossary) {
                  ref.read(selectedGlossaryProvider.notifier).select(glossary);
                },
                onDeleteGlossary: (glossary) => _confirmDeleteGlossary(glossary),
              );
            },
            loading: () => const Center(child: FluentInlineSpinner()),
            error: (error, stack) => Center(
              child: Text(
                'Error loading glossaries: $error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Build the glossary editor view (shown when a glossary is selected)
  Widget _buildGlossaryEditorView(BuildContext context, Glossary glossary) {
    return Column(
      children: [
        // Header with back button
        _buildEditorHeader(context, glossary),

        const Divider(height: 1),

        // Main content
        Expanded(
          child: Row(
            children: [
              // Statistics panel (left sidebar) with fixed width
              SizedBox(
                width: 280,
                child: GlossaryStatisticsPanel(
                  glossaryId: glossary.id,
                ),
              ),

              const VerticalDivider(width: 1),

              // Main content area
              Expanded(
                child: Column(
                  children: [
                    // Toolbar
                    _buildToolbar(context, glossary),

                    const Divider(height: 1),

                    // DataGrid
                    Expanded(
                      child: GlossaryDataGrid(
                        glossaryId: glossary.id,
                      ),
                    ),

                    const Divider(height: 1),

                    // Footer info
                    _buildFooter(context, glossary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Header for the glossary list view
  Widget _buildListHeader(BuildContext context) {
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
          // Create new glossary button
          _buildActionButton(
            context,
            icon: FluentIcons.add_24_regular,
            label: 'New Glossary',
            onPressed: () => _showNewGlossaryDialog(),
          ),
        ],
      ),
    );
  }

  /// Header for the glossary editor view (with back button)
  Widget _buildEditorHeader(BuildContext context, Glossary glossary) {
    final isUniversal = glossary.isGlobal;
    final gameName = glossary.gameInstallationId != null
        ? _gameInstallations[glossary.gameInstallationId]?.gameName
        : null;
    final typeLabel = isUniversal
        ? 'Universal Glossary'
        : gameName != null
            ? 'Game: $gameName'
            : 'Game-specific Glossary';

    return Container(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          // Back button
          _buildBackButton(context),
          const SizedBox(width: 16),
          // Glossary icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isUniversal
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isUniversal
                  ? FluentIcons.globe_24_regular
                  : FluentIcons.games_24_regular,
              size: 20,
              color: isUniversal
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          // Glossary name and type
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  glossary.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  typeLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isUniversal
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.secondary,
                      ),
                ),
              ],
            ),
          ),
          // Action buttons
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
            onPressed: () => _confirmDeleteGlossary(glossary),
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _buildBackButton(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          ref.read(selectedGlossaryProvider.notifier).clear();
        },
        child: Tooltip(
          message: 'Back to Glossary List',
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              FluentIcons.arrow_left_24_regular,
              size: 20,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
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
    final isUniversal = glossary.isGlobal;
    final gameName = glossary.gameInstallationId != null
        ? _gameInstallations[glossary.gameInstallationId]?.gameName
        : null;
    final typeLabel = isUniversal
        ? 'Universal Glossary'
        : gameName != null
            ? gameName
            : 'Game-specific';

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
            typeLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isUniversal
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
            'No glossaries yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a glossary to manage your translation terminology',
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

  /// Show confirmation dialog and delete glossary
  Future<void> _confirmDeleteGlossary(Glossary glossary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Glossary'),
        content: Text(
          'Are you sure you want to delete "${glossary.name}"? '
          'This will permanently delete all ${glossary.entryCount} entries.',
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
        await service.deleteGlossary(glossary.id);

        if (mounted) {
          // Clear selection if this was the selected glossary
          final selected = ref.read(selectedGlossaryProvider);
          if (selected?.id == glossary.id) {
            ref.read(selectedGlossaryProvider.notifier).clear();
          }
          // Refresh glossaries list
          ref.invalidate(glossariesProvider);

          FluentToast.success(
            context,
            'Glossary "${glossary.name}" deleted successfully',
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
  bool _isUniversal = true;
  String? _selectedGameCode;
  String? _selectedLanguageId;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadDefaultLanguage();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadDefaultLanguage() async {
    final languageRepository = ServiceLocator.get<LanguageRepository>();
    final settingsService = ServiceLocator.get<SettingsService>();
    
    final defaultLanguageCode = await settingsService.getString(
      SettingsKeys.defaultTargetLanguage,
      defaultValue: SettingsKeys.defaultTargetLanguageValue,
    );
    
    final langResult = await languageRepository.getActive();
    langResult.when(
      ok: (languages) {
        if (mounted && languages.isNotEmpty) {
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

  /// Get or create GameInstallation for the given game code
  Future<String?> _getOrCreateGameInstallationId(String gameCode, String gameName, String gamePath) async {
    final repository = ServiceLocator.get<GameInstallationRepository>();
    
    // Try to find existing
    final existingResult = await repository.getByGameCode(gameCode);
    if (existingResult.isOk) {
      return existingResult.value.id;
    }
    
    // Create new GameInstallation
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final newInstallation = GameInstallation(
      id: const Uuid().v4(),
      gameCode: gameCode,
      gameName: gameName,
      installationPath: gamePath,
      isAutoDetected: false,
      isValid: true,
      createdAt: now,
      updatedAt: now,
    );
    
    final insertResult = await repository.insert(newInstallation);
    if (insertResult.isOk) {
      return insertResult.value.id;
    }
    
    return null;
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
              value: _selectedLanguageId,
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

  Widget _buildGameSelector() {
    final configuredGamesAsync = ref.watch(configuredGamesProvider);

    return configuredGamesAsync.when(
      loading: () => const FluentInlineSpinner(),
      error: (_, __) => const Text('Error loading games'),
      data: (games) {
        if (games.isEmpty) {
          return const Text('No games configured. Add a game in Settings first.');
        }

        return DropdownButtonFormField<String>(
          value: _selectedGameCode,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Select game',
          ),
          items: games.map((game) {
            return DropdownMenuItem<String>(
              value: game.code,
              child: Text(game.name),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedGameCode = value;
            });
          },
          validator: (value) {
            if (!_isUniversal && (value == null || value.isEmpty)) {
              return 'Game selection is required';
            }
            return null;
          },
        );
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

                // Scope
                Text(
                  'Scope *',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Column(
                  children: [
                    // ignore: deprecated_member_use
                    RadioListTile<bool>(
                      value: true,
                      // ignore: deprecated_member_use
                      groupValue: _isUniversal,
                      // ignore: deprecated_member_use
                      onChanged: (value) {
                        setState(() {
                          _isUniversal = value ?? true;
                          if (_isUniversal) {
                            _selectedGameCode = null;
                          }
                        });
                      },
                      title: const Text('Universal (all games)'),
                      subtitle: const Text('Shared across all projects of all games'),
                    ),
                    // ignore: deprecated_member_use
                    RadioListTile<bool>(
                      value: false,
                      // ignore: deprecated_member_use
                      groupValue: _isUniversal,
                      // ignore: deprecated_member_use
                      onChanged: (value) {
                        setState(() {
                          _isUniversal = value ?? false;
                        });
                      },
                      title: const Text('Game-specific'),
                      subtitle: const Text('Shared across all projects of one game'),
                    ),
                  ],
                ),

                // Game selector (only visible when game-specific)
                if (!_isUniversal) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Game *',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _buildGameSelector(),
                ],

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

      // Get or create GameInstallation for game-specific glossary
      String? gameInstallationId;
      if (!_isUniversal && _selectedGameCode != null) {
        final configuredGames = await ref.read(configuredGamesProvider.future);
        final selectedGame = configuredGames.firstWhere(
          (g) => g.code == _selectedGameCode,
        );
        gameInstallationId = await _getOrCreateGameInstallationId(
          selectedGame.code,
          selectedGame.name,
          selectedGame.path,
        );
        
        if (gameInstallationId == null) {
          if (mounted) {
            FluentToast.error(context, 'Failed to create game installation record');
          }
          return;
        }
      }

      print('[NewGlossaryDialog] Calling service.createGlossary with:');
      print('  name: ${_nameController.text.trim()}');
      print('  description: ${_descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null}');
      print('  isUniversal: $_isUniversal');
      print('  gameInstallationId: $gameInstallationId');
      print('  targetLanguageId: $_selectedLanguageId');
      
      final result = await service.createGlossary(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        isGlobal: _isUniversal,
        gameInstallationId: gameInstallationId,
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
