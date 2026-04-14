import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/tokens/forge_tokens.dart';

void main() {
  group('forgeTokens', () {
    test('bg is near-black charcoal', () {
      expect(forgeTokens.bg, const Color(0xFF0A0A0B));
    });

    test('accent is the cyan tone', () {
      expect(forgeTokens.accent, const Color(0xFF00D4FF));
    });

    test('accentFg is pure black for max contrast on cyan', () {
      expect(forgeTokens.accentFg, const Color(0xFF000000));
    });

    test('fontDisplayItalic is false (no italic serif in Forge)', () {
      expect(forgeTokens.fontDisplayItalic, isFalse);
    });

    test('radii identical to Atelier — r=8 is global', () {
      expect(forgeTokens.radiusMd, 8.0);
      expect(forgeTokens.radiusPill, 20.0);
    });
  });
}
