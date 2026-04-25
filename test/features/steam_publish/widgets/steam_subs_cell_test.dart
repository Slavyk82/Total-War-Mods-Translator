import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:twmt/features/steam_publish/providers/published_subs_cache_provider.dart';
import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';
import 'package:twmt/features/steam_publish/widgets/steam_publish_list_cells.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

ProjectPublishItem _project({String? publishedSteamId}) => ProjectPublishItem(
      export: null,
      project: Project(
        id: 'p1',
        name: 'P1',
        gameInstallationId: 'g',
        createdAt: 0,
        updatedAt: 0,
        publishedSteamId: publishedSteamId,
        publishedAt: publishedSteamId != null ? 1_700_000_000 : null,
      ),
      languageCodes: const ['en'],
    );

void main() {
  setUp(() async => TestBootstrap.registerFakes());

  testWidgets('SteamSubsCell shows "-" and unpublished tooltip when item is unpublished',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      SteamSubsCell(item: _project()),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('-'), findsOneWidget);

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, 'Not published to the Workshop yet.');
  });

  testWidgets('SteamSubsCell shows "-" when published but cache has no entry',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      SteamSubsCell(item: _project(publishedSteamId: '999')),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('-'), findsOneWidget);

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, 'Workshop subscribers — last refreshed at app start.');
  });

  testWidgets('SteamSubsCell formats the count with non-breaking spaces',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        publishedSubsCacheProvider.overrideWith(
          () => _StubCache({'42': 1234}),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: SteamSubsCell(item: _project(publishedSteamId: '42')),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 234'), findsOneWidget);
  });

  testWidgets(
      'SteamSubsCell tooltip says "Not published to the Workshop yet." when publishedSteamId is null',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      SteamSubsCell(item: _project()),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('Not published to the Workshop yet.'),
      findsOneWidget,
    );
  });
}

class _StubCache extends PublishedSubsCache {
  _StubCache(this._initial);
  final Map<String, int> _initial;

  @override
  Map<String, int> build() => _initial;
}
