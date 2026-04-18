import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/tokens/atelier_tokens.dart';

void main() {
  group('atelierTokens', () {
    test('bg matches the spec warm greige', () {
      expect(atelierTokens.bg, const Color(0xFF1A1816));
    });

    test('accent is the ambre tone', () {
      expect(atelierTokens.accent, const Color(0xFFD89A4A));
    });

    test('accentFg provides readable contrast on accent', () {
      expect(atelierTokens.accentFg, const Color(0xFF1A1612));
    });

    test('radii match the design-token scale', () {
      expect(atelierTokens.radiusXs, 3.0);
      expect(atelierTokens.radiusSm, 4.0);
      expect(atelierTokens.radiusMd, 8.0);
      expect(atelierTokens.radiusLg, 10.0);
      expect(atelierTokens.radiusPill, 20.0);
    });

    test('fontDisplayItalic is false (shared IBM Plex typography)', () {
      expect(atelierTokens.fontDisplayItalic, isFalse);
    });
  });
}
