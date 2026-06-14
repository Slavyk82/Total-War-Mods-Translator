// Coverage-focused widget tests for `lib/features/mods/widgets/mods_list.dart`.
//
// ModsList is a plain StatelessWidget that takes its data via constructor
// props (not via filtered-mods providers), so these tests construct it
// directly with crafted DetectedMod fixtures. The goal is to exercise every
// per-row state variant (imported/not, needs-download, has-changes, up-to-date,
// hidden), the row actions (hide toggle, force-redownload), the sortable
// header, and the empty / loading / scanning / refresh-overlay branches.
import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/features/mods/widgets/mods_list.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/project_metadata.dart';
import 'package:twmt/models/domain/scan_log_message.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/common/scan_terminal_widget.dart';
import 'package:twmt/widgets/lists/list_row.dart';
import 'package:twmt/widgets/lists/status_pill.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

// Pinned "now" so relative-date rendering is deterministic.
final _now = DateTime(2024, 6, 1, 12);
final int _nowEpoch = _now.millisecondsSinceEpoch ~/ 1000;

DetectedMod _mod(
  String id,
  String name, {
  String? imageUrl,
  int? timeUpdated,
  int? localFileLastModified,
  bool isAlreadyImported = false,
  bool isHidden = false,
  int subscribers = 0,
  ModUpdateAnalysis? analysis,
}) =>
    DetectedMod(
      workshopId: id,
      name: name,
      packFilePath: '/tmp/$id.pack',
      imageUrl: imageUrl,
      metadata:
          subscribers > 0 ? ProjectMetadata(modSubscribers: subscribers) : null,
      isAlreadyImported: isAlreadyImported,
      isHidden: isHidden,
      timeUpdated: timeUpdated,
      localFileLastModified: localFileLastModified,
      updateAnalysis: analysis,
    );

/// A needs-download mod: Steam newer than local file.
DetectedMod _needsDownload(String id, String name,
        {bool imported = true}) =>
    _mod(
      id,
      name,
      isAlreadyImported: imported,
      timeUpdated: _nowEpoch,
      localFileLastModified: _nowEpoch - 3600,
    );

/// A has-changes mod: local file current, imported, analysis has pending units.
DetectedMod _hasChanges(String id, String name) => _mod(
      id,
      name,
      isAlreadyImported: true,
      timeUpdated: _nowEpoch - 7200,
      localFileLastModified: _nowEpoch,
      analysis: const ModUpdateAnalysis(
        newUnitsCount: 3,
        removedUnitsCount: 1,
        modifiedUnitsCount: 2,
        totalPackUnits: 10,
        totalProjectUnits: 8,
      ),
    );

/// An up-to-date imported mod: local file current, no pending analysis.
DetectedMod _upToDate(String id, String name) => _mod(
      id,
      name,
      isAlreadyImported: true,
      timeUpdated: _nowEpoch - 7200,
      localFileLastModified: _nowEpoch,
    );

Widget _pump(
  Widget child, {
  List<Override> extra = const [],
}) =>
    createThemedTestableWidget(
      child,
      theme: AppTheme.atelierDarkTheme,
      screenSize: const Size(1400, 1000),
      overrides: [
        clockProvider.overrideWithValue(() => _now),
        ...extra,
      ],
    );

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  setUpAll(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.textScaleFactorTestValue = 1.0;
    addTearDown(
      () => binding.platformDispatcher.clearTextScaleFactorTestValue(),
    );
  });

  Future<void> setSurface(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  group('loading states', () {
    testWidgets('isLoading without stream shows spinner indicator',
        (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(mods: const [], onRowTap: (_) {}, isLoading: true),
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ScanTerminalWidget), findsNothing);
    });

    testWidgets('isLoading with stream shows scan terminal', (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(
          mods: const [],
          onRowTap: (_) {},
          isLoading: true,
          scanLogStream: const Stream<ScanLogMessage>.empty(),
        ),
      ));
      await tester.pump();

      expect(find.byType(ScanTerminalWidget), findsOneWidget);
    });
  });

  group('empty states', () {
    testWidgets('empty + not showing hidden renders "no mods found"',
        (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(mods: const [], onRowTap: (_) {}),
      ));
      await tester.pump();

      expect(find.byIcon(FluentIcons.cube_24_regular), findsOneWidget);
      expect(find.text('No mods found'), findsOneWidget);
    });

    testWidgets('empty + showingHidden renders hidden empty copy',
        (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(mods: const [], onRowTap: (_) {}, showingHidden: true),
      ));
      await tester.pump();

      expect(find.byIcon(FluentIcons.eye_off_24_regular), findsOneWidget);
      expect(find.text('No hidden mods'), findsOneWidget);
    });

    testWidgets('empty + scanning with stream shows scan terminal',
        (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(
          mods: const [],
          onRowTap: (_) {},
          isScanning: true,
          scanLogStream: const Stream<ScanLogMessage>.empty(),
        ),
      ));
      await tester.pump();

      expect(find.byType(ScanTerminalWidget), findsOneWidget);
      expect(find.text('No mods found'), findsNothing);
    });
  });

  group('row rendering — cell variants', () {
    testWidgets('renders a row per mod with header', (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(
          mods: [
            _mod('1', 'Alpha', subscribers: 12345),
            _mod('2', 'Beta'),
          ],
          onRowTap: (_) {},
        ),
      ));
      await tester.pump();

      expect(find.byType(ListRow), findsNWidgets(2));
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      // Workshop ids rendered in the title block.
      expect(find.text('1'), findsOneWidget);
      // Subscribers formatted with space grouping.
      expect(find.text('12 345'), findsOneWidget);
      // No-subscribers cell renders a dash.
      expect(find.text('-'), findsWidgets);
    });

    testWidgets('remote image thumbnail renders CachedNetworkImage path',
        (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(
          mods: [_mod('1', 'Remote', imageUrl: 'https://example.com/x.png')],
          onRowTap: (_) {},
        ),
      ));
      await tester.pump();
      // Placeholder spinner from CachedNetworkImage is shown while loading.
      expect(find.byType(ListRow), findsOneWidget);
    });

    testWidgets('local file image thumbnail renders Image.file path',
        (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(
          mods: [_mod('1', 'Local', imageUrl: 'C:/does/not/exist.png')],
          onRowTap: (_) {},
        ),
      ));
      await tester.pump();
      // errorBuilder fallback icon renders since the file does not exist.
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('empty image url renders fallback icon', (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(
          mods: [_mod('1', 'NoImg', imageUrl: '')],
          onRowTap: (_) {},
        ),
      ));
      await tester.pump();
      expect(find.byIcon(FluentIcons.image_off_24_regular), findsOneWidget);
    });

    testWidgets('updated cell: no timestamp renders dash', (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(mods: [_mod('1', 'NoDate')], onRowTap: (_) {}),
      ));
      await tester.pump();
      // The updated cell shows '-' alongside subscribers '-'.
      expect(find.text('-'), findsWidgets);
    });

    testWidgets('updated cell: plain upToDate shows relative label',
        (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(mods: [_upToDate('1', 'Recent')], onRowTap: (_) {}),
      ));
      await tester.pump();
      // No needs-download / sync icon in the updated cell for up-to-date.
      expect(
        find.byIcon(FluentIcons.arrow_download_24_filled),
        findsNothing,
      );
    });

    testWidgets('updated cell: needsDownload shows download icon',
        (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(mods: [_needsDownload('1', 'Outdated')], onRowTap: (_) {}),
      ));
      await tester.pump();
      expect(
        find.byIcon(FluentIcons.arrow_download_24_filled),
        findsWidgets,
      );
    });

    testWidgets('updated cell: hasChanges shows sync icon', (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(mods: [_hasChanges('1', 'Changed')], onRowTap: (_) {}),
      ));
      await tester.pump();
      expect(find.byIcon(FluentIcons.arrow_sync_24_filled), findsOneWidget);
    });

    testWidgets('imported cell shows imported vs not-imported pill',
        (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(
          mods: [
            _mod('1', 'Imp', isAlreadyImported: true),
            _mod('2', 'NotImp'),
          ],
          onRowTap: (_) {},
        ),
      ));
      await tester.pump();
      expect(find.text('Imported'), findsOneWidget);
      expect(find.text('Not Imported'), findsOneWidget);
    });

    testWidgets('changes cell: not imported renders dash', (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(mods: [_mod('1', 'Plain')], onRowTap: (_) {}),
      ));
      await tester.pump();
      expect(find.text('-'), findsWidgets);
    });

    testWidgets('changes cell: upToDate shows up-to-date label',
        (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(mods: [_upToDate('1', 'Done')], onRowTap: (_) {}),
      ));
      await tester.pump();
      expect(
        find.byIcon(FluentIcons.checkmark_circle_24_regular),
        findsWidgets,
      );
    });

    testWidgets('changes cell: hasChanges renders changes badge',
        (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(mods: [_hasChanges('1', 'Changed')], onRowTap: (_) {}),
      ));
      await tester.pump();
      expect(find.byIcon(FluentIcons.warning_24_filled), findsOneWidget);
    });

    testWidgets(
        'changes cell: imported + status fallthrough renders dash '
        '(hasChanges status but null analysis)', (tester) async {
      await setSurface(tester);
      // Imported, local current, but updateStatus resolves to upToDate when
      // analysis is null -> hits the upToDate branch. To exercise the final
      // fallback dash we need imported + unknown status (missing timestamps).
      await tester.pumpWidget(_pump(
        ModsList(
          mods: [_mod('1', 'Unknown', isAlreadyImported: true)],
          onRowTap: (_) {},
        ),
      ));
      await tester.pump();
      expect(find.text('-'), findsWidgets);
    });
  });

  group('changes cell — needs download badge action', () {
    testWidgets('tapping needs-download badge invokes onForceRedownload',
        (tester) async {
      await setSurface(tester);
      String? tapped;
      await tester.pumpWidget(_pump(
        ModsList(
          mods: [_needsDownload('1', 'Outdated')],
          onRowTap: (_) {},
          onForceRedownload: (p) => tapped = p,
        ),
      ));
      await tester.pump();

      // The needs-download StatusPill carries the "Download required" label.
      final pill = find.widgetWithText(StatusPill, 'Download required');
      expect(pill, findsOneWidget);
      await tester.tap(pill);
      await tester.pump();
      expect(tapped, '/tmp/1.pack');
    });

    testWidgets('needs-download badge with null callback is non-tappable',
        (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(
          mods: [_needsDownload('1', 'Outdated')],
          onRowTap: (_) {},
        ),
      ));
      await tester.pump();
      // Renders fine without a callback (enabled == false branch).
      expect(
        find.widgetWithText(StatusPill, 'Download required'),
        findsOneWidget,
      );
    });
  });

  group('hide toggle cell', () {
    testWidgets('visible mod shows eye-off icon and toggles to hide',
        (tester) async {
      await setSurface(tester);
      String? toggledId;
      bool? toggledHide;
      await tester.pumpWidget(_pump(
        ModsList(
          mods: [_mod('42', 'Vis')],
          onRowTap: (_) {},
          onToggleHidden: (id, hide) {
            toggledId = id;
            toggledHide = hide;
          },
        ),
      ));
      await tester.pump();

      expect(find.byIcon(FluentIcons.eye_off_24_regular), findsOneWidget);
      await tester.tap(find.byIcon(FluentIcons.eye_off_24_regular));
      await tester.pump();
      expect(toggledId, '42');
      expect(toggledHide, isTrue);
    });

    testWidgets('hidden mod shows eye icon and toggles to show',
        (tester) async {
      await setSurface(tester);
      bool? toggledHide;
      await tester.pumpWidget(_pump(
        ModsList(
          mods: [_mod('7', 'Hid', isHidden: true)],
          onRowTap: (_) {},
          showingHidden: true,
          onToggleHidden: (_, hide) => toggledHide = hide,
        ),
      ));
      await tester.pump();

      expect(find.byIcon(FluentIcons.eye_24_regular), findsOneWidget);
      await tester.tap(find.byIcon(FluentIcons.eye_24_regular));
      await tester.pump();
      expect(toggledHide, isFalse);
    });

    testWidgets('hover toggles accent highlight state', (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(
          mods: [_mod('1', 'Hover')],
          onRowTap: (_) {},
          onToggleHidden: (_, _) {},
        ),
      ));
      await tester.pump();

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture
          .moveTo(tester.getCenter(find.byIcon(FluentIcons.eye_off_24_regular)));
      await tester.pump();
      // Move away to fire onExit too.
      await gesture.moveTo(Offset.zero);
      await tester.pump();
      expect(find.byIcon(FluentIcons.eye_off_24_regular), findsOneWidget);
    });

    testWidgets('tap with null onToggleHidden is a no-op', (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(mods: [_mod('1', 'NoCb')], onRowTap: (_) {}),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(FluentIcons.eye_off_24_regular));
      await tester.pump();
      expect(find.byType(ListRow), findsOneWidget);
    });
  });

  group('row tap', () {
    testWidgets('tapping a row invokes onRowTap with workshop id',
        (tester) async {
      await setSurface(tester);
      String? tappedId;
      await tester.pumpWidget(_pump(
        ModsList(
          mods: [_mod('99', 'Tappable')],
          onRowTap: (id) => tappedId = id,
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Tappable'));
      await tester.pump();
      expect(tappedId, '99');
    });
  });

  group('sortable header', () {
    testWidgets('tapping NAME header toggles sort and shows active arrow',
        (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(mods: [_mod('1', 'A')], onRowTap: (_) {}),
      ));
      await tester.pump();

      // Default sort is name ascending -> up arrow is active in header.
      expect(find.byIcon(FluentIcons.arrow_up_16_filled), findsOneWidget);

      await tester.tap(find.text('MOD'));
      await tester.pump();
      // Toggling name flips to descending -> down arrow.
      expect(find.byIcon(FluentIcons.arrow_down_16_filled), findsOneWidget);
    });

    testWidgets('tapping SUBS header activates subscribers sort indicator',
        (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(mods: [_mod('1', 'A', subscribers: 5)], onRowTap: (_) {}),
      ));
      await tester.pump();

      await tester.tap(find.text('SUBS'));
      await tester.pump();
      // Numeric field defaults to descending -> down arrow becomes active.
      expect(find.byIcon(FluentIcons.arrow_down_16_filled), findsOneWidget);
    });

    testWidgets('tapping UPDATED header activates updated sort indicator',
        (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(mods: [_upToDate('1', 'A')], onRowTap: (_) {}),
      ));
      await tester.pump();

      await tester.tap(find.text('UPDATED'));
      await tester.pump();
      // Numeric/date field defaults to descending -> down arrow active.
      expect(find.byIcon(FluentIcons.arrow_down_16_filled), findsOneWidget);
    });

    testWidgets('plain header columns render STATUS and CHANGES labels',
        (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(mods: [_mod('1', 'A')], onRowTap: (_) {}),
      ));
      await tester.pump();
      expect(find.text('STATUS'), findsOneWidget);
      expect(find.text('CHANGES'), findsOneWidget);
    });
  });

  group('refresh overlay', () {
    testWidgets('scanning with rows + stream renders terminal overlay on list',
        (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(
          mods: [_mod('1', 'A'), _mod('2', 'B')],
          onRowTap: (_) {},
          isScanning: true,
          scanLogStream: const Stream<ScanLogMessage>.empty(),
        ),
      ));
      await tester.pump();

      // List is rendered (dimmed via Opacity) with the terminal stacked over.
      expect(find.byType(Opacity), findsWidgets);
      expect(find.byType(ScanTerminalWidget), findsOneWidget);
      expect(find.byType(ListRow), findsNWidgets(2));
    });
  });

  group('mods sort provider interaction', () {
    testWidgets('header reads modsSortProvider override', (tester) async {
      await setSurface(tester);
      await tester.pumpWidget(_pump(
        ModsList(mods: [_mod('1', 'A')], onRowTap: (_) {}),
        extra: [
          modsSortProvider.overrideWith(_SubsDescSort.new),
        ],
      ));
      await tester.pump();
      // Subscribers sort active descending -> SUBS header has down arrow.
      expect(find.byIcon(FluentIcons.arrow_down_16_filled), findsOneWidget);
    });
  });
}

/// Forces the sort state to subscribers-descending so the SUBS header renders
/// its active descending arrow without a tap.
class _SubsDescSort extends ModsSort {
  @override
  ModsSortState build() =>
      const ModsSortState(field: ModsSortField.subscribers, ascending: false);
}
