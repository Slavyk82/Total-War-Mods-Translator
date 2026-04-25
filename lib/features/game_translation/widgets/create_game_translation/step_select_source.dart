import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:intl/intl.dart';

import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

import '../../../../providers/selected_game_provider.dart';
import '../../../../services/game/game_localization_service.dart';
import '../../../../utils/game_label.dart';
import '../../providers/game_translation_providers.dart';
import 'game_translation_creation_state.dart';

/// Step 1: select source localization pack.
///
/// Retokenised (Plan 5d · Task 5): pack rows rebuilt as panel/accent
/// selectable containers, empty / error states use `tokens.err` + `tokens.errBg`.
class StepSelectSource extends ConsumerWidget {
  final GameTranslationCreationState state;
  final VoidCallback onStateChanged;

  const StepSelectSource({
    super.key,
    required this.state,
    required this.onStateChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final selectedGameAsync = ref.watch(selectedGameProvider);
    final packsAsync = ref.watch(detectedLocalPacksProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.gameTranslation.stepSource.description,
          style: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.textDim,
          ),
        ),
        const SizedBox(height: 16),

        // Selected game info
        selectedGameAsync.when(
          data: (game) => game != null
              ? Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tokens.accentBg,
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(
                      color: tokens.accent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        FluentIcons.games_24_regular,
                        color: tokens.accent,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        gameLabel(game.name),
                        style: tokens.fontBody.copyWith(
                          fontSize: 13,
                          color: tokens.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              : Text(
                  t.gameTranslation.stepSource.noGameSelected,
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: tokens.textDim,
                  ),
                ),
          loading: () => SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
            ),
          ),
          error: (e, _) => Text(
            'Error: $e',
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.err,
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Pack selection
        Text(
          t.gameTranslation.stepSource.sectionLabel,
          style: tokens.fontMono.copyWith(
            fontSize: 10,
            color: tokens.textDim,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),

        packsAsync.when(
          data: (packs) {
            if (packs.isEmpty) {
              return _buildNoPacks(tokens);
            }
            return _buildPackList(context, tokens, packs);
          },
          loading: () => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
                ),
              ),
            ),
          ),
          error: (e, _) => _buildError(tokens, e.toString()),
        ),
      ],
    );
  }

  Widget _buildNoPacks(TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.errBg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.err.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(
            FluentIcons.warning_24_regular,
            size: 40,
            color: tokens.err,
          ),
          const SizedBox(height: 10),
          Text(
            t.gameTranslation.stepSource.noPacks.title,
            style: tokens.fontBody.copyWith(
              fontSize: 14,
              color: tokens.err,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t.gameTranslation.stepSource.noPacks.subtitle,
            style: tokens.fontBody.copyWith(
              fontSize: 12.5,
              color: tokens.textDim,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPackList(
    BuildContext context,
    TwmtThemeTokens tokens,
    List<DetectedLocalPack> packs,
  ) {
    final dateFormat = DateFormat.yMMMd().add_Hm();

    return Column(
      children: packs.map((pack) {
        final isSelected = state.selectedSourcePack == pack;

        return _PackSelectionItem(
          pack: pack,
          isSelected: isSelected,
          dateFormat: dateFormat,
          onTap: () {
            state.selectedSourcePack = pack;
            // Clear target languages when source changes
            state.clearLanguages();
            onStateChanged();
          },
        );
      }).toList(),
    );
  }

  Widget _buildError(TwmtThemeTokens tokens, String error) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.errBg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.err.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            color: tokens.err,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.err,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A selectable pack row — token themed.
class _PackSelectionItem extends StatefulWidget {
  final DetectedLocalPack pack;
  final bool isSelected;
  final DateFormat dateFormat;
  final VoidCallback onTap;

  const _PackSelectionItem({
    required this.pack,
    required this.isSelected,
    required this.dateFormat,
    required this.onTap,
  });

  @override
  State<_PackSelectionItem> createState() => _PackSelectionItemState();
}

class _PackSelectionItemState extends State<_PackSelectionItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final Color backgroundColor;
    if (widget.isSelected) {
      backgroundColor = tokens.accentBg;
    } else if (_isHovered) {
      backgroundColor = tokens.panel2;
    } else {
      backgroundColor = tokens.panel;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(
                color: widget.isSelected ? tokens.accent : tokens.border,
                width: widget.isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Radio indicator
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.isSelected
                          ? tokens.accent
                          : tokens.border,
                      width: 2,
                    ),
                  ),
                  child: widget.isSelected
                      ? Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: tokens.accent,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                // Language icon
                Icon(
                  FluentIcons.local_language_24_regular,
                  size: 20,
                  color: widget.isSelected ? tokens.accent : tokens.textDim,
                ),
                const SizedBox(width: 12),
                // Pack info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.pack.languageName,
                        style: tokens.fontBody.copyWith(
                          fontSize: 13.5,
                          color:
                              widget.isSelected ? tokens.accent : tokens.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'local_${widget.pack.languageCode}.pack',
                        style: tokens.fontMono.copyWith(
                          fontSize: 11.5,
                          color: tokens.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                // Size and date
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      widget.pack.formattedSize,
                      style: tokens.fontMono.copyWith(
                        fontSize: 12,
                        color: tokens.textMid,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.dateFormat.format(widget.pack.lastModified),
                      style: tokens.fontBody.copyWith(
                        fontSize: 11.5,
                        color: tokens.textDim,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
