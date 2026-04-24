import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// 80×80 cover thumbnail for a project row.
///
/// Shows the project image when [imageUrl] is set, `assets/twmt_icon.png`
/// when the project represents a full-game translation, and a game-specific
/// Fluent icon fallback otherwise.
class ProjectCoverThumbnail extends StatelessWidget {
  final String? imageUrl;
  final bool isGameTranslation;
  final String? gameCode;

  const ProjectCoverThumbnail({
    super.key,
    required this.imageUrl,
    required this.isGameTranslation,
    required this.gameCode,
  });

  IconData _iconFor(String? code) {
    switch (code?.toLowerCase()) {
      case 'wh3':
      case 'wh2':
      case 'wh1':
        return FluentIcons.shield_24_regular;
      case 'troy':
        return FluentIcons.crown_24_regular;
      case 'threekingdoms':
      case '3k':
        return FluentIcons.people_24_regular;
      default:
        return FluentIcons.games_24_regular;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    Widget fallback() => Icon(
          _iconFor(gameCode),
          size: 44,
          color: tokens.textMid,
        );

    Widget img;
    if (isGameTranslation) {
      img = Image.asset(
        'assets/twmt_icon.png',
        fit: BoxFit.cover,
        width: 80,
        height: 80,
        cacheWidth: 160,
        cacheHeight: 160,
        errorBuilder: (_, _, _) => fallback(),
      );
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      img = Image.file(
        File(imageUrl!),
        fit: BoxFit.cover,
        width: 80,
        height: 80,
        cacheWidth: 160,
        cacheHeight: 160,
        errorBuilder: (_, _, _) => fallback(),
      );
    } else {
      img = fallback();
    }
    return Center(
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: tokens.panel,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: img,
      ),
    );
  }
}
