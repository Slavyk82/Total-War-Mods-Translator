import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/features/settings/widgets/language_settings_datagrid.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/providers/language_settings_providers.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

class _FakeLanguageSettings extends LanguageSettings {
  _FakeLanguageSettings(this._build);

  final Future<LanguageSettingsState> Function() _build;

  @override
  Future<LanguageSettingsState> build() => _build();
}

Language _lang(String code) => Language(
      id: 'id-$code',
      code: code,
      name: code.toUpperCase(),
      nativeName: code,
    );

Future<void> _pump(
  WidgetTester tester,
  Future<LanguageSettingsState> Function() build,
) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        languageSettingsProvider.overrideWith(() => _FakeLanguageSettings(build)),
      ],
      child: MaterialApp(
        theme: ThemeData.light().copyWith(extensions: [slateTokens]),
        home: const Scaffold(body: LanguageSettingsDataGrid()),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a spinner while loading', (tester) async {
    final never = Completer<LanguageSettingsState>();
    await _pump(tester, () => never.future);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the error state when loading fails', (tester) async {
    await _pump(tester, () async => throw Exception('boom'));
    await tester.pumpAndSettle();

    expect(
      find.text(t.settings.general.languagePreferences.grid.errorTitle),
      findsOneWidget,
    );
  });

  testWidgets('shows the empty state when there are no languages',
      (tester) async {
    await _pump(
      tester,
      () async => const LanguageSettingsState(
        languages: [],
        defaultLanguageCode: 'en',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(t.settings.general.languagePreferences.grid.emptyTitle),
      findsOneWidget,
    );
  });

  testWidgets('renders the grid with column headers when languages exist',
      (tester) async {
    await _pump(
      tester,
      () async => LanguageSettingsState(
        languages: [_lang('en'), _lang('fr')],
        defaultLanguageCode: 'en',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SfDataGrid), findsOneWidget);
    expect(
      find.text(t.settings.general.languagePreferences.grid.columnCode),
      findsOneWidget,
    );
    expect(
      find.text(t.settings.general.languagePreferences.grid.columnLanguage),
      findsOneWidget,
    );
  });
}
