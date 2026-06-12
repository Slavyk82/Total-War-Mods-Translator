import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/features/settings/providers/ignored_source_texts_providers.dart';
import 'package:twmt/features/settings/widgets/ignored_source_texts_datagrid.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/domain/ignored_source_text.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';
import 'package:twmt/widgets/common/fluent_spinner.dart';

class _FakeIgnored extends IgnoredSourceTexts {
  _FakeIgnored(this._build);

  final Future<List<IgnoredSourceText>> Function() _build;

  @override
  Future<List<IgnoredSourceText>> build() => _build();
}

IgnoredSourceText _text(String source) => IgnoredSourceText(
      id: 'id-$source',
      sourceText: source,
      createdAt: 0,
      updatedAt: 0,
    );

Future<void> _pump(
  WidgetTester tester,
  Future<List<IgnoredSourceText>> Function() build,
) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ignoredSourceTextsProvider.overrideWith(() => _FakeIgnored(build)),
      ],
      child: MaterialApp(
        theme: ThemeData.light().copyWith(extensions: [slateTokens]),
        home: const Scaffold(body: IgnoredSourceTextsDataGrid()),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a spinner while loading', (tester) async {
    final never = Completer<List<IgnoredSourceText>>();
    await _pump(tester, () => never.future);
    await tester.pump();

    expect(find.byType(FluentSpinner), findsOneWidget);
  });

  testWidgets('shows the error state when loading fails', (tester) async {
    await _pump(tester, () async => throw Exception('boom'));
    await tester.pumpAndSettle();

    expect(find.text(t.settings.ignoredTexts.grid.errorTitle), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no texts', (tester) async {
    await _pump(tester, () async => <IgnoredSourceText>[]);
    await tester.pumpAndSettle();

    expect(find.text(t.settings.ignoredTexts.grid.emptyTitle), findsOneWidget);
  });

  testWidgets('renders the grid with column headers when texts exist',
      (tester) async {
    await _pump(tester, () async => [_text('foo'), _text('bar')]);
    await tester.pumpAndSettle();

    expect(find.byType(SfDataGrid), findsOneWidget);
    expect(find.text(t.settings.ignoredTexts.grid.columnSourceText),
        findsOneWidget);
  });
}
