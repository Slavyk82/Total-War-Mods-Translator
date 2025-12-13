import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import '../providers/glossary_providers.dart';
import '../../../widgets/common/fluent_spinner.dart';

/// Dropdown widget for selecting a glossary
class GlossarySelector extends ConsumerWidget {
  final Glossary? selectedGlossary;
  final void Function(Glossary?) onGlossarySelected;
  final VoidCallback onCreateNew;

  const GlossarySelector({
    super.key,
    required this.selectedGlossary,
    required this.onGlossarySelected,
    required this.onCreateNew,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glossariesAsync = ref.watch(glossariesProvider());

    return glossariesAsync.when(
      data: (glossaries) => _buildDropdown(context, glossaries),
      loading: () => _buildLoadingState(context),
      error: (error, stack) => _buildErrorState(context, error),
    );
  }

  Widget _buildDropdown(BuildContext context, List<Glossary> glossaries) {
    if (glossaries.isEmpty) {
      return _buildEmptyState(context);
    }

    // Group glossaries by type
    final globalGlossaries =
        glossaries.where((g) => g.isGlobal).toList()..sort((a, b) => a.name.compareTo(b.name));
    final projectGlossaries =
        glossaries.where((g) => !g.isGlobal).toList()..sort((a, b) => a.name.compareTo(b.name));

    return PopupMenuButton<Glossary?>(
      initialValue: selectedGlossary,
      offset: const Offset(0, 8),
      child: _buildSelectorButton(context),
      itemBuilder: (context) {
        final items = <PopupMenuEntry<Glossary?>>[];

        // Global glossaries section
        if (globalGlossaries.isNotEmpty) {
          items.add(
            PopupMenuItem<Glossary?>(
              enabled: false,
              child: Text(
                'Global Glossaries',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
          );

          for (final glossary in globalGlossaries) {
            items.add(
              PopupMenuItem<Glossary?>(
                value: glossary,
                child: _buildGlossaryMenuItem(context, glossary, isGlobal: true),
              ),
            );
          }
        }

        // Project glossaries section
        if (projectGlossaries.isNotEmpty) {
          if (globalGlossaries.isNotEmpty) {
            items.add(const PopupMenuDivider());
          }

          items.add(
            PopupMenuItem<Glossary?>(
              enabled: false,
              child: Text(
                'Project Glossaries',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
              ),
            ),
          );

          for (final glossary in projectGlossaries) {
            items.add(
              PopupMenuItem<Glossary?>(
                value: glossary,
                child: _buildGlossaryMenuItem(context, glossary, isGlobal: false),
              ),
            );
          }
        }

        // New glossary option
        items.add(const PopupMenuDivider());
        items.add(
          PopupMenuItem<Glossary?>(
            value: null,
            child: Row(
              children: [
                Icon(
                  FluentIcons.add_24_regular,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Create New Glossary...',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );

        return items;
      },
      onSelected: (glossary) {
        if (glossary == null) {
          onCreateNew();
        } else {
          onGlossarySelected(glossary);
        }
      },
    );
  }

  Widget _buildSelectorButton(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outline,
          ),
          borderRadius: BorderRadius.circular(4.0),
        ),
        child: Row(
          children: [
            Icon(
              selectedGlossary?.isGlobal == true
                  ? FluentIcons.globe_24_regular
                  : FluentIcons.folder_24_regular,
              size: 20,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                selectedGlossary?.name ?? 'Select a glossary...',
                style: Theme.of(context).textTheme.bodyLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (selectedGlossary != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Text(
                  '${selectedGlossary!.entryCount} entries',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Icon(
              FluentIcons.chevron_down_24_regular,
              size: 20,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlossaryMenuItem(
    BuildContext context,
    Glossary glossary, {
    required bool isGlobal,
  }) {
    final isSelected = selectedGlossary?.id == glossary.id;

    return Row(
      children: [
        Icon(
          isGlobal ? FluentIcons.globe_24_regular : FluentIcons.folder_24_regular,
          size: 20,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            glossary.name,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10.0),
          ),
          child: Text(
            '${glossary.entryCount}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
        ),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Row(
        children: [
          const FluentSpinner(size: 20, strokeWidth: 2),
          const SizedBox(width: 12),
          Text(
            'Loading glossaries...',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, Object error) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.error,
        ),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            size: 20,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Error loading glossaries: $error',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onCreateNew,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outline,
            ),
            borderRadius: BorderRadius.circular(4.0),
          ),
          child: Row(
            children: [
              Icon(
                FluentIcons.add_24_regular,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'No glossaries. Create one.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
