import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';
import 'package:twmt/features/steam_publish/widgets/steam_id_cell.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/repositories/project_publication_repository.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

class _FakeProjectPublicationRepository extends Mock
    implements ProjectPublicationRepository {}

String _createTempPack(String id) {
  final dir = Directory.systemTemp.createTempSync('twmt-id-cell-$id-');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  final packPath = p.join(dir.path, '$id.pack');
  File(packPath).writeAsBytesSync(const []);
  return packPath;
}

ProjectPublishItem _project({
  String id = 'p1',
  String? publishedSteamId,
  bool hasPack = false,
}) {
  final outputPath = hasPack ? _createTempPack(id) : '';
  return ProjectPublishItem(
    export: hasPack
        ? ExportHistory(
            id: 'e-$id',
            projectId: id,
            languages: '["en"]',
            format: ExportFormat.pack,
            validatedOnly: false,
            outputPath: outputPath,
            entryCount: 10,
            exportedAt: 1_700_000_000,
          )
        : null,
    project: Project(
      id: id,
      name: 'P1',
      gameInstallationId: 'g',
      createdAt: 0,
      updatedAt: 0,
    ),
    languageCodes: const ['en'],
    resolvedPublishedSteamId: publishedSteamId,
    resolvedPublishedAt: publishedSteamId != null ? 1_700_000_000 : null,
  );
}

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

  testWidgets('Save persists the parsed id via the publication repository',
      (tester) async {
    final fakePubRepo = _FakeProjectPublicationRepository();
    final setSteamIdCalls = <List<String>>[];
    when(() => fakePubRepo.setSteamId(any(), any(), any()))
        .thenAnswer((invocation) async {
      setSteamIdCalls.add([
        invocation.positionalArguments[0] as String,
        invocation.positionalArguments[1] as String,
        invocation.positionalArguments[2] as String,
      ]);
      return const Ok<void, TWMTDatabaseException>(null);
    });

    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(body: SteamIdCell(item: _project())),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        projectPublicationRepositoryProvider.overrideWithValue(fakePubRepo),
      ],
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

    expect(setSteamIdCalls, hasLength(1));
    expect(setSteamIdCalls.single[0], 'p1'); // projectId
    expect(setSteamIdCalls.single[2], '3456789012'); // steamId
  });

  testWidgets(
    'Save with unparseable input keeps the editor open and never calls setSteamId',
    (tester) async {
      final fakePubRepo = _FakeProjectPublicationRepository();

      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(body: SteamIdCell(item: _project())),
        theme: AppTheme.atelierDarkTheme,
        overrides: [
          projectPublicationRepositoryProvider.overrideWithValue(fakePubRepo),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Set Workshop id'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'not-a-url');
      await tester.tap(find.byTooltip('Save Workshop id'));
      // Pump past the toast's 4-second auto-dismiss so its `Future.delayed`
      // doesn't leak into the next test as a pending timer.
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Editor stays open so the user can correct the input without re-typing.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Save Workshop id'), findsOneWidget);
      verifyNever(() => fakePubRepo.setSteamId(any(), any(), any()));
    },
  );

  testWidgets(
    'Save surfaces a failure when the repository throws and keeps the editor open',
    (tester) async {
      final fakePubRepo = _FakeProjectPublicationRepository();
      when(() => fakePubRepo.setSteamId(any(), any(), any()))
          .thenThrow(Exception('db down'));

      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(body: SteamIdCell(item: _project())),
        theme: AppTheme.atelierDarkTheme,
        overrides: [
          projectPublicationRepositoryProvider.overrideWithValue(fakePubRepo),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Set Workshop id'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '3456789012');
      await tester.tap(find.byTooltip('Save Workshop id'));
      // Pump past the toast's 4-second auto-dismiss to drain its pending timer.
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Save Workshop id'), findsOneWidget);
    },
  );

  testWidgets(
    'State B (pack + no id) auto-opens the editor',
    (tester) async {
      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(body: SteamIdCell(item: _project(hasPack: true))),
        theme: AppTheme.atelierDarkTheme,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Save Workshop id'), findsOneWidget);
      expect(find.byTooltip('Cancel'), findsOneWidget);
    },
  );

  testWidgets(
    'State B cancel falls back to read mode for the lifetime of the row',
    (tester) async {
      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(body: SteamIdCell(item: _project(hasPack: true))),
        theme: AppTheme.atelierDarkTheme,
      ));
      await tester.pumpAndSettle();

      // Cancel the auto-opened editor.
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();

      // The cell sits in read mode (em dash + Set pencil).
      expect(find.byType(TextField), findsNothing);
      expect(find.text('—'), findsOneWidget);
      expect(find.byTooltip('Set Workshop id'), findsOneWidget);
    },
  );
}
