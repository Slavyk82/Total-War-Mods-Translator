import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Shogun palette — Total War: Shogun 2, mid-gaming theme.
///
/// Lacquered near-black surfaces, shu-iro vermillion accent, rice-paper
/// text tone. Sits between the sober themes and the fully-gaming ones:
/// single bold accent, no secondary colour chrome. Typography is shared
/// with every other theme.
final TwmtThemeTokens shogunTokens = TwmtThemeTokens(
  // Palette
  bg: const Color(0xFF0E0B0B),
  panel: const Color(0xFF131010),
  panel2: const Color(0xFF1B1615),
  border: const Color(0xFF2A2220),
  text: const Color(0xFFF0E6D2),
  textMid: const Color(0xFFB8A896),
  textDim: const Color(0xFF7A6A5A),
  textFaint: const Color(0xFF4C4238),
  accent: const Color(0xFFD14B35),
  accentFg: const Color(0xFF0E0B0B),
  accentBg: const Color(0xFF2B1512),
  ok: const Color(0xFF8FB08C),
  okBg: const Color(0xFF182217),
  warn: const Color(0xFFD1A84B),
  warnBg: const Color(0xFF2A2010),
  err: const Color(0xFFB8332A),
  errBg: const Color(0xFF2A100D),
  info: const Color(0xFF6B8BAA),
  infoBg: const Color(0xFF161E28),
  llm: const Color(0xFF9079B8),
  llmBg: const Color(0xFF1E172A),
  rowSelected: const Color(0xFF1F1312),

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
