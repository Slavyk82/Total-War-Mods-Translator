// Widget tests for SteamActionCell — Plan 5a · Task 4 follow-up.
//
// Covers the "no local pack but already published" compound rendering that
// was lost in the Task 4 state-machine rewrite and restored in Fix A:
// Generate + Open-in-Steam must render side-by-side so a user whose pack was
// deleted can still jump to their published Workshop listing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';
import 'package:twmt/features/steam_publish/widgets/steam_publish_action_cell.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

ProjectPublishItem _project({
  String id = 'p1',
  String name = 'Sigmars Heirs',
  String? publishedSteamId,
}) {
  return ProjectPublishItem(
    // No export → hasPack is false.
    export: null,
    project: Project(
      id: id,
      name: name,
      gameInstallationId: 'g1',
      createdAt: 0,
      updatedAt: 0,
      publishedSteamId: publishedSteamId,
      publishedAt: publishedSteamId != null ? 1_700_000_000 : null,
    ),
    languageCodes: const ['en'],
  );
}

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets(
      'SteamActionCell renders Generate + Open-in-Steam when pack missing but publishedSteamId is set',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createThemedTestableWidget(
      SteamActionCell(item: _project(publishedSteamId: '123456')),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    // Generate pack button is present.
    expect(find.text('Generate pack'), findsOneWidget);
    // Open-in-Steam action renders as a SmallTextButton beside it.
    expect(
      find.widgetWithText(SmallTextButton, 'Open in Steam'),
      findsOneWidget,
    );
  });

  testWidgets(
      'SteamActionCell renders Generate only when pack missing and never published',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createThemedTestableWidget(
      SteamActionCell(item: _project()),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Generate pack'), findsOneWidget);
    // No Open-in-Steam when the project was never published.
    expect(
      find.widgetWithText(SmallTextButton, 'Open in Steam'),
      findsNothing,
    );
  });
}
