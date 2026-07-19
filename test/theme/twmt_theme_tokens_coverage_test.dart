import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

// The concrete font source is irrelevant to the behaviour exercised here;
// TwmtThemeTokens only stores and forwards the TextStyle values.
const TextStyle _bodyFont = TextStyle(fontFamily: 'CovBody');
const TextStyle _displayFont = TextStyle(fontFamily: 'CovDisplay');
const TextStyle _monoFont = TextStyle(fontFamily: 'CovMono');

/// Baseline fixture with a distinct value per field so field-by-field checks
/// can catch a mis-wired copyWith/== branch.
TwmtThemeTokens _fixture() {
  return const TwmtThemeTokens(
    bg: Color(0xFF111111),
    panel: Color(0xFF222222),
    panel2: Color(0xFF333333),
    border: Color(0xFF444444),
    text: Color(0xFFAAAAAA),
    textMid: Color(0xFF888888),
    textDim: Color(0xFF666666),
    textFaint: Color(0xFF555555),
    accent: Color(0xFFFFAA00),
    accentFg: Color(0xFF000000),
    accentBg: Color(0xFF221100),
    ok: Color(0xFF00AA00),
    okBg: Color(0xFF002200),
    warn: Color(0xFFAA8800),
    warnBg: Color(0xFF221800),
    err: Color(0xFFAA0000),
    errBg: Color(0xFF220000),
    info: Color(0xFF3366AA),
    infoBg: Color(0xFF001122),
    llm: Color(0xFF8800AA),
    llmBg: Color(0xFF180022),
    rowSelected: Color(0xFF112233),
    fontBody: _bodyFont,
    fontDisplay: _displayFont,
    fontMono: _monoFont,
    fontDisplayItalic: false,
    radiusXs: 3.0,
    radiusSm: 4.0,
    radiusMd: 8.0,
    radiusLg: 10.0,
    radiusPill: 20.0,
  );
}

/// A fixture whose every field differs from [_fixture]. Used to verify that
/// copyWith maps each named argument onto the matching field.
TwmtThemeTokens _otherFixture() {
  return const TwmtThemeTokens(
    bg: Color(0xFF010101),
    panel: Color(0xFF020202),
    panel2: Color(0xFF030303),
    border: Color(0xFF040404),
    text: Color(0xFF050505),
    textMid: Color(0xFF060606),
    textDim: Color(0xFF070707),
    textFaint: Color(0xFF080808),
    accent: Color(0xFF090909),
    accentFg: Color(0xFF0A0A0A),
    accentBg: Color(0xFF0B0B0B),
    ok: Color(0xFF0C0C0C),
    okBg: Color(0xFF0D0D0D),
    warn: Color(0xFF0E0E0E),
    warnBg: Color(0xFF0F0F0F),
    err: Color(0xFF101010),
    errBg: Color(0xFF111112),
    info: Color(0xFF121212),
    infoBg: Color(0xFF131313),
    llm: Color(0xFF141414),
    llmBg: Color(0xFF151515),
    rowSelected: Color(0xFF161616),
    fontBody: TextStyle(fontFamily: 'OtherBody'),
    fontDisplay: TextStyle(fontFamily: 'OtherDisplay'),
    fontMono: TextStyle(fontFamily: 'OtherMono'),
    fontDisplayItalic: true,
    radiusXs: 1.0,
    radiusSm: 2.0,
    radiusMd: 5.0,
    radiusLg: 7.0,
    radiusPill: 9.0,
  );
}

void main() {
  group('TwmtThemeTokens.fontDisplayStyle', () {
    test('is FontStyle.italic when fontDisplayItalic is true', () {
      final tokens = _fixture().copyWith(fontDisplayItalic: true);
      expect(tokens.fontDisplayStyle, FontStyle.italic);
    });

    test('is FontStyle.normal when fontDisplayItalic is false', () {
      final tokens = _fixture().copyWith(fontDisplayItalic: false);
      expect(tokens.fontDisplayStyle, FontStyle.normal);
    });
  });

  group('TwmtThemeTokens.hashCode', () {
    test('is equal for value-equal instances', () {
      expect(_fixture().hashCode, _fixture().hashCode);
    });

    test('differs when any single field differs', () {
      final base = _fixture();
      expect(
        base.hashCode,
        isNot(base.copyWith(accent: const Color(0xFF010203)).hashCode),
      );
      expect(
        base.hashCode,
        isNot(base.copyWith(radiusPill: 99.0).hashCode),
      );
      expect(
        base.hashCode,
        isNot(base.copyWith(fontDisplayItalic: true).hashCode),
      );
    });
  });

  group('TwmtThemeTokens.operator ==', () {
    test('returns true for the identical instance', () {
      final tokens = _fixture();
      expect(tokens == tokens, isTrue);
    });

    test('returns false when compared to a different runtime type', () {
      // ignore: unrelated_type_equality_checks
      expect(_fixture() == Object(), isFalse);
    });

    test('returns false when a colour field differs', () {
      final base = _fixture();
      expect(base == base.copyWith(bg: const Color(0xFF000001)), isFalse);
      expect(base == base.copyWith(rowSelected: const Color(0xFF000001)),
          isFalse);
    });

    test('returns false when typography or radius fields differ', () {
      final base = _fixture();
      expect(
        base == base.copyWith(fontBody: const TextStyle(fontFamily: 'Z')),
        isFalse,
      );
      expect(base == base.copyWith(fontDisplayItalic: true), isFalse);
      expect(base == base.copyWith(radiusMd: 99.0), isFalse);
    });
  });

  group('TwmtThemeTokens.copyWith', () {
    test('with no arguments returns a value-equal instance', () {
      final base = _fixture();
      expect(base.copyWith(), equals(base));
    });

    test('maps every named argument onto the matching field', () {
      final base = _fixture();
      final other = _otherFixture();
      final merged = base.copyWith(
        bg: other.bg,
        panel: other.panel,
        panel2: other.panel2,
        border: other.border,
        text: other.text,
        textMid: other.textMid,
        textDim: other.textDim,
        textFaint: other.textFaint,
        accent: other.accent,
        accentFg: other.accentFg,
        accentBg: other.accentBg,
        ok: other.ok,
        okBg: other.okBg,
        warn: other.warn,
        warnBg: other.warnBg,
        err: other.err,
        errBg: other.errBg,
        info: other.info,
        infoBg: other.infoBg,
        llm: other.llm,
        llmBg: other.llmBg,
        rowSelected: other.rowSelected,
        fontBody: other.fontBody,
        fontDisplay: other.fontDisplay,
        fontMono: other.fontMono,
        fontDisplayItalic: other.fontDisplayItalic,
        radiusXs: other.radiusXs,
        radiusSm: other.radiusSm,
        radiusMd: other.radiusMd,
        radiusLg: other.radiusLg,
        radiusPill: other.radiusPill,
      );
      expect(merged, equals(other));
    });
  });

  group('TwmtThemeTokens.lerp', () {
    test('returns the receiver unchanged for a null / non-matching other', () {
      final base = _fixture();
      final result = base.lerp(null, 0.5);
      expect(identical(result, base), isTrue);
    });

    test('interpolates radii and snaps typography at the midpoint', () {
      final a = _fixture(); // radiusMd 8.0, fontDisplayItalic false
      final b = a.copyWith(
        radiusMd: 16.0,
        fontDisplayItalic: true,
        fontBody: const TextStyle(fontFamily: 'Snap'),
      );

      // t < 0.5: radii interpolate, typography snaps to the receiver.
      final low = a.lerp(b, 0.25);
      expect(low.radiusMd, 8.0 + (16.0 - 8.0) * 0.25); // 10.0
      expect(low.fontDisplayItalic, a.fontDisplayItalic);
      expect(low.fontBody, a.fontBody);

      // t >= 0.5: radii interpolate, typography snaps to the other endpoint.
      final high = a.lerp(b, 0.75);
      expect(high.radiusMd, 8.0 + (16.0 - 8.0) * 0.75); // 14.0
      expect(high.fontDisplayItalic, b.fontDisplayItalic);
      expect(high.fontBody, b.fontBody);
    });

    test('interpolates every radius token', () {
      final a = _fixture();
      final b = a.copyWith(
        radiusXs: 13.0,
        radiusSm: 14.0,
        radiusMd: 18.0,
        radiusLg: 20.0,
        radiusPill: 40.0,
      );
      final mid = a.lerp(b, 0.5);
      expect(mid.radiusXs, (a.radiusXs + b.radiusXs) / 2);
      expect(mid.radiusSm, (a.radiusSm + b.radiusSm) / 2);
      expect(mid.radiusMd, (a.radiusMd + b.radiusMd) / 2);
      expect(mid.radiusLg, (a.radiusLg + b.radiusLg) / 2);
      expect(mid.radiusPill, (a.radiusPill + b.radiusPill) / 2);
    });
  });

  group('TwmtTokensAccess.tokens', () {
    testWidgets('asserts when the extension is missing from the theme',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(), // deliberately no TwmtThemeTokens extension
          home: Builder(
            builder: (context) {
              expect(() => context.tokens, throwsA(isA<AssertionError>()));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('returns the registered extension when present', (tester) async {
      final fixture = _fixture();
      TwmtThemeTokens? resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(extensions: [fixture]),
          home: Builder(
            builder: (context) {
              resolved = context.tokens;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved, equals(fixture));
    });
  });
}
