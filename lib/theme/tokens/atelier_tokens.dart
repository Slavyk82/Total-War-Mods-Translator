import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Atelier palette + typography — default TWMT theme.
///
/// Warm greige charcoal, ambre accent. Editorial typography: Instrument
/// Sans body, Instrument Serif italic display, JetBrains Mono for code.
///
/// See spec §4.1.
final TwmtThemeTokens atelierTokens = TwmtThemeTokens(
  // Palette
  bg: const Color(0xFF1A1816),
  panel: const Color(0xFF15130F),
  panel2: const Color(0xFF1F1B17),
  border: const Color(0xFF2A2420),
  text: const Color(0xFFF5ECD9),
  textMid: const Color(0xFFB8AD9C),
  textDim: const Color(0xFF7A6F60),
  textFaint: const Color(0xFF5E5648),
  accent: const Color(0xFFD89A4A),
  accentFg: const Color(0xFF1A1612),
  accentBg: const Color(0xFF241D15),
  ok: const Color(0xFF9ECC8A),
  okBg: const Color(0xFF2A3A2A),
  warn: const Color(0xFFD89A4A),
  warnBg: const Color(0xFF3A2E1E),
  err: const Color(0xFFC47A6E),
  errBg: const Color(0xFF3A2624),
  info: const Color(0xFF8AB3D4),
  infoBg: const Color(0xFF1E2530),
  llm: const Color(0xFFB09EDC),
  llmBg: const Color(0xFF2E263A),
  rowSelected: const Color(0xFF221B13),

  // Typography
  fontBody: GoogleFonts.instrumentSans(),
  fontDisplay: GoogleFonts.instrumentSerif(
    fontStyle: FontStyle.italic,
  ),
  fontMono: GoogleFonts.jetBrainsMono(),
  fontDisplayItalic: true,

  // Radius
  radiusXs: 3.0,
  radiusSm: 4.0,
  radiusMd: 8.0,
  radiusLg: 10.0,
  radiusPill: 20.0,
);
