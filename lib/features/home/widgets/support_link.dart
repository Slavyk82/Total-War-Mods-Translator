import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// "Buy me a beer" support card shown at the bottom of the Home screen.
///
/// Mimics the Buy Me a Coffee branded button (yellow background, beer emoji,
/// black text) while staying consistent with TWMT's design tokens, and pairs
/// it with a short note explaining why a contribution would be appreciated.
class SupportLink extends StatelessWidget {
  const SupportLink({super.key});

  static const String _url = 'https://buymeacoffee.com/slavyk';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'If TWMT made your modding life easier, keeping '
                    'translations tidy and surviving every mod update, a '
                    'small tip would be hugely appreciated and helps me '
                    'keep improving it!',
                    textAlign: TextAlign.center,
                    style: tokens.fontBody.copyWith(
                      fontSize: 13,
                      height: 1.5,
                      color: tokens.textDim,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _BuyMeABeerButton(),
                ],
              ),
            ),
          ),
          const SizedBox(width: 22),
          const _GoblinAvatar(),
        ],
      ),
    );
  }
}

/// Circular goblin avatar framed with a fantasy-style ring built from the
/// theme's accent colour (a soft glow + a gold-tone gradient stroke separated
/// from the portrait by a thin background gap, mimicking an engraved coin).
class _GoblinAvatar extends StatelessWidget {
  const _GoblinAvatar();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: tokens.accent.withValues(alpha: 0.32),
            blurRadius: 14,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tokens.accent,
              tokens.accent.withValues(alpha: 0.55),
            ],
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tokens.bg,
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/slavyk.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

class _BuyMeABeerButton extends StatefulWidget {
  const _BuyMeABeerButton();

  @override
  State<_BuyMeABeerButton> createState() => _BuyMeABeerButtonState();
}

class _BuyMeABeerButtonState extends State<_BuyMeABeerButton> {
  static const Color _bmcYellow = Color(0xFFFFDD00);
  static const Color _bmcOutline = Color(0xFF000000);

  bool _hovered = false;
  bool _pressed = false;

  Future<void> _open() async {
    final uri = Uri.parse(SupportLink._url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final scale = _pressed ? 0.97 : (_hovered ? 1.02 : 1.0);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _open,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: _bmcYellow,
              borderRadius: BorderRadius.circular(tokens.radiusPill),
              border: Border.all(color: _bmcOutline, width: 1),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: _bmcOutline.withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '🍺',
                  style: TextStyle(fontSize: 18, height: 1.0),
                ),
                const SizedBox(width: 10),
                Text(
                  'Buy me a beer :-)',
                  style: tokens.fontDisplay.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _bmcOutline,
                    letterSpacing: 0.2,
                    fontStyle: FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
