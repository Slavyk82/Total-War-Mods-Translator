import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';
import 'package:twmt/features/steam_publish/widgets/steam_id_cell.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

class _FakeProjectRepository extends Mock implements ProjectRepository {}

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
  setUpAll(() {
    registerFallbackValue(
      Project(
        id: '_',
        name: '_',
        gameInstallationId: '_',
        createdAt: 0,
        updatedAt: 0,
      ),
    );
  });

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

  testWidgets('Pencil tap reveals the inline TextField pre-filled with the ID',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(
        body: SteamIdCell(item: _project(publishedSteamId: '999')),
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit Workshop id'));
    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text, '999');
    expect(find.byTooltip('Save Workshop id'), findsOneWidget);
    expect(find.byTooltip('Cancel'), findsOneWidget);
  });

  testWidgets('Cancel exits edit mode and restores the read view',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(
        body: SteamIdCell(item: _project(publishedSteamId: '999')),
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit Workshop id'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('999'), findsOneWidget);
  });

  testWidgets('Save persists the parsed id via the project repository',
      (tester) async {
    final fakeRepo = _FakeProjectRepository();
    final savedIds = <String?>[];
    final baseProject = Project(
      id: 'p1',
      name: 'P1',
      gameInstallationId: 'g',
      createdAt: 0,
      updatedAt: 0,
    );
    when(() => fakeRepo.getById('p1')).thenAnswer(
      (_) async => Ok<Project, TWMTDatabaseException>(baseProject),
    );
    when(() => fakeRepo.update(any())).thenAnswer((invocation) async {
      final updated = invocation.positionalArguments.first as Project;
      savedIds.add(updated.publishedSteamId);
      return Ok<Project, TWMTDatabaseException>(updated);
    });

    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(body: SteamIdCell(item: _project())),
      theme: AppTheme.atelierDarkTheme,
      overrides: [projectRepositoryProvider.overrideWithValue(fakeRepo)],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Set Workshop id'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'https://steamcommunity.com/sharedfiles/filedetails/?id=3456789012',
    );
    await tester.tap(find.byTooltip('Save Workshop id'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(savedIds, ['3456789012']);
  });
}
