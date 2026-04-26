import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/i18n/app_locale_info.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/app_locale_provider.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'settings_section_header.dart';

/// Application-UI language picker.
///
/// Distinct from `LanguagePreferencesSection`, which manages the languages
/// the user's mods are translated INTO. This section controls the language
/// the TWMT UI itself is rendered in.
class AppLanguageSection extends ConsumerWidget {
  const AppLanguageSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final selectedAsync = ref.watch(appLocaleProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(
          title: t.app.language.title,
          subtitle: t.app.language.subtitle,
        ),
        const SizedBox(height: 16),
        selectedAsync.when(
          loading: () => const SizedBox(
            height: 48,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text(
            '${t.common.error}: $e',
            style: tokens.fontBody.copyWith(color: tokens.err),
          ),
          data: (selected) => _Dropdown(selected: selected),
        ),
      ],
    );
  }
}

class _Dropdown extends ConsumerWidget {
  final AppLocale selected;

  const _Dropdown({required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;

    return DropdownButtonFormField<AppLocale?>(
      initialValue: selected,
      decoration: InputDecoration(
        labelText: t.app.language.label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: <DropdownMenuItem<AppLocale?>>[
        DropdownMenuItem<AppLocale?>(
          value: null,
          child: Text(t.app.language.systemDefault),
        ),
        ...supportedLocales.map((locale) {
          final info = infoFor(locale);
          return DropdownMenuItem<AppLocale?>(
            value: locale,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (info.flagAsset != null) ...[
                  Image.asset(
                    info.flagAsset!,
                    width: 20,
                    height: 14,
                    errorBuilder: (ctx, err, st) => const SizedBox(width: 20),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(info.nativeName, style: tokens.fontBody),
              ],
            ),
          );
        }),
      ],
      onChanged: (locale) async {
        // Update slang's runtime first so the global `t` already points at
        // the new translations by the time the locale-driven app rebuild
        // (triggered by the Riverpod state change below) reads them.
        if (locale != null) {
          await LocaleSettings.setLocale(locale);
        } else {
          await LocaleSettings.useDeviceLocale();
        }
        await ref.read(appLocaleProvider.notifier).setLocale(locale);
      },
    );
  }
}
