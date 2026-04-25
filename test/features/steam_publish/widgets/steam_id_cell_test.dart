import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';
import 'package:twmt/features/steam_publish/widgets/steam_id_cell.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

ProjectPublishItem _project({String? publishedSteamId}) =>
    ProjectPublishItem(
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

  testWidgets('Read mode — shows the ID and the edit pencil when set',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(
        body: SteamIdCell(item: _project(publishedSteamId: '3024186382')),
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('3024186382'), findsOneWidget);
    expect(find.byTooltip('Edit Workshop id'), findsOneWidget);
    expect(find.byIcon(FluentIcons.edit_24_regular), findsOneWidget);
  });

  testWidgets('Read mode — shows em dash and pencil when ID is absent',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(body: SteamIdCell(item: _project())),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('—'), findsOneWidget);
    expect(find.byTooltip('Set Workshop id'), findsOneWidget);
  });
}
