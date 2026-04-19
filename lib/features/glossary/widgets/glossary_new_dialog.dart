import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:uuid/uuid.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/common/fluent_spinner.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart'
    hide settingsServiceProvider;
import 'package:twmt/providers/selected_game_provider.dart';
import '../../../providers/shared/repository_providers.dart';
import '../../../providers/shared/service_providers.dart';
import '../providers/glossary_providers.dart';

/// Token-themed popup for creating a new glossary.
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
    final languageRepository = ref.read(languageRepositoryProvider);
    final settingsService = ref.read(settingsServiceProvider);

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
    final repository = ref.read(gameInstallationRepositoryProvider);

    final existingResult = await repository.getByGameCode(gameCode);
    if (existingResult.isOk) {
      return existingResult.value.id;
    }

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
    final tokens = context.tokens;

    return TokenDialog(
      icon: FluentIcons.book_add_24_regular,
      title: 'Create New Glossary',
      width: 540,
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.text,
                ),
                decoration: _tokenInputDecoration(tokens, 'Name *'),
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
              const SizedBox(height: 14),
              TextFormField(
                controller: _descriptionController,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.text,
                ),
                decoration: _tokenInputDecoration(tokens, 'Description'),
                maxLines: 3,
                maxLength: 300,
              ),
              const SizedBox(height: 14),
              _sectionLabel(tokens, 'Scope *'),
              const SizedBox(height: 6),
              _ScopeRadio(
                value: true,
                groupValue: _isUniversal,
                label: 'Universal (all games)',
                subtitle: 'Shared across all projects of all games',
                onChanged: (v) {
                  setState(() {
                    _isUniversal = v;
                    if (_isUniversal) _selectedGameCode = null;
                  });
                },
              ),
              _ScopeRadio(
                value: false,
                groupValue: _isUniversal,
                label: 'Game-specific',
                subtitle: 'Shared across all projects of one game',
                onChanged: (v) => setState(() => _isUniversal = v),
              ),
              if (!_isUniversal) ...[
                const SizedBox(height: 14),
                _sectionLabel(tokens, 'Game *'),
                const SizedBox(height: 6),
                _buildGameSelector(tokens),
              ],
              const SizedBox(height: 14),
              _sectionLabel(tokens, 'Target Language *'),
              const SizedBox(height: 6),
              _buildLanguageSelector(tokens),
            ],
          ),
        ),
      ),
      actions: [
        SmallTextButton(
          label: 'Cancel',
          onTap: _isCreating ? null : () => Navigator.of(context).pop(),
        ),
        SmallTextButton(
          label: _isCreating ? 'Creating...' : 'Create',
          icon: FluentIcons.add_24_regular,
          filled: true,
          onTap: _isCreating ? null : _createGlossary,
        ),
      ],
    );
  }

  Widget _sectionLabel(TwmtThemeTokens tokens, String text) {
    return Text(
      text,
      style: tokens.fontBody.copyWith(
        fontSize: 13,
        color: tokens.text,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration _tokenInputDecoration(
    TwmtThemeTokens tokens,
    String labelText,
  ) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: tokens.fontBody.copyWith(
        fontSize: 12,
        color: tokens.textDim,
      ),
      floatingLabelStyle: tokens.fontBody.copyWith(
        fontSize: 12,
        color: tokens.accent,
      ),
      filled: true,
      fillColor: tokens.panel2,
      isDense: true,
      counterStyle: tokens.fontBody.copyWith(
        fontSize: 11,
        color: tokens.textFaint,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.err),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.err),
      ),
      errorStyle: tokens.fontBody.copyWith(
        fontSize: 11.5,
        color: tokens.err,
      ),
    );
  }

  Widget _buildLanguageSelector(TwmtThemeTokens tokens) {
    final repository = ref.watch(languageRepositoryProvider);
    return FutureBuilder(
      future: repository.getActive(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const FluentInlineSpinner();
        }

        return snapshot.data?.when(
              ok: (languages) {
                if (languages.isEmpty) {
                  return Text(
                    'No active languages available',
                    style: tokens.fontBody.copyWith(
                      fontSize: 12.5,
                      color: tokens.textDim,
                    ),
                  );
                }

                return DropdownButtonFormField<String>(
                  initialValue: _selectedLanguageId,
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: tokens.text,
                  ),
                  dropdownColor: tokens.panel,
                  decoration: _tokenInputDecoration(
                    tokens,
                    'Target language',
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
              err: (_) => Text(
                'Error loading languages',
                style: tokens.fontBody.copyWith(
                  fontSize: 12.5,
                  color: tokens.err,
                ),
              ),
            ) ??
            Text(
              'Error loading languages',
              style: tokens.fontBody.copyWith(
                fontSize: 12.5,
                color: tokens.err,
              ),
            );
      },
    );
  }

  Widget _buildGameSelector(TwmtThemeTokens tokens) {
    final configuredGamesAsync = ref.watch(configuredGamesProvider);

    return configuredGamesAsync.when(
      loading: () => const FluentInlineSpinner(),
      error: (_, _) => Text(
        'Error loading games',
        style: tokens.fontBody.copyWith(
          fontSize: 12.5,
          color: tokens.err,
        ),
      ),
      data: (games) {
        if (games.isEmpty) {
          return Text(
            'No games configured. Add a game in Settings first.',
            style: tokens.fontBody.copyWith(
              fontSize: 12.5,
              color: tokens.textDim,
            ),
          );
        }

        return DropdownButtonFormField<String>(
          initialValue: _selectedGameCode,
          style: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.text,
          ),
          dropdownColor: tokens.panel,
          decoration: _tokenInputDecoration(tokens, 'Game'),
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
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    try {
      final service = ref.read(glossaryServiceProvider);

      if (_selectedLanguageId == null) {
        if (mounted) {
          FluentToast.error(context, 'Please select a target language');
        }
        return;
      }

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
            ref.read(selectedGlossaryProvider.notifier).select(glossary);
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
        setState(() => _isCreating = false);
      }
    }
  }
}

class _ScopeRadio extends StatelessWidget {
  final bool value;
  final bool groupValue;
  final String label;
  final String subtitle;
  final ValueChanged<bool> onChanged;

  const _ScopeRadio({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.subtitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final selected = value == groupValue;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? FluentIcons.radio_button_24_filled
                    : FluentIcons.radio_button_24_regular,
                size: 18,
                color: selected ? tokens.accent : tokens.textFaint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: tokens.fontBody.copyWith(
                        fontSize: 13,
                        color: tokens.text,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: tokens.fontBody.copyWith(
                        fontSize: 11.5,
                        color: tokens.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
