import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:twmt/theme/tokens/atelier_tokens.dart';

void main() {
  // Initialize the test binding and disable runtime font fetching so that
  // `GoogleFonts` calls in `atelierTokens` don't hit the network during
  // unit tests.
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  // Force module initialization inside a guarded zone: the GoogleFonts
  // factories used by `atelierTokens` schedule async asset lookups that
  // always fail in a pure-Dart test environment (no font assets are
  // bundled for this unit test). Swallowing these ensures the colour /
  // radius assertions below run cleanly.
  setUpAll(() {
    runZonedGuarded(() {
      // Touch a field so the `final` initializer runs inside the zone.
      atelierTokens.bg;
    }, (_, _) {});
  });

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

    test('fontDisplayItalic is true (Instrument Serif italic)', () {
      expect(atelierTokens.fontDisplayItalic, isTrue);
    });
  });
}
