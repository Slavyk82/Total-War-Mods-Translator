import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Vellum palette — the only light theme.
///
/// Cream paper background, deep brown ink, ink-blue accent evocative of
/// cartographic and manuscript inks. Designed for editorial review
/// sessions in daylight. Consumers that assume a dark brightness must
/// check `Theme.of(context).brightness` before painting. Typography is
/// shared with every other theme (IBM Plex).
final TwmtThemeTokens vellumTokens = TwmtThemeTokens(
  // Palette
  bg: const Color(0xFFF3EAD7),
  panel: const Color(0xFFEFE3CA),
  panel2: const Color(0xFFE7D8BB),
  border: const Color(0xFFD6C6A4),
  text: const Color(0xFF2B231A),
  textMid: const Color(0xFF5C4E3D),
  textDim: const Color(0xFF8A7A62),
  textFaint: const Color(0xFFB5A489),
  accent: const Color(0xFF1F4E8A),
  accentFg: const Color(0xFFF3EAD7),
  accentBg: const Color(0xFFD4DEEB),
  ok: const Color(0xFF4F6A2B),
  okBg: const Color(0xFFDCE4C2),
  warn: const Color(0xFFB5711E),
  warnBg: const Color(0xFFEEDCB8),
  err: const Color(0xFF8A1F14),
  errBg: const Color(0xFFE8CAC2),
  info: const Color(0xFF2E6E77),
  infoBg: const Color(0xFFCEE1E3),
  llm: const Color(0xFF6A4A8C),
  llmBg: const Color(0xFFDBCFE3),
  rowSelected: const Color(0xFFE2CFA8),

  // Typography — identical to Atelier/Forge: IBM Plex Sans + Mono.
  fontBody: const TextStyle(fontFamily: 'IBMPlexSans'),
  fontDisplay: const TextStyle(
    fontFamily: 'IBMPlexSans',
    fontWeight: FontWeight.w500,
  ),
  fontMono: const TextStyle(fontFamily: 'IBMPlexMono'),
  fontDisplayItalic: false,

  // Radius — shared scale.
  radiusXs: 3.0,
  radiusSm: 4.0,
  radiusMd: 8.0,
  radiusLg: 10.0,
  radiusPill: 20.0,
);
