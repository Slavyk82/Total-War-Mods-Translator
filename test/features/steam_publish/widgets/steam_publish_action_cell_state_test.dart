// Regression widget tests locking the four rendering modes of
// [SteamActionCell]. The production docstring describes a tight 4-state
// machine (A0/A1: no pack / B: pack without id / C: pack with id) and this
// file asserts each state renders its signature affordance so a future
// refactor can't silently flip a state.
//
// Fixtures use real temp pack files because [ProjectPublishItem.hasPack]
// reads `File(outputPath).existsSync()` directly. Temp directories are
// cleaned up via [addTearDown].
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:path/path.dart' as p;

import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';
import 'package:twmt/features/steam_publish/widgets/steam_publish_action_cell.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

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
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('State A₀ (no pack, no id) renders Generate pack only',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createThemedTestableWidget(
      SteamActionCell(item: _project()),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Generate pack'), findsOneWidget);
    expect(find.byTooltip('Set Workshop id'), findsNothing);
    expect(find.byTooltip('Edit Workshop id'), findsNothing);
  });

  testWidgets(
    'State A₁ (no pack, with id) renders Generate + Open in Steam (no pencil)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createThemedTestableWidget(
        SteamActionCell(item: _project(publishedSteamId: '3456789012')),
        theme: AppTheme.atelierDarkTheme,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Generate pack'), findsOneWidget);
      expect(find.byTooltip('Open in Steam Workshop'), findsOneWidget);
      expect(find.byTooltip('Edit Workshop id'), findsNothing);
    },
  );

  testWidgets(
    'State B (pack, no id) renders disabled Update + Open launcher',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(body: SteamActionCell(item: _project(hasPack: true))),
        theme: AppTheme.atelierDarkTheme,
      ));
      await tester.pumpAndSettle();

      // Update label is rendered, but tap-handler is null (disabled).
      expect(find.text('Update'), findsOneWidget);
      expect(
        find.byTooltip('Set the Steam ID first to enable updating'),
        findsOneWidget,
      );

      // Launcher button still present.
      expect(find.byTooltip('Open the in-game launcher'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byTooltip('Open the in-game launcher'),
          matching: find.byIcon(FluentIcons.play_24_regular),
        ),
        findsOneWidget,
      );

      // Inline editor is gone — that's now SteamIdCell's job.
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('Save Workshop id'), findsNothing);
    },
  );

  testWidgets('State C (pack + Workshop id) renders Update without a pencil',
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
    expect(find.byTooltip('Open in Steam Workshop'), findsOneWidget);
    expect(find.byTooltip('Edit Workshop id'), findsNothing);
  });
}
