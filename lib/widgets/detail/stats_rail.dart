import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Semantic colour variants for [StatsRailRow] values and [StatsRailHint]
/// kickers. Resolved to token colours by [_resolveForeground].
enum StatsSemantics { neutral, accent, ok, warn, err }

Color _resolveForeground(TwmtThemeTokens tokens, StatsSemantics s) {
  return switch (s) {
    StatsSemantics.neutral => tokens.text,
    StatsSemantics.accent => tokens.accent,
    StatsSemantics.ok => tokens.ok,
    StatsSemantics.warn => tokens.warn,
    StatsSemantics.err => tokens.err,
  };
}

Color _resolveBackground(TwmtThemeTokens tokens, StatsSemantics s) {
  return switch (s) {
    StatsSemantics.neutral => tokens.panel2,
    StatsSemantics.accent => tokens.accentBg,
    StatsSemantics.ok => tokens.okBg,
    StatsSemantics.warn => tokens.warnBg,
    StatsSemantics.err => tokens.errBg,
  };
}

/// A single row inside a [StatsRailSection].
class StatsRailRow {
  final String label;
  final String value;
  final StatsSemantics semantics;

  const StatsRailRow({
    required this.label,
    required this.value,
    this.semantics = StatsSemantics.neutral,
  });
}

/// A labelled group of rows inside a [StatsRail].
class StatsRailSection {
  final String label;
  final List<StatsRailRow> rows;

  const StatsRailSection({required this.label, required this.rows});
}

/// Actionable hint rendered at the bottom of a [StatsRail].
class StatsRailHint {
  final String kicker;
  final String message;
  final StatsSemantics semantics;
  final VoidCallback? onTap;

  const StatsRailHint({
    required this.kicker,
    required this.message,
    this.semantics = StatsSemantics.warn,
    this.onTap,
  });
}

/// Right-column rail used by detail screens (§7.2).
///
/// Stacks: optional [header] · 1..N [sections] · optional [hint].
class StatsRail extends StatelessWidget {
  final Widget? header;
  final List<StatsRailSection> sections;
  final StatsRailHint? hint;

  const StatsRail({
    super.key,
    this.header,
    required this.sections,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null) ...[
            header!,
            const SizedBox(height: 14),
            Container(height: 1, color: tokens.border),
            const SizedBox(height: 14),
          ],
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 12),
              Container(height: 1, color: tokens.border),
              const SizedBox(height: 12),
            ],
            _Section(section: sections[i]),
          ],
          if (hint != null) ...[
            const SizedBox(height: 16),
            _Hint(hint: hint!),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final StatsRailSection section;
  const _Section({required this.section});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          section.label.toUpperCase(),
          style: tokens.fontMono.copyWith(
            fontSize: 10,
            color: tokens.textDim,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        for (final row in section.rows) _Row(row: row),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final StatsRailRow row;
  const _Row({required this.row});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              row.label,
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.textMid,
              ),
            ),
          ),
          Text(
            row.value,
            style: tokens.fontMono.copyWith(
              fontSize: 12,
              color: _resolveForeground(tokens, row.semantics),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final StatsRailHint hint;
  const _Hint({required this.hint});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fg = _resolveForeground(tokens, hint.semantics);
    final bg = _resolveBackground(tokens, hint.semantics);
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border(left: BorderSide(color: fg, width: 2)),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hint.kicker.toUpperCase(),
            style: tokens.fontMono.copyWith(
              fontSize: 10,
              color: fg,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hint.message,
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: tokens.text,
            ),
          ),
        ],
      ),
    );
    if (hint.onTap == null) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: hint.onTap, child: body),
    );
  }
}
