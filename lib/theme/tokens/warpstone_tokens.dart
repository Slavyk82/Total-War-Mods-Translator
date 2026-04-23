import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Warpstone palette — Total War: Warhammer gaming theme.
///
/// Violet-tinted near-black surfaces, controlled warpstone-green accent,
/// visceral red error. The most expressive dark theme; keep the green on
/// accent only (never on panels) to avoid saturation fatigue. Typography
/// is shared with every other theme.
final TwmtThemeTokens warpstoneTokens = TwmtThemeTokens(
  // Palette
  bg: const Color(0xFF0A0910),
  panel: const Color(0xFF0E0B15),
  panel2: const Color(0xFF15101E),
  border: const Color(0xFF2A1E3A),
  text: const Color(0xFFEADFF2),
  textMid: const Color(0xFFA99AC0),
  textDim: const Color(0xFF716385),
  textFaint: const Color(0xFF443A55),
  accent: const Color(0xFF6EE07A),
  accentFg: const Color(0xFF0A0910),
  accentBg: const Color(0xFF0F2818),
  ok: const Color(0xFF6EE07A),
  okBg: const Color(0xFF0F2818),
  warn: const Color(0xFFE0A33D),
  warnBg: const Color(0xFF2A1E0A),
  err: const Color(0xFFE03A4A),
  errBg: const Color(0xFF2A0D12),
  info: const Color(0xFF5FA2E0),
  infoBg: const Color(0xFF0F1C2E),
  llm: const Color(0xFFC58AFF),
  llmBg: const Color(0xFF1E1230),
  rowSelected: const Color(0xFF1A1028),

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
