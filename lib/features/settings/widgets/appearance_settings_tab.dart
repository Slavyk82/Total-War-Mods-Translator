import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/providers/theme_name_provider.dart';
import 'package:twmt/theme/tokens/atelier_tokens.dart';
import 'package:twmt/theme/tokens/forge_tokens.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Settings tab letting the user pick Atelier or Forge.
///
/// Two preview cards; clicking a card sets the active palette
/// through the [themeNameProvider].
class AppearanceSettingsTab extends ConsumerWidget {
  const AppearanceSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeNameAsync = ref.watch(themeNameProvider);
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Appearance',
            style: tokens.fontDisplay.copyWith(
              fontSize: 22,
              color: tokens.accent,
              fontStyle: tokens.fontDisplayStyle,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Settings > Appearance - applied live.',
            style: tokens.fontMono.copyWith(
              fontSize: 12,
              color: tokens.textDim,
            ),
          ),
          const SizedBox(height: 26),
          themeNameAsync.when(
            data: (active) => _PaletteChoices(active: active),
            loading: () => const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => Text('Error: $err',
                style: TextStyle(color: tokens.err)),
          ),
        ],
      ),
    );
  }
}

class _PaletteChoices extends ConsumerWidget {
  const _PaletteChoices({required this.active});

  final TwmtThemeName active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _PaletteCard(
            name: TwmtThemeName.atelier,
            label: 'Atelier',
            tokens: atelierTokens,
            isActive: active == TwmtThemeName.atelier,
            onTap: () => ref
                .read(themeNameProvider.notifier)
                .setThemeName(TwmtThemeName.atelier),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _PaletteCard(
            name: TwmtThemeName.forge,
            label: 'Forge',
            tokens: forgeTokens,
            isActive: active == TwmtThemeName.forge,
            onTap: () => ref
                .read(themeNameProvider.notifier)
                .setThemeName(TwmtThemeName.forge),
          ),
        ),
      ],
    );
  }
}

class _PaletteCard extends StatelessWidget {
  const _PaletteCard({
    required this.name,
    required this.label,
    required this.tokens,
    required this.isActive,
    required this.onTap,
  });

  final TwmtThemeName name;
  final String label;
  final TwmtThemeTokens tokens;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = context.tokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(active.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isActive ? active.accentBg : active.panel2,
            border: Border.all(
              color: isActive ? active.accent : active.border,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(active.radiusLg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _PalettePreview(tokens: tokens),
              const SizedBox(width: 16),
              Expanded(
                child: Text(label,
                    style: active.fontBody.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: active.text,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PalettePreview extends StatelessWidget {
  const _PalettePreview({required this.tokens});

  final TwmtThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    final active = context.tokens;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(active.radiusMd),
        border: Border.all(color: active.border, width: 1),
        gradient: LinearGradient(
          colors: [tokens.bg, tokens.bg, tokens.accent, tokens.accent],
          stops: const [0.0, 0.5, 0.5, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}
