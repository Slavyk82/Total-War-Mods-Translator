import 'package:flutter/material.dart';

/// Fluent Design color palette for TWMT.
///
/// Based on Microsoft Fluent Design System colors.
class FluentColors {
  FluentColors._();

  // Primary colors
  static const primary = Color(0xFF0078D4);
  static const primaryDark = Color(0xFF106EBE);
  static const primaryLight = Color(0xFF50A0E0);

  // Accent colors
  static const accent = Color(0xFF0078D4);
  static const success = Color(0xFF107C10);
  static const warning = Color(0xFFF7630C);
  static const error = Color(0xFFE81123);
  static const info = Color(0xFF0078D4);

  // Neutral colors (Light theme)
  static const white = Color(0xFFFFFFFF);
  static const gray10 = Color(0xFFFAF9F8);
  static const gray20 = Color(0xFFF3F2F1);
  static const gray30 = Color(0xFFEDEBE9);
  static const gray40 = Color(0xFFE1DFDD);
  static const gray50 = Color(0xFFD2D0CE);
  static const gray60 = Color(0xFFC8C6C4);
  static const gray70 = Color(0xFFA19F9D);
  static const gray80 = Color(0xFF797775);
  static const gray90 = Color(0xFF605E5C);
  static const gray100 = Color(0xFF484644);
  static const gray110 = Color(0xFF3B3A39);
  static const gray120 = Color(0xFF323130);
  static const gray130 = Color(0xFF292827);
  static const gray140 = Color(0xFF201F1E);
  static const gray150 = Color(0xFF161514);
  static const gray160 = Color(0xFF11100F);
  static const black = Color(0xFF000000);

  // Semantic colors for Light theme
  static const lightBackground = white;
  static const lightSurface = gray20;
  static const lightDivider = gray40;
  static const lightBorder = gray50;
  static const lightText = gray130;
  static const lightTextSecondary = gray90;
  static const lightTextDisabled = gray60;

  // Semantic colors for Dark theme
  static const darkBackground = Color(0xFF1E1E1E);
  static const darkSurface = Color(0xFF252525);
  static const darkDivider = Color(0xFF3B3B3B);
  static const darkBorder = Color(0xFF484848);
  static const darkText = gray20;
  static const darkTextSecondary = gray60;
  static const darkTextDisabled = gray80;

  // Hover/Focus states
  static const hoverLight = Color(0x0A000000); // 4% black
  static const hoverDark = Color(0x0AFFFFFF); // 4% white
  static const pressedLight = Color(0x14000000); // 8% black
  static const pressedDark = Color(0x14FFFFFF); // 8% white
  static const focusStroke = primary;

  // Status colors
  static const statusSuccess = success;
  static const statusWarning = warning;
  static const statusError = error;
  static const statusInfo = info;
}
