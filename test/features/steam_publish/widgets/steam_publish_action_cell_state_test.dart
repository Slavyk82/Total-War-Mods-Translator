// Regression widget tests locking the three rendering modes of
// [SteamActionCell]. The production docstring describes a tight 3-state
// machine (no pack / pack without id / pack with id) and this file asserts
// each state renders its signature affordance so a future refactor can't
// silently flip a state.
//
// Fixtures use real temp pack files because [ProjectPublishItem.hasPack]
// reads `File(outputPath).existsSync()` directly. Temp directories are
// cleaned up via [addTearDown].
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';
import 'package:twmt/features/steam_publish/widgets/steam_publish_action_cell.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

class _FakeProjectRepository extends Mock implements ProjectRepository {}

/// Creates a touched-but-empty pack file in a per-test temp directory so
/// [ProjectPublishItem.hasPack] reports true. The temp directory is removed
/// via [addTearDown].
String _createTempPack(String id) {
  final dir = Directory.systemTemp.createTempSync('twmt-action-cell-$id-');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // Best-effort cleanup; tests shouldn't fail on a stale temp dir.
    }
  });
  final packPath = p.join(dir.path, '$id.pack');
  File(packPath).writeAsBytesSync(const []);
  return packPath;
}

ProjectPublishItem _project({
  String id = 'p1',
  String name = 'Sigmars Heirs',
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

  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('State A (no pack) renders Generate pack', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createThemedTestableWidget(
      SteamActionCell(item: _project()),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Generate pack'), findsOneWidget);
  });

  testWidgets(
    'State A (no pack, no id) renders the Set Workshop id icon button',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createThemedTestableWidget(
        SteamActionCell(item: _project()),
        theme: AppTheme.atelierDarkTheme,
      ));
      await tester.pumpAndSettle();

      // Generate pack must still render alongside the new pencil icon.
      expect(find.text('Generate pack'), findsOneWidget);
      expect(find.byTooltip('Set Workshop id'), findsOneWidget);
    },
  );

  testWidgets(
    'State A (no pack, with id) renders Generate + Open in Steam + Edit id',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createThemedTestableWidget(
        SteamActionCell(
          item: _project(publishedSteamId: '3456789012'),
        ),
        theme: AppTheme.atelierDarkTheme,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Generate pack'), findsOneWidget);
      expect(find.byTooltip('Open in Steam Workshop'), findsOneWidget);
      expect(find.byTooltip('Edit Workshop id'), findsOneWidget);
    },
  );

  testWidgets(
      'State B (pack, no Workshop id) renders the inline Workshop-id input',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // State B uses a TextField, which requires a Material ancestor. Wrap the
    // cell in a Scaffold so the material lookup resolves.
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(body: SteamActionCell(item: _project(hasPack: true))),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    // Signature affordance of State B: the inline Workshop-id TextField with
    // its current hint text. Task 8 renamed this hint to flag URL support —
    // keep the finder pinned to the live string so a future rename trips this
    // test and forces the state lock to be reviewed.
    final inputFinder = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Paste Workshop URL or ID...',
    );
    expect(inputFinder, findsOneWidget);
  });

  testWidgets('State B accepts a full Workshop URL and saves the extracted id',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Prepare a fake project repository that returns a well-formed project
    // via `getById` and records the entity passed to `update` so the test
    // can assert the URL was parsed to the raw numeric id.
    final fakeRepo = _FakeProjectRepository();
    final savedIds = <String?>[];
    final baseProject = Project(
      id: 'p1',
      name: 'Sigmars Heirs',
      gameInstallationId: 'g1',
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
      Scaffold(body: SteamActionCell(item: _project(hasPack: true))),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        projectRepositoryProvider.overrideWithValue(fakeRepo),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'https://steamcommunity.com/sharedfiles/filedetails/?id=3456789012',
    );
    await tester.tap(find.byTooltip('Save Workshop id'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(savedIds, ['3456789012']);
  });

  testWidgets('State B shows the Open launcher icon button', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(body: SteamActionCell(item: _project(hasPack: true))),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Open the in-game launcher'), findsOneWidget);
    // Sanity: the play icon sits inside that tooltip.
    expect(
      find.descendant(
        of: find.byTooltip('Open the in-game launcher'),
        matching: find.byIcon(FluentIcons.play_24_regular),
      ),
      findsOneWidget,
    );
  });

  testWidgets('State B shows the two-step checklist text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(body: SteamActionCell(item: _project(hasPack: true))),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Publish from the launcher'),
      findsOneWidget,
    );
  });

  testWidgets('State C (pack + Workshop id) renders the Update action',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createThemedTestableWidget(
      SteamActionCell(
        item: _project(hasPack: true, publishedSteamId: '123456'),
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Update'), findsOneWidget);
  });
}
