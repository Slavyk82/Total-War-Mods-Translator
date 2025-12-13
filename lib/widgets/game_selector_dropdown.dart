import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import '../widgets/common/fluent_spinner.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/providers/selected_game_provider.dart';

/// Dropdown widget for selecting the active game
class GameSelectorDropdown extends ConsumerStatefulWidget {
  const GameSelectorDropdown({super.key});

  @override
  ConsumerState<GameSelectorDropdown> createState() => _GameSelectorDropdownState();
}

class _GameSelectorDropdownState extends ConsumerState<GameSelectorDropdown> {
  bool _isExpanded = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configuredGamesAsync = ref.watch(configuredGamesProvider);
    final selectedGameAsync = ref.watch(selectedGameProvider);

    return configuredGamesAsync.when(
      loading: () => _buildLoadingState(theme),
      error: (error, stack) => _buildErrorState(theme, error),
      data: (configuredGames) {
        if (configuredGames.isEmpty) {
          return _buildNoGamesConfigured(context, theme);
        }

        return selectedGameAsync.when(
          loading: () => _buildLoadingState(theme),
          error: (error, stack) => _buildErrorState(theme, error),
          data: (selectedGame) => _buildDropdown(
            context,
            theme,
            configuredGames,
            selectedGame,
          ),
        );
      },
    );
  }

  Widget _buildLoadingState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            FluentSpinner(
              size: 16,
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Text(
              'Loading games...',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme, Object error) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 16,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Error loading games',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoGamesConfigured(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: () => context.go(AppRoutes.settings),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: _isHovered
                  ? theme.colorScheme.primary.withValues(alpha: 0.08)
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _isHovered
                    ? theme.colorScheme.primary.withValues(alpha: 0.3)
                    : theme.dividerColor,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  FluentIcons.settings_24_regular,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Configure a game',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  FluentIcons.chevron_right_24_regular,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown(
    BuildContext context,
    ThemeData theme,
    List<ConfiguredGame> games,
    ConfiguredGame? selectedGame,
  ) {
    final displayText = selectedGame?.name ?? 'Select a game';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Column(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: _isHovered || _isExpanded
                      ? theme.colorScheme.primary.withValues(alpha: 0.08)
                      : theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _isExpanded
                        ? theme.colorScheme.primary
                        : _isHovered
                            ? theme.colorScheme.primary.withValues(alpha: 0.3)
                            : theme.dividerColor,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      FluentIcons.games_24_regular,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        displayText,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      _isExpanded
                          ? FluentIcons.chevron_up_24_regular
                          : FluentIcons.chevron_down_24_regular,
                      size: 16,
                      color: theme.iconTheme.color,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isExpanded)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: theme.dividerColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: games.map((game) {
                  return _GameMenuItem(
                    game: game,
                    isSelected: selectedGame?.code == game.code,
                    onTap: () async {
                      await ref.read(selectedGameProvider.notifier).selectGame(game);
                      setState(() => _isExpanded = false);
                    },
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

/// Individual game menu item
class _GameMenuItem extends StatefulWidget {
  final ConfiguredGame game;
  final bool isSelected;
  final VoidCallback onTap;

  const _GameMenuItem({
    required this.game,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_GameMenuItem> createState() => _GameMenuItemState();
}

class _GameMenuItemState extends State<_GameMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color backgroundColor;
    if (widget.isSelected) {
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.1);
    } else if (_isHovered) {
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.05);
    } else {
      backgroundColor = Colors.transparent;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
          ),
          child: Row(
            children: [
              if (widget.isSelected)
                Icon(
                  FluentIcons.checkmark_24_regular,
                  size: 16,
                  color: theme.colorScheme.primary,
                )
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.game.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: widget.isSelected
                        ? theme.colorScheme.primary
                        : theme.textTheme.bodyMedium?.color,
                    fontWeight: widget.isSelected ? FontWeight.w500 : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}




