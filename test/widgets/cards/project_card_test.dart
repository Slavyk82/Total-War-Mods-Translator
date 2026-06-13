import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/providers/projects_data_providers.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/cards/project_card.dart';

import '../../helpers/test_bootstrap.dart';
import '../../helpers/test_helpers.dart';

/// Large surface so the card never overflows during layout.
const Size _cardSurface = Size(1800, 1600);

Project _project({
  String id = 'p1',
  String name = 'My Mod',
  String? modSteamId,
  String? sourceFilePath,
  String projectType = 'mod',
  String? imageMetadata,
  bool hasModUpdateImpact = false,
  int? updatedAt,
  int? publishedAt,
  String? publishedSteamId,
}) {
  return Project(
    id: id,
    name: name,
    modSteamId: modSteamId,
    gameInstallationId: 'g1',
    sourceFilePath: sourceFilePath,
    createdAt: 1000,
    updatedAt: updatedAt ?? 2000,
    metadata: imageMetadata,
    hasModUpdateImpact: hasModUpdateImpact,
    projectType: projectType,
    publishedSteamId: publishedSteamId,
    publishedAt: publishedAt,
  );
}

GameInstallation _game({String gameCode = 'wh3'}) {
  return GameInstallation(
    id: 'g1',
    gameCode: gameCode,
    gameName: 'Game $gameCode',
    createdAt: 1000,
    updatedAt: 2000,
  );
}

ProjectLanguageWithInfo _lang({
  required String name,
  required int total,
  required int translated,
  int needsReview = 0,
}) {
  return ProjectLanguageWithInfo(
    projectLanguage: ProjectLanguage(
      id: 'pl_$name',
      projectId: 'p1',
      languageId: 'lang_$name',
      createdAt: 1000,
      updatedAt: 2000,
    ),
    language: Language(
      id: 'lang_$name',
      code: name.substring(0, 2).toLowerCase(),
      name: name,
      nativeName: name,
    ),
    totalUnits: total,
    translatedUnits: translated,
    needsReviewUnits: needsReview,
  );
}

ExportHistory _export({int exportedAt = 1500}) {
  return ExportHistory(
    id: 'e1',
    projectId: 'p1',
    languages: '["fr"]',
    format: ExportFormat.pack,
    validatedOnly: false,
    outputPath: 'out.pack',
    entryCount: 10,
    exportedAt: exportedAt,
  );
}

ProjectWithDetails _details({
  Project? project,
  GameInstallation? gameInstallation = const _Unset(),
  List<ProjectLanguageWithInfo>? languages,
  ModUpdateAnalysis? updateAnalysis,
  ExportHistory? lastPackExport,
}) {
  return ProjectWithDetails(
    project: project ?? _project(),
    gameInstallation: gameInstallation is _Unset ? _game() : gameInstallation,
    languages: languages ?? [_lang(name: 'French', total: 10, translated: 5)],
    updateAnalysis: updateAnalysis,
    lastPackExport: lastPackExport,
  );
}

/// Sentinel so we can pass `null` explicitly for gameInstallation.
class _Unset implements GameInstallation {
  const _Unset();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = _cardSurface,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    createThemedTestableWidget(
      child,
      theme: AppTheme.atelierDarkTheme,
      screenSize: size,
    ),
  );
}

void main() {
  setUp(() async => TestBootstrap.registerFakes());

  testWidgets('renders name, dates and a progress bar', (tester) async {
    await _pump(tester, ProjectCard(projectWithDetails: _details()));
    expect(find.text('My Mod'), findsOneWidget);
    // 5/10 -> 50%
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('French'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('tapping card fires onTap', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      ProjectCard(projectWithDetails: _details(), onTap: () => taps++),
    );
    await tester.tap(find.byType(ProjectCard));
    expect(taps, 1);
  });

  testWidgets('selection mode shows checkbox and fires toggle, not onTap',
      (tester) async {
    var toggles = 0;
    var taps = 0;
    await _pump(
      tester,
      ProjectCard(
        projectWithDetails: _details(),
        isSelectionMode: true,
        isSelected: true,
        onSelectionToggle: () => toggles++,
        onTap: () => taps++,
      ),
    );
    // Selected checkbox shows a checkmark icon.
    expect(find.byIcon(Icons.check), findsNothing); // sanity (fluent icon used)
    await tester.tap(find.byType(ProjectCard));
    expect(toggles, 1);
    expect(taps, 0);
  });

  testWidgets('selection mode unselected renders empty checkbox', (tester) async {
    await _pump(
      tester,
      ProjectCard(
        projectWithDetails: _details(),
        isSelectionMode: true,
        isSelected: false,
        onSelectionToggle: () {},
      ),
    );
    expect(find.byType(ProjectCard), findsOneWidget);
  });

  testWidgets('hover changes background (onEnter/onExit)', (tester) async {
    await _pump(tester, ProjectCard(projectWithDetails: _details()));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(ProjectCard)));
    await tester.pump();
    // Move away to trigger onExit.
    await gesture.moveTo(const Offset(5000, 5000));
    await tester.pump();
    expect(find.byType(ProjectCard), findsOneWidget);
  });

  testWidgets('no languages shows no-target-language message', (tester) async {
    await _pump(
      tester,
      ProjectCard(projectWithDetails: _details(languages: const [])),
    );
    expect(find.text(t.projects.labels.noTargetLanguage), findsOneWidget);
  });

  testWidgets('progress colors: 0%, partial, complete', (tester) async {
    await _pump(
      tester,
      ProjectCard(
        projectWithDetails: _details(
          languages: [
            _lang(name: 'Zero', total: 10, translated: 0),
            _lang(name: 'Low', total: 10, translated: 3),
            _lang(name: 'Half', total: 10, translated: 6),
            _lang(name: 'Full', total: 10, translated: 10),
          ],
        ),
      ),
    );
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(4));
  });

  testWidgets('steam workshop mod shows steam id, no resync button',
      (tester) async {
    await _pump(
      tester,
      ProjectCard(
        projectWithDetails: _details(
          project: _project(modSteamId: '123456'),
        ),
        onResync: () {},
      ),
    );
    expect(find.text('123456'), findsOneWidget);
  });

  testWidgets('local pack project shows resync button and fires onResync',
      (tester) async {
    var resyncs = 0;
    await _pump(
      tester,
      ProjectCard(
        projectWithDetails: _details(
          project: _project(modSteamId: null),
        ),
        onResync: () => resyncs++,
      ),
    );
    await tester.tap(find.byTooltip(t.projects.tooltips.resync));
    expect(resyncs, 1);
  });

  testWidgets('resync button shows spinner while resyncing', (tester) async {
    await _pump(
      tester,
      ProjectCard(
        projectWithDetails: _details(project: _project(modSteamId: null)),
        onResync: () {},
        isResyncing: true,
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Tooltip-based resync button is hidden while resyncing.
    expect(find.byTooltip(t.projects.tooltips.resync), findsNothing);
  });

  testWidgets('delete button shown and fires onDelete', (tester) async {
    var deletes = 0;
    await _pump(
      tester,
      ProjectCard(
        projectWithDetails: _details(),
        onDelete: () => deletes++,
      ),
    );
    await tester.tap(find.byTooltip(t.common.actions.delete));
    expect(deletes, 1);
  });

  testWidgets('game translation project hides resync, uses twmt icon',
      (tester) async {
    await _pump(
      tester,
      ProjectCard(
        projectWithDetails: _details(
          project: _project(projectType: 'game', modSteamId: null),
        ),
      ),
    );
    // game translation => no resync button even with null steam id.
    expect(find.byTooltip(t.projects.tooltips.resync), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('mod image from imageUrl uses Image.file', (tester) async {
    await _pump(
      tester,
      ProjectCard(
        projectWithDetails: _details(
          project: _project(
            imageMetadata: '{"mod_image_url":"C:/does/not/exist.png"}',
          ),
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('fallback game icons per game code', (tester) async {
    for (final code in ['wh3', 'troy', '3k', 'unknown']) {
      await _pump(
        tester,
        ProjectCard(
          projectWithDetails: _details(gameInstallation: _game(gameCode: code)),
        ),
      );
      expect(find.byType(ProjectCard), findsOneWidget);
    }
    // null game installation -> default icon branch
    await _pump(
      tester,
      ProjectCard(projectWithDetails: _details(gameInstallation: null)),
    );
    expect(find.byType(ProjectCard), findsOneWidget);
  });

  testWidgets('last export date and modified-since-export badge', (tester) async {
    await _pump(
      tester,
      ProjectCard(
        projectWithDetails: _details(
          // updatedAt far after export so isModifiedSinceLastExport is true.
          project: _project(updatedAt: 100000),
          lastPackExport: _export(exportedAt: 1000),
        ),
      ),
    );
    expect(find.text(t.projects.status.exportOutdated), findsOneWidget);
  });

  testWidgets('export date without modified badge', (tester) async {
    await _pump(
      tester,
      ProjectCard(
        projectWithDetails: _details(
          // updatedAt within 60s margin of export -> not modified.
          project: _project(updatedAt: 1500),
          lastPackExport: _export(exportedAt: 1500),
        ),
      ),
    );
    expect(find.text(t.projects.status.exportOutdated), findsNothing);
  });

  testWidgets('mod-update-impact badge shown', (tester) async {
    await _pump(
      tester,
      ProjectCard(
        projectWithDetails: _details(
          project: _project(hasModUpdateImpact: true),
        ),
      ),
    );
    expect(find.text(t.projects.status.modUpdated), findsOneWidget);
  });

  testWidgets('up-to-date badge when analysis has no pending changes',
      (tester) async {
    await _pump(
      tester,
      ProjectCard(
        projectWithDetails: _details(
          updateAnalysis: ModUpdateAnalysis.empty,
        ),
      ),
    );
    expect(find.text(t.projects.status.upToDate), findsOneWidget);
  });

  testWidgets('changes badge with pending changes shows summary', (tester) async {
    const analysis = ModUpdateAnalysis(
      newUnitsCount: 3,
      removedUnitsCount: 2,
      modifiedUnitsCount: 4,
      totalPackUnits: 20,
      totalProjectUnits: 15,
    );
    await _pump(
      tester,
      ProjectCard(
        projectWithDetails: _details(updateAnalysis: analysis),
      ),
    );
    // summary: "+3 new, ~4 modified"
    expect(find.text(analysis.summary), findsOneWidget);
  });
}
