import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:twmt/widgets/common/fluent_spinner.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/services/glossary/i_glossary_service.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import '../providers/glossary_providers.dart';

/// Dialog for creating a new glossary.
class NewGlossaryDialog extends ConsumerStatefulWidget {
  const NewGlossaryDialog({super.key});

  @override
  ConsumerState<NewGlossaryDialog> createState() => _NewGlossaryDialogState();
}

class _NewGlossaryDialogState extends ConsumerState<NewGlossaryDialog> {
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

  Future<String?> _getOrCreateGameInstallationId(
    String gameCode,
    String gameName,
    String gamePath,
  ) async {
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
                _buildScopeRadioButtons(),

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

  Widget _buildScopeRadioButtons() {
    return RadioGroup<bool>(
      groupValue: _isUniversal,
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _isUniversal = value;
            if (_isUniversal) {
              _selectedGameCode = null;
            }
          });
        }
      },
      child: Column(
        children: [
          ListTile(
            leading: Radio<bool>(
              value: true,
              toggleable: false,
            ),
            title: const Text('Universal (all games)'),
            subtitle: const Text('Shared across all projects of all games'),
            onTap: () {
              setState(() {
                _isUniversal = true;
                _selectedGameCode = null;
              });
            },
          ),
          ListTile(
            leading: Radio<bool>(
              value: false,
              toggleable: false,
            ),
            title: const Text('Game-specific'),
            subtitle: const Text('Shared across all projects of one game'),
            onTap: () {
              setState(() {
                _isUniversal = false;
              });
            },
          ),
        ],
      ),
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
            ) ??
            const Text('Error loading languages');
      },
    );
  }

  Widget _buildGameSelector() {
    final configuredGamesAsync = ref.watch(configuredGamesProvider);

    return configuredGamesAsync.when(
      loading: () => const FluentInlineSpinner(),
      error: (_, _) => const Text('Error loading games'),
      data: (games) {
        if (games.isEmpty) {
          return const Text(
              'No games configured. Add a game in Settings first.');
        }

        return DropdownButtonFormField<String>(
          initialValue: _selectedGameCode,
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

  Future<void> _createGlossary() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final service = ServiceLocator.get<IGlossaryService>();

      if (_selectedLanguageId == null) {
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
            FluentToast.error(
                context, 'Failed to create game installation record');
          }
          return;
        }
      }

      final result = await service.createGlossary(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        isGlobal: _isUniversal,
        gameInstallationId: gameInstallationId,
        targetLanguageId: _selectedLanguageId!,
      );

      result.when(
        ok: (glossary) {
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
          if (mounted) {
            FluentToast.error(context, 'Error creating glossary: $error');
          }
        },
      );
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, 'Unexpected error: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }
}
