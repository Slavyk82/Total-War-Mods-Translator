import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:twmt/features/bootstrap/widgets/mod_scan_boot_dialog.dart';
import 'package:twmt/features/mods/models/scan_log_message.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/features/steam_publish/providers/published_subs_cache_provider.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/providers/mods/mod_list_provider.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';

class _StubCache extends PublishedSubsCache {
  _StubCache({
    required List<String> ids,
    required Future<bool> Function(List<String>) onRefresh,
  })  : _ids = ids,
        _onRefresh = onRefresh;
  final List<String> _ids;
  final Future<bool> Function(List<String>) _onRefresh;

  @override
  Map<String, int> build() => const {};

  @override
  Future<List<String>> collectPublishedIds() async => _ids;

  @override
  Future<bool> refreshForIds(List<String> ids) => _onRefresh(ids);
}

/// Stub DetectedMods notifier that resolves immediately to an empty list,
/// bypassing real service dependencies.
class _StubDetectedMods extends DetectedMods {
  @override
  Future<List<DetectedMod>> build() async => const [];
}

Widget _wrap(Widget child, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.atelierDarkTheme,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() async => TestBootstrap.registerFakes());

  // The detectedModsProvider is async and depends on services we don't want
  // to spin up. Each test overrides it to resolve immediately to an empty
  // mod list so phase 1 finishes on the first frame.

  testWidgets('phase 2 skipped and dialog closes when no published ids',
      (tester) async {
    final logController = StreamController<ScanLogMessage>.broadcast();
    addTearDown(logController.close);

    await tester.pumpWidget(_wrap(
      const ModScanBootDialog(),
      [
        detectedModsProvider.overrideWith(_StubDetectedMods.new),
        scanLogStreamProvider.overrideWithValue(logController.stream),
        publishedSubsCacheProvider.overrideWith(() => _StubCache(
              ids: const [],
              onRefresh: (_) async => true,
            )),
      ],
    ));

    // Let phase 1 resolve and phase 2 short-circuit.
    await tester.pumpAndSettle();

    // No "Refreshing subscriber counts..." text appears.
    expect(find.text('Refreshing subscriber counts...'), findsNothing);
    // The dialog has popped.
    expect(find.byType(ModScanBootDialog), findsNothing);
  });

  testWidgets('phase 2 announces N ids and "Done." on success', (tester) async {
    final logController = StreamController<ScanLogMessage>.broadcast();
    addTearDown(logController.close);

    await tester.pumpWidget(_wrap(
      const ModScanBootDialog(),
      [
        detectedModsProvider.overrideWith(_StubDetectedMods.new),
        scanLogStreamProvider.overrideWithValue(logController.stream),
        publishedSubsCacheProvider.overrideWith(() => _StubCache(
              ids: const ['111', '222', '333'],
              onRefresh: (_) async => true,
            )),
      ],
    ));

    // Pump a few frames so phase 2 starts.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Title flipped.
    expect(find.text('Refreshing subscriber counts...'), findsOneWidget);
    // The announce + done lines made it through the merged log stream.
    expect(
      find.textContaining(
        'Refreshing subscriber counts for 3 published translations',
      ),
      findsOneWidget,
    );
    // Wait for the tail delay + close.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.byType(ModScanBootDialog), findsNothing);
  });

  testWidgets('phase 2 reports "Failed" on refresh error and still closes',
      (tester) async {
    final logController = StreamController<ScanLogMessage>.broadcast();
    addTearDown(logController.close);

    await tester.pumpWidget(_wrap(
      const ModScanBootDialog(),
      [
        detectedModsProvider.overrideWith(_StubDetectedMods.new),
        scanLogStreamProvider.overrideWithValue(logController.stream),
        publishedSubsCacheProvider.overrideWith(() => _StubCache(
              ids: const ['111'],
              onRefresh: (_) async => false,
            )),
      ],
    ));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.textContaining('Failed — subscriber counts unavailable'),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.byType(ModScanBootDialog), findsNothing);
  });
}
