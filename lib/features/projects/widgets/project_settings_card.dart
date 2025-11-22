import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../models/domain/project.dart';

/// Card displaying and allowing editing of project translation settings.
///
/// Shows batch size, parallel batches, and custom prompt with inline editing.
class ProjectSettingsCard extends StatefulWidget {
  final Project project;
  final Function(int batchSize, int parallelBatches, String? customPrompt)?
      onSave;

  const ProjectSettingsCard({
    super.key,
    required this.project,
    this.onSave,
  });

  @override
  State<ProjectSettingsCard> createState() => _ProjectSettingsCardState();
}

class _ProjectSettingsCardState extends State<ProjectSettingsCard> {
  late final TextEditingController _batchSizeController;
  late final TextEditingController _parallelBatchesController;
  late final TextEditingController _customPromptController;
  final _formKey = GlobalKey<FormState>();

  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _batchSizeController =
        TextEditingController(text: widget.project.batchSize.toString());
    _parallelBatchesController =
        TextEditingController(text: widget.project.parallelBatches.toString());
    _customPromptController =
        TextEditingController(text: widget.project.customPrompt ?? '');
  }

  @override
  void dispose() {
    _batchSizeController.dispose();
    _parallelBatchesController.dispose();
    _customPromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  FluentIcons.settings_24_regular,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Translation Settings',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (!_isEditing)
                  _buildEditButton(theme)
                else ...[
                  _buildCancelButton(theme),
                  const SizedBox(width: 8),
                  _buildSaveButton(theme),
                ],
              ],
            ),
            const SizedBox(height: 20),

            // Batch size
            _buildSettingField(
              theme: theme,
              label: 'Batch Size',
              description: 'Number of translation units per batch',
              controller: _batchSizeController,
              enabled: _isEditing,
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Batch size is required';
                }
                final intValue = int.tryParse(value);
                if (intValue == null || intValue < 1 || intValue > 100) {
                  return 'Batch size must be between 1 and 100';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Parallel batches
            _buildSettingField(
              theme: theme,
              label: 'Parallel Batches',
              description: 'Number of batches to process in parallel',
              controller: _parallelBatchesController,
              enabled: _isEditing,
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Parallel batches is required';
                }
                final intValue = int.tryParse(value);
                if (intValue == null || intValue < 1 || intValue > 10) {
                  return 'Parallel batches must be between 1 and 10';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Custom prompt
            _buildPromptField(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingField({
    required ThemeData theme,
    required String label,
    required String description,
    required TextEditingController controller,
    required bool enabled,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          inputFormatters: keyboardType == TextInputType.number
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.1),
              ),
            ),
            filled: !enabled,
            fillColor: enabled
                ? null
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildPromptField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Custom Translation Prompt',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Optional custom instructions for the AI translator',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _customPromptController,
          enabled: _isEditing,
          maxLines: 4,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.1),
              ),
            ),
            filled: !_isEditing,
            fillColor: _isEditing
                ? null
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
            hintText: 'Enter custom translation instructions...',
          ),
        ),
      ],
    );
  }

  Widget _buildEditButton(ThemeData theme) {
    return _SettingsButton(
      icon: FluentIcons.edit_24_regular,
      label: 'Edit',
      onTap: () => setState(() => _isEditing = true),
    );
  }

  Widget _buildCancelButton(ThemeData theme) {
    return _SettingsButton(
      icon: FluentIcons.dismiss_24_regular,
      label: 'Cancel',
      onTap: () {
        setState(() {
          _isEditing = false;
          // Reset to original values
          _batchSizeController.text = widget.project.batchSize.toString();
          _parallelBatchesController.text =
              widget.project.parallelBatches.toString();
          _customPromptController.text = widget.project.customPrompt ?? '';
        });
      },
    );
  }

  Widget _buildSaveButton(ThemeData theme) {
    return _SettingsButton(
      icon: FluentIcons.checkmark_24_regular,
      label: 'Save',
      isPrimary: true,
      isLoading: _isSaving,
      onTap: _isSaving ? null : _saveSettings,
    );
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final batchSize = int.parse(_batchSizeController.text);
      final parallelBatches = int.parse(_parallelBatchesController.text);
      final customPrompt = _customPromptController.text.trim().isEmpty
          ? null
          : _customPromptController.text.trim();

      await widget.onSave?.call(batchSize, parallelBatches, customPrompt);

      if (mounted) {
        setState(() {
          _isEditing = false;
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
      }
      rethrow;
    }
  }
}

/// Fluent Design button for settings actions
class _SettingsButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isPrimary;
  final bool isLoading;

  const _SettingsButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.isPrimary = false,
    this.isLoading = false,
  });

  @override
  State<_SettingsButton> createState() => _SettingsButtonState();
}

class _SettingsButtonState extends State<_SettingsButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = widget.onTap != null && !widget.isLoading;

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isPrimary
                ? (_isHovered && isEnabled
                    ? theme.colorScheme.primary.withValues(alpha: 0.9)
                    : theme.colorScheme.primary)
                : (_isHovered && isEnabled
                    ? theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
            border: widget.isPrimary
                ? null
                : Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isLoading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.isPrimary
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.primary,
                  ),
                )
              else
                Icon(
                  widget.icon,
                  size: 16,
                  color: isEnabled
                      ? (widget.isPrimary
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isEnabled
                      ? (widget.isPrimary
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
