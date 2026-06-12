import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/settings/widgets/general/app_language_section.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/app_locale_provider.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

/// Fake notifier letting each test drive the [appLocaleProvider] async state
/// (data / loading / error) without touching SharedPreferences.
class _FakeAppLocale extends AppLocaleNotifier {
  _FakeAppLocale(this._build);

  final Future<AppLocale> Function() _build;

  @override
  Future<AppLocale> build() => _build();
}

Widget _host(Future<AppLocale> Function() build) => ProviderScope(
      overrides: [
        appLocaleProvider.overrideWith(() => _FakeAppLocale(build)),
      ],
      child: MaterialApp(
        theme: ThemeData.light().copyWith(extensions: [slateTokens]),
        home: const Scaffold(
          body: SizedBox(width: 600, child: AppLanguageSection()),
        ),
      ),
    );

void main() {
  testWidgets('shows a progress indicator while the locale is loading',
      (tester) async {
    final never = Completer<AppLocale>(); // never completes -> stays loading
    await tester.pumpWidget(_host(() => never.future));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows an error message when loading the locale fails',
      (tester) async {
    await tester.pumpWidget(_host(() async => throw Exception('boom')));
    await tester.pumpAndSettle();

    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<AppLocale?>), findsNothing);
  });

  testWidgets('renders the locale dropdown with a system-default entry',
      (tester) async {
    await tester.pumpWidget(_host(() async => AppLocale.en));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<AppLocale?>), findsOneWidget);

    // Opening the menu surfaces the "system default" option.
    await tester.tap(find.byType(DropdownButtonFormField<AppLocale?>));
    await tester.pumpAndSettle();

    expect(find.text(t.app.language.systemDefault), findsWidgets);
  });
}
