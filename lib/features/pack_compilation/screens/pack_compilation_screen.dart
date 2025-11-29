import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart' hide FluentIconButton;
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../providers/pack_compilation_providers.dart';
import '../widgets/compilation_list.dart';
import '../widgets/compilation_editor.dart';

/// Screen for managing pack compilations.
///
/// Features:
/// - List existing compilations
/// - Create new compilations
/// - Edit compilation configuration
/// - Generate combined .pack files
class PackCompilationScreen extends ConsumerStatefulWidget {
  const PackCompilationScreen({super.key});

  @override
  ConsumerState<PackCompilationScreen> createState() =>
      _PackCompilationScreenState();
}

class _PackCompilationScreenState extends ConsumerState<PackCompilationScreen> {
  bool _showEditor = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editorState = ref.watch(compilationEditorProvider);

    if (_showEditor) {
      // Block navigation during compilation
      final canNavigate = !editorState.isCompiling;

      return FluentScaffold(
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        header: FluentHeader(
          backgroundColor: theme.colorScheme.surface,
          leading: FluentIconButton(
            icon: Icon(
              FluentIcons.arrow_left_24_regular,
              color: canNavigate
                  ? null
                  : theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            onPressed: canNavigate ? () => _hideEditor() : null,
            tooltip: canNavigate ? 'Back' : 'Stop generation to go back',
          ),
          title: editorState.isEditing ? editorState.name : 'New Compilation',
        ),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: CompilationEditor(
            onCancel: canNavigate ? () => _hideEditor() : null,
            onSaved: () => _onSaved(),
          ),
        ),
      );
    }

    return FluentScaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(theme),
            const SizedBox(height: 24),
            // Main content
            Expanded(
              child: CompilationList(
                onCreateNew: () => _showCreateNew(),
                onEdit: (compilation) => _showEditCompilation(compilation),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: [
        Icon(
          FluentIcons.box_multiple_24_regular,
          size: 32,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Text(
          'Pack Compilations',
          style: theme.textTheme.headlineLarge,
        ),
        const Spacer(),
        _CreateButton(onTap: () => _showCreateNew()),
      ],
    );
  }

  void _showCreateNew() {
    ref.read(compilationEditorProvider.notifier).reset();
    setState(() => _showEditor = true);
  }

  void _showEditCompilation(CompilationWithDetails compilation) {
    ref.read(compilationEditorProvider.notifier).loadCompilation(compilation);
    setState(() => _showEditor = true);
  }

  void _hideEditor() {
    ref.read(compilationEditorProvider.notifier).reset();
    setState(() => _showEditor = false);
  }

  void _onSaved() {
    ref.invalidate(compilationsWithDetailsProvider);
    _hideEditor();
  }
}

class _CreateButton extends StatefulWidget {
  const _CreateButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_CreateButton> createState() => _CreateButtonState();
}

class _CreateButtonState extends State<_CreateButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _isHovered
                ? theme.colorScheme.primary.withValues(alpha: 0.9)
                : theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.add_24_regular,
                size: 20,
                color: theme.colorScheme.onPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                'New Compilation',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
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

