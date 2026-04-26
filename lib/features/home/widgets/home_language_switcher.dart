import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/i18n/app_locale_info.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/app_locale_provider.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Discrete app-UI language switcher for the Home screen.
///
/// Renders only the flag pill of the currently active locale and opens a
/// popup menu with the supported locales when tapped.
class HomeLanguageSwitcher extends ConsumerWidget {
  const HomeLanguageSwitcher({super.key});

  static const double _flagWidth = 44;
  static const double _flagHeight = 32;
  static const double _menuFlagWidth = 22;
  static const double _menuFlagHeight = 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final selectedAsync = ref.watch(appLocaleProvider);
    final selected = selectedAsync.value ?? AppLocale.en;
    final selectedInfo = infoFor(selected);

    return Tooltip(
      message: t.app.language.label,
      child: PopupMenuButton<AppLocale>(
        tooltip: '',
        position: PopupMenuPosition.under,
        padding: EdgeInsets.zero,
        onSelected: (locale) async {
          await LocaleSettings.setLocale(locale);
          await ref.read(appLocaleProvider.notifier).setLocale(locale);
        },
        itemBuilder: (context) => supportedLocales.map((locale) {
          final info = infoFor(locale);
          return PopupMenuItem<AppLocale>(
            value: locale,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (info.flagAsset != null) ...[
                  Image.asset(
                    info.flagAsset!,
                    width: _menuFlagWidth,
                    height: _menuFlagHeight,
                    errorBuilder: (ctx, err, st) =>
                        const SizedBox(width: _menuFlagWidth),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(info.nativeName, style: tokens.fontBody),
              ],
            ),
          );
        }).toList(),
        child: selectedInfo.flagAsset != null
            ? Image.asset(
                selectedInfo.flagAsset!,
                width: _flagWidth,
                height: _flagHeight,
                errorBuilder: (ctx, err, st) => Text(
                  selected.languageCode.toUpperCase(),
                  style: tokens.fontBody.copyWith(fontSize: 12),
                ),
              )
            : Text(
                selected.languageCode.toUpperCase(),
                style: tokens.fontBody.copyWith(fontSize: 12),
              ),
      ),
    );
  }
}
