import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Forge palette + typography — pro-tool variant.
///
/// Cold charcoal background, cyan accent. Technical typography: IBM Plex
/// Sans body + display (500 weight, no italic), IBM Plex Mono for code.
///
/// See spec §4.2.
final TwmtThemeTokens forgeTokens = TwmtThemeTokens(
  // Palette
  bg: const Color(0xFF0A0A0B),
  panel: const Color(0xFF0D0D10),
  panel2: const Color(0xFF121215),
  border: const Color(0xFF1D1D22),
  text: const Color(0xFFE8E8EA),
  textMid: const Color(0xFFB8B8BC),
  textDim: const Color(0xFF888891),
  textFaint: const Color(0xFF4A4A50),
  accent: const Color(0xFF00D4FF),
  accentFg: const Color(0xFF000000),
  accentBg: const Color(0xFF0A1518),
  ok: const Color(0xFF00D4FF),
  okBg: const Color(0xFF0A1E24),
  warn: const Color(0xFFFFAA00),
  warnBg: const Color(0xFF241A00),
  err: const Color(0xFFFF3366),
  errBg: const Color(0xFF240914),
  info: const Color(0xFF4DA6FF),
  infoBg: const Color(0xFF0A1A2E),
  llm: const Color(0xFFC28EFF),
  llmBg: const Color(0xFF1B0F28),
  rowSelected: const Color(0xFF0F1418),

  // Typography — same family for body & display; weight differs at use site.
  fontBody: const TextStyle(fontFamily: 'IBMPlexSans'),
  fontDisplay: const TextStyle(
    fontFamily: 'IBMPlexSans',
    fontWeight: FontWeight.w500,
  ),
  fontMono: const TextStyle(fontFamily: 'IBMPlexMono'),
  fontDisplayItalic: false,

  // Radius
  radiusXs: 3.0,
  radiusSm: 4.0,
  radiusMd: 8.0,
  radiusLg: 10.0,
  radiusPill: 20.0,
);
