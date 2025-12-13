import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/models/domain/game_installation.dart';
import '../providers/glossary_providers.dart';

/// Header for the glossary list view.
class GlossaryListHeader extends StatelessWidget {
  const GlossaryListHeader({
    super.key,
    required this.onNewGlossary,
  });

  final VoidCallback onNewGlossary;

  @override
  Widget build(BuildContext context) {
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
          GlossaryActionButton(
            icon: FluentIcons.add_24_regular,
            label: 'New Glossary',
            onPressed: onNewGlossary,
          ),
        ],
      ),
    );
  }
}

/// Header for the glossary editor view (with back button).
class GlossaryEditorHeader extends ConsumerWidget {
  const GlossaryEditorHeader({
    super.key,
    required this.glossary,
    required this.gameInstallations,
    required this.onImport,
    required this.onExport,
    required this.onDelete,
  });

  final Glossary glossary;
  final Map<String, GameInstallation> gameInstallations;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUniversal = glossary.isGlobal;
    final gameName = glossary.gameInstallationId != null
        ? gameInstallations[glossary.gameInstallationId]?.gameName
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
          _BackButton(
            onTap: () => ref.read(selectedGlossaryProvider.notifier).clear(),
          ),
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
          GlossaryActionButton(
            icon: FluentIcons.arrow_import_24_regular,
            label: 'Import',
            onPressed: onImport,
          ),
          const SizedBox(width: 8),
          GlossaryActionButton(
            icon: FluentIcons.arrow_export_24_regular,
            label: 'Export',
            onPressed: onExport,
          ),
          const SizedBox(width: 8),
          GlossaryActionButton(
            icon: FluentIcons.delete_24_regular,
            label: 'Delete',
            onPressed: onDelete,
            isDestructive: true,
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
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
}

/// Toolbar for glossary editor with search and add entry button.
class GlossaryEditorToolbar extends ConsumerWidget {
  const GlossaryEditorToolbar({
    super.key,
    required this.glossary,
    required this.searchController,
    required this.onAddEntry,
  });

  final Glossary glossary;
  final TextEditingController searchController;
  final VoidCallback onAddEntry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          // Search bar
          Expanded(
            flex: 2,
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Search entries...',
                prefixIcon: const Icon(FluentIcons.search_24_regular),
                suffixIcon: searchController.text.isNotEmpty
                    ? MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            searchController.clear();
                            ref
                                .read(glossaryFilterStateProvider.notifier)
                                .setSearchText('');
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
                ref
                    .read(glossaryFilterStateProvider.notifier)
                    .setSearchText(value);
              },
            ),
          ),
          const SizedBox(width: 16),

          // Add Entry button
          GlossaryActionButton(
            icon: FluentIcons.add_24_regular,
            label: 'Add Entry',
            onPressed: onAddEntry,
          ),
        ],
      ),
    );
  }
}

/// Footer showing glossary info.
class GlossaryEditorFooter extends StatelessWidget {
  const GlossaryEditorFooter({
    super.key,
    required this.glossary,
    required this.gameInstallations,
  });

  final Glossary glossary;
  final Map<String, GameInstallation> gameInstallations;

  @override
  Widget build(BuildContext context) {
    final isUniversal = glossary.isGlobal;
    final gameName = glossary.gameInstallationId != null
        ? gameInstallations[glossary.gameInstallationId]?.gameName
        : null;
    final typeLabel = isUniversal
        ? 'Universal Glossary'
        : gameName ?? 'Game-specific';

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
}

/// Empty state when no glossaries exist.
class GlossaryEmptyState extends StatelessWidget {
  const GlossaryEmptyState({super.key, required this.onNewGlossary});
  final VoidCallback onNewGlossary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.book_24_regular,
            size: 64,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No glossaries yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a glossary to manage your translation terminology',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
          ),
          const SizedBox(height: 24),
          GlossaryActionButton(
            icon: FluentIcons.add_24_regular,
            label: 'Create New Glossary',
            onPressed: onNewGlossary,
          ),
        ],
      ),
    );
  }
}

/// Action button used throughout glossary screens.
class GlossaryActionButton extends StatelessWidget {
  const GlossaryActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
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
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
}
