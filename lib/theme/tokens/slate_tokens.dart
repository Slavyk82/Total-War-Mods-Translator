import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Slate palette — sober, mineral, cold monochrome.
///
/// Dark blue-grey surfaces with a single indigo accent. The quietest of the
/// dark themes: no warm tones, no green, meant for long focus sessions on
/// the editor screen. Typography is shared with Atelier/Forge (IBM Plex).
final TwmtThemeTokens slateTokens = TwmtThemeTokens(
  // Palette
  bg: const Color(0xFF101218),
  panel: const Color(0xFF0C0E14),
  panel2: const Color(0xFF161922),
  border: const Color(0xFF232834),
  text: const Color(0xFFE4E7EE),
  textMid: const Color(0xFFA8ADBA),
  textDim: const Color(0xFF6E7383),
  textFaint: const Color(0xFF454956),
  accent: const Color(0xFF7C8CFF),
  accentFg: const Color(0xFF0B0D14),
  accentBg: const Color(0xFF151A2E),
  ok: const Color(0xFF7FB88A),
  okBg: const Color(0xFF14241A),
  warn: const Color(0xFFE0B36A),
  warnBg: const Color(0xFF2A1F0E),
  err: const Color(0xFFD96A7A),
  errBg: const Color(0xFF2B1218),
  info: const Color(0xFF7AA8E0),
  infoBg: const Color(0xFF121E2C),
  llm: const Color(0xFFA892E0),
  llmBg: const Color(0xFF1C1629),
  rowSelected: const Color(0xFF181C28),

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
