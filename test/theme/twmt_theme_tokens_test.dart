import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

// Plain TextStyle fixtures are used instead of GoogleFonts.* factories because
// google_fonts triggers runtime HTTP fetches (or asset lookups) even when the
// returned TextStyle is never rendered, which breaks hermetic unit tests.
// TwmtThemeTokens only cares about receiving TextStyle values — the concrete
// font source is irrelevant to the behaviour exercised here.
const TextStyle _bodyFont = TextStyle(fontFamily: 'TestBody');
const TextStyle _displayFont = TextStyle(fontFamily: 'TestDisplay');
const TextStyle _monoFont = TextStyle(fontFamily: 'TestMono');

TwmtThemeTokens _fixture() {
  return const TwmtThemeTokens(
    bg: Color(0xFF111111),
    panel: Color(0xFF222222),
    panel2: Color(0xFF333333),
    border: Color(0xFF444444),
    text: Color(0xFFAAAAAA),
    textMid: Color(0xFF888888),
    textDim: Color(0xFF666666),
    textFaint: Color(0xFF444444),
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

void main() {
  group('TwmtThemeTokens', () {
    test('equality is based on values', () {
      final a = _fixture();
      final b = _fixture();
      expect(a, equals(b));
    });

    test('copyWith overrides only the supplied field', () {
      final base = _fixture();
      final modified =
          base.copyWith(accent: const Color(0xFF112233));
      expect(modified.accent, const Color(0xFF112233));
      expect(modified.bg, base.bg);
      expect(modified.text, base.text);
      expect(modified.fontBody, base.fontBody);
    });

    test('lerp at t=0 returns the receiver unchanged', () {
      final a = _fixture();
      final b = a.copyWith(accent: const Color(0xFF112233));
      final lerped = a.lerp(b, 0.0);
      expect(lerped.accent, a.accent);
    });

    test('lerp at t=1 returns the other', () {
      final a = _fixture();
      final b = a.copyWith(accent: const Color(0xFF112233));
      final lerped = a.lerp(b, 1.0);
      expect(lerped.accent, b.accent);
    });

    test('copyWith overrides info and infoBg independently', () {
      final base = _fixture();
      final modified = base.copyWith(
        info: const Color(0xFF11AAFF),
        infoBg: const Color(0xFF001133),
      );
      expect(modified.info, const Color(0xFF11AAFF));
      expect(modified.infoBg, const Color(0xFF001133));
      expect(modified.bg, base.bg);
      expect(modified.accent, base.accent);
    });

    test('lerp interpolates the info pair between endpoints', () {
      final a = _fixture();
      final b = a.copyWith(
        info: const Color(0xFF11AAFF),
        infoBg: const Color(0xFF001133),
      );
      final lerped = a.lerp(b, 0.5);
      expect(lerped.info, Color.lerp(a.info, b.info, 0.5));
      expect(lerped.infoBg, Color.lerp(a.infoBg, b.infoBg, 0.5));
    });
  });

  testWidgets('context.tokens returns the active extension', (tester) async {
    final captured = <TwmtThemeTokens>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: [_fixture()],
        ),
        home: Builder(
          builder: (context) {
            captured.add(context.tokens);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(captured, hasLength(1));
    expect(captured.single.accent, _fixture().accent);
  });
}
