import 'package:flutter/material.dart';

/// Design tokens for TWMT themes.
///
/// A single [ThemeExtension] that carries every colour and typography token
/// required by the redesigned UI. Two static instances (`atelier`, `forge`)
/// live in `lib/theme/tokens/`.
///
/// Consume via `context.tokens` (see the extension at the bottom of this file).
class TwmtThemeTokens extends ThemeExtension<TwmtThemeTokens> {
  const TwmtThemeTokens({
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.border,
    required this.text,
    required this.textMid,
    required this.textDim,
    required this.textFaint,
    required this.accent,
    required this.accentFg,
    required this.accentBg,
    required this.ok,
    required this.okBg,
    required this.warn,
    required this.warnBg,
    required this.err,
    required this.errBg,
    required this.llm,
    required this.llmBg,
    required this.rowSelected,
    required this.fontBody,
    required this.fontDisplay,
    required this.fontMono,
    required this.fontDisplayItalic,
    required this.radiusXs,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.radiusPill,
  });

  // ---------- Palette ----------
  final Color bg;
  final Color panel;
  final Color panel2;
  final Color border;
  final Color text;
  final Color textMid;
  final Color textDim;
  final Color textFaint;
  final Color accent;
  final Color accentFg;
  final Color accentBg;
  final Color ok;
  final Color okBg;
  final Color warn;
  final Color warnBg;
  final Color err;
  final Color errBg;
  final Color llm;
  final Color llmBg;
  final Color rowSelected;

  // ---------- Typography ----------
  /// Base body font, already wired to a variable-weight TextStyle.
  final TextStyle fontBody;

  /// Display font used for page / section titles. In Forge this is the same
  /// family as body at weight 500; in Atelier it is Instrument Serif italic.
  final TextStyle fontDisplay;

  /// Monospace font used for keys, paths, kbd hints, tabular numerics.
  final TextStyle fontMono;

  /// Whether the display font expects `FontStyle.italic` when rendered.
  /// Forge sets this to `false` to avoid a pseudo-italic when the family
  /// doesn't ship an italic cut.
  final bool fontDisplayItalic;

  // ---------- Radius ----------
  final double radiusXs;
  final double radiusSm;
  final double radiusMd;
  final double radiusLg;
  final double radiusPill;

  @override
  TwmtThemeTokens copyWith({
    Color? bg,
    Color? panel,
    Color? panel2,
    Color? border,
    Color? text,
    Color? textMid,
    Color? textDim,
    Color? textFaint,
    Color? accent,
    Color? accentFg,
    Color? accentBg,
    Color? ok,
    Color? okBg,
    Color? warn,
    Color? warnBg,
    Color? err,
    Color? errBg,
    Color? llm,
    Color? llmBg,
    Color? rowSelected,
    TextStyle? fontBody,
    TextStyle? fontDisplay,
    TextStyle? fontMono,
    bool? fontDisplayItalic,
    double? radiusXs,
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? radiusPill,
  }) {
    return TwmtThemeTokens(
      bg: bg ?? this.bg,
      panel: panel ?? this.panel,
      panel2: panel2 ?? this.panel2,
      border: border ?? this.border,
      text: text ?? this.text,
      textMid: textMid ?? this.textMid,
      textDim: textDim ?? this.textDim,
      textFaint: textFaint ?? this.textFaint,
      accent: accent ?? this.accent,
      accentFg: accentFg ?? this.accentFg,
      accentBg: accentBg ?? this.accentBg,
      ok: ok ?? this.ok,
      okBg: okBg ?? this.okBg,
      warn: warn ?? this.warn,
      warnBg: warnBg ?? this.warnBg,
      err: err ?? this.err,
      errBg: errBg ?? this.errBg,
      llm: llm ?? this.llm,
      llmBg: llmBg ?? this.llmBg,
      rowSelected: rowSelected ?? this.rowSelected,
      fontBody: fontBody ?? this.fontBody,
      fontDisplay: fontDisplay ?? this.fontDisplay,
      fontMono: fontMono ?? this.fontMono,
      fontDisplayItalic: fontDisplayItalic ?? this.fontDisplayItalic,
      radiusXs: radiusXs ?? this.radiusXs,
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusLg: radiusLg ?? this.radiusLg,
      radiusPill: radiusPill ?? this.radiusPill,
    );
  }

  @override
  TwmtThemeTokens lerp(ThemeExtension<TwmtThemeTokens>? other, double t) {
    if (other is! TwmtThemeTokens) return this;
    return TwmtThemeTokens(
      bg: Color.lerp(bg, other.bg, t) ?? bg,
      panel: Color.lerp(panel, other.panel, t) ?? panel,
      panel2: Color.lerp(panel2, other.panel2, t) ?? panel2,
      border: Color.lerp(border, other.border, t) ?? border,
      text: Color.lerp(text, other.text, t) ?? text,
      textMid: Color.lerp(textMid, other.textMid, t) ?? textMid,
      textDim: Color.lerp(textDim, other.textDim, t) ?? textDim,
      textFaint: Color.lerp(textFaint, other.textFaint, t) ?? textFaint,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      accentFg: Color.lerp(accentFg, other.accentFg, t) ?? accentFg,
      accentBg: Color.lerp(accentBg, other.accentBg, t) ?? accentBg,
      ok: Color.lerp(ok, other.ok, t) ?? ok,
      okBg: Color.lerp(okBg, other.okBg, t) ?? okBg,
      warn: Color.lerp(warn, other.warn, t) ?? warn,
      warnBg: Color.lerp(warnBg, other.warnBg, t) ?? warnBg,
      err: Color.lerp(err, other.err, t) ?? err,
      errBg: Color.lerp(errBg, other.errBg, t) ?? errBg,
      llm: Color.lerp(llm, other.llm, t) ?? llm,
      llmBg: Color.lerp(llmBg, other.llmBg, t) ?? llmBg,
      rowSelected:
          Color.lerp(rowSelected, other.rowSelected, t) ?? rowSelected,
      // Typography is not lerped — snap at t>=0.5.
      fontBody: t < 0.5 ? fontBody : other.fontBody,
      fontDisplay: t < 0.5 ? fontDisplay : other.fontDisplay,
      fontMono: t < 0.5 ? fontMono : other.fontMono,
      fontDisplayItalic:
          t < 0.5 ? fontDisplayItalic : other.fontDisplayItalic,
      radiusXs: _lerpDouble(radiusXs, other.radiusXs, t),
      radiusSm: _lerpDouble(radiusSm, other.radiusSm, t),
      radiusMd: _lerpDouble(radiusMd, other.radiusMd, t),
      radiusLg: _lerpDouble(radiusLg, other.radiusLg, t),
      radiusPill: _lerpDouble(radiusPill, other.radiusPill, t),
    );
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TwmtThemeTokens) return false;
    return bg == other.bg &&
        panel == other.panel &&
        panel2 == other.panel2 &&
        border == other.border &&
        text == other.text &&
        textMid == other.textMid &&
        textDim == other.textDim &&
        textFaint == other.textFaint &&
        accent == other.accent &&
        accentFg == other.accentFg &&
        accentBg == other.accentBg &&
        ok == other.ok &&
        okBg == other.okBg &&
        warn == other.warn &&
        warnBg == other.warnBg &&
        err == other.err &&
        errBg == other.errBg &&
        llm == other.llm &&
        llmBg == other.llmBg &&
        rowSelected == other.rowSelected &&
        fontBody == other.fontBody &&
        fontDisplay == other.fontDisplay &&
        fontMono == other.fontMono &&
        fontDisplayItalic == other.fontDisplayItalic &&
        radiusXs == other.radiusXs &&
        radiusSm == other.radiusSm &&
        radiusMd == other.radiusMd &&
        radiusLg == other.radiusLg &&
        radiusPill == other.radiusPill;
  }

  @override
  int get hashCode => Object.hashAll([
        bg, panel, panel2, border,
        text, textMid, textDim, textFaint,
        accent, accentFg, accentBg,
        ok, okBg, warn, warnBg, err, errBg, llm, llmBg,
        rowSelected,
        fontBody, fontDisplay, fontMono, fontDisplayItalic,
        radiusXs, radiusSm, radiusMd, radiusLg, radiusPill,
      ]);
}

/// Access the active [TwmtThemeTokens] from a [BuildContext].
///
/// Throws if no [TwmtThemeTokens] extension is registered on the current
/// theme — callers should never guard for `null` because every app theme
/// is expected to carry this extension.
extension TwmtTokensAccess on BuildContext {
  /// Active [TwmtThemeTokens] for this build context.
  ///
  /// Every TWMT `ThemeData` is expected to carry a [TwmtThemeTokens] extension.
  /// If this fires in debug mode, the most common cause is a dialog or overlay
  /// built under a sub-tree without the app `Theme` in its ancestry — make sure
  /// the route inherits the main `MaterialApp` theme.
  TwmtThemeTokens get tokens {
    final ext = Theme.of(this).extension<TwmtThemeTokens>();
    assert(
      ext != null,
      'TwmtThemeTokens missing from Theme. Register via ThemeData.extensions. '
      'If this fires inside a dialog/overlay, ensure that subtree inherits the '
      'main app theme.',
    );
    return ext!;
  }
}
