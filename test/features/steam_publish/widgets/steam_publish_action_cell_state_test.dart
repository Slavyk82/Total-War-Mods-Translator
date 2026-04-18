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
    // its current hint text. Keep this finder pinned to the live string so a
    // future hint rename (e.g. Task 8's "Paste Workshop URL or ID...") flips
    // this test and forces the state lock to be reviewed.
    final inputFinder = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Workshop id...',
    );
    expect(inputFinder, findsOneWidget);
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
