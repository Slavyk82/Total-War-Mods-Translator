import 'package:flutter/material.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'glossary_card.dart';

/// List layout for displaying glossary cards.
///
/// Displays glossary cards grouped by type (Universal / Game-specific).
class GlossaryList extends StatelessWidget {
  final List<Glossary> glossaries;
  final Map<String, GameInstallation> gameInstallations;
  final void Function(Glossary glossary)? onGlossaryTap;
  final void Function(Glossary glossary)? onDeleteGlossary;

  const GlossaryList({
    super.key,
    required this.glossaries,
    this.gameInstallations = const {},
    this.onGlossaryTap,
    this.onDeleteGlossary,
  });

  @override
  Widget build(BuildContext context) {
    if (glossaries.isEmpty) {
      return const SizedBox.shrink();
    }

    // Group glossaries by type
    final universalGlossaries = glossaries.where((g) => g.isGlobal).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final gameSpecificGlossaries = glossaries.where((g) => !g.isGlobal).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Universal glossaries section
        if (universalGlossaries.isNotEmpty) ...[
          _buildSectionHeader(context, 'Universal Glossaries', isUniversal: true),
          const SizedBox(height: 12),
          ...universalGlossaries.map(
            (glossary) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlossaryCard(
                glossary: glossary,
                onTap: () => onGlossaryTap?.call(glossary),
                onDelete: onDeleteGlossary != null
                    ? () => onDeleteGlossary?.call(glossary)
                    : null,
              ),
            ),
          ),
        ],

        // Spacing between sections
        if (universalGlossaries.isNotEmpty && gameSpecificGlossaries.isNotEmpty)
          const SizedBox(height: 24),

        // Game-specific glossaries section
        if (gameSpecificGlossaries.isNotEmpty) ...[
          _buildSectionHeader(context, 'Game-specific Glossaries', isUniversal: false),
          const SizedBox(height: 12),
          ...gameSpecificGlossaries.map(
            (glossary) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlossaryCard(
                glossary: glossary,
                gameName: _getGameName(glossary.gameInstallationId),
                onTap: () => onGlossaryTap?.call(glossary),
                onDelete: onDeleteGlossary != null
                    ? () => onDeleteGlossary?.call(glossary)
                    : null,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String? _getGameName(String? gameInstallationId) {
    if (gameInstallationId == null) return null;
    return gameInstallations[gameInstallationId]?.gameName;
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title, {
    required bool isUniversal,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: isUniversal
                ? theme.colorScheme.primary
                : theme.colorScheme.secondary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: isUniversal
                ? theme.colorScheme.primary
                : theme.colorScheme.secondary,
          ),
        ),
      ],
    );
  }
}
