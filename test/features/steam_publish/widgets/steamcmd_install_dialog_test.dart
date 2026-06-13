// Widget coverage tests for
// lib/features/steam_publish/widgets/steamcmd_install_dialog.dart.
//
// The dialog walks through four install phases (confirm, downloading, success,
// error) driven by SteamCmdManager.downloadAndInstall. These tests render every
// phase, exercise the Install / Cancel / Continue / Close / Retry actions, and
// drive the onProgress callback to cover the downloading progress UI.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/features/steam_publish/widgets/steamcmd_install_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/steamcmd_manager.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

class _MockSteamCmdManager extends Mock implements SteamCmdManager {}

void main() {
  late _MockSteamCmdManager manager;

  setUp(() {
    manager = _MockSteamCmdManager();
  });

  /// Pump the dialog inside a nested Navigator under an Overlay, so a
  /// `Navigator.of(context).pop(...)` from the actions resolves the local
  /// route. The body lives on a tall surface to avoid Column overflow.
  Future<void> pumpDialog(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          steamCmdManagerProvider.overrideWithValue(manager),
          ...overrides,
        ],
        child: MaterialApp(
          theme: ThemeData.light().copyWith(extensions: [slateTokens]),
          home: Scaffold(
            body: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => Navigator(
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (navContext) => Center(
                        child: ElevatedButton(
                          onPressed: () => SteamCmdInstallDialog.show(navContext),
                          child: const Text('open'),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the confirm phase with title and confirm texts',
      (tester) async {
    await pumpDialog(tester);

    expect(find.text(t.steamPublish.steamcmdDialog.title), findsOneWidget);
    expect(find.text(t.steamPublish.steamcmdDialog.subtitle), findsOneWidget);
    expect(find.text(t.steamPublish.steamcmdDialog.confirmText), findsOneWidget);
    expect(find.text(t.steamPublish.steamcmdDialog.confirmText2), findsOneWidget);
    // Confirm-phase actions.
    expect(find.text(t.steamPublish.steamcmdDialog.cancel), findsOneWidget);
    expect(find.text(t.steamPublish.steamcmdDialog.install), findsOneWidget);
  });

  testWidgets('Cancel in confirm phase pops the dialog', (tester) async {
    await pumpDialog(tester);

    expect(find.text(t.steamPublish.steamcmdDialog.title), findsOneWidget);

    await tester.tap(find.text(t.steamPublish.steamcmdDialog.cancel));
    await tester.pumpAndSettle();

    expect(find.text(t.steamPublish.steamcmdDialog.title), findsNothing);
  });

  testWidgets(
      'tapping Install calls downloadAndInstall and drives the downloading '
      'progress UI', (tester) async {
    final completer = Completer<Result<String, SteamServiceException>>();
    void Function(double)? captured;
    when(() => manager.downloadAndInstall(
          onProgress: any(named: 'onProgress'),
        )).thenAnswer((invocation) {
      captured =
          invocation.namedArguments[#onProgress] as void Function(double)?;
      return completer.future;
    });

    await pumpDialog(tester);

    await tester.tap(find.text(t.steamPublish.steamcmdDialog.install));
    await tester.pump();

    verify(() => manager.downloadAndInstall(
          onProgress: any(named: 'onProgress'),
        )).called(1);

    // Downloading phase: label, progress bar, and 0% shown.
    expect(find.text(t.steamPublish.steamcmdDialog.downloading), findsOneWidget);
    expect(find.text(t.steamPublish.steamcmdDialog.downloadingFrom),
        findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    // Downloading phase only shows Cancel.
    expect(find.text(t.steamPublish.steamcmdDialog.cancel), findsOneWidget);
    expect(find.text(t.steamPublish.steamcmdDialog.install), findsNothing);

    // Drive a progress update through the captured callback.
    captured!(0.42);
    await tester.pump();
    expect(find.text('42%'), findsOneWidget);

    // Finish the install successfully and let the phase flip.
    completer.complete(const Ok('C:/steamcmd/steamcmd.exe'));
    await tester.pumpAndSettle();

    expect(find.text(t.steamPublish.steamcmdDialog.successTitle), findsOneWidget);
    expect(
        find.text(t.steamPublish.steamcmdDialog.successMessage), findsOneWidget);
  });

  testWidgets('Cancel during downloading phase pops the dialog', (tester) async {
    final completer = Completer<Result<String, SteamServiceException>>();
    when(() => manager.downloadAndInstall(
          onProgress: any(named: 'onProgress'),
        )).thenAnswer((_) => completer.future);

    await pumpDialog(tester);
    await tester.tap(find.text(t.steamPublish.steamcmdDialog.install));
    await tester.pump();

    expect(find.text(t.steamPublish.steamcmdDialog.downloading), findsOneWidget);

    await tester.tap(find.text(t.steamPublish.steamcmdDialog.cancel));
    await tester.pumpAndSettle();

    expect(find.text(t.steamPublish.steamcmdDialog.title), findsNothing);

    // Avoid pending-timer/future leaks.
    completer.complete(const Ok('x'));
  });

  testWidgets('Continue in success phase pops the dialog with true',
      (tester) async {
    when(() => manager.downloadAndInstall(
          onProgress: any(named: 'onProgress'),
        )).thenAnswer((_) async => const Ok('C:/steamcmd/steamcmd.exe'));

    await pumpDialog(tester);
    await tester.tap(find.text(t.steamPublish.steamcmdDialog.install));
    await tester.pumpAndSettle();

    expect(find.text(t.steamPublish.steamcmdDialog.successTitle), findsOneWidget);

    await tester.tap(find.text(t.steamPublish.steamcmdDialog.kContinue));
    await tester.pumpAndSettle();

    expect(find.text(t.steamPublish.steamcmdDialog.title), findsNothing);
  });

  testWidgets('error result renders the error banner with the error message',
      (tester) async {
    when(() => manager.downloadAndInstall(
          onProgress: any(named: 'onProgress'),
        )).thenAnswer((_) async => const Err(
          SteamServiceException('network exploded', code: 'BOOM'),
        ));

    await pumpDialog(tester);
    await tester.tap(find.text(t.steamPublish.steamcmdDialog.install));
    await tester.pumpAndSettle();

    expect(find.text(t.steamPublish.steamcmdDialog.errorTitle), findsOneWidget);
    expect(find.text('network exploded'), findsOneWidget);
    // Error-phase actions.
    expect(find.text(t.steamPublish.steamcmdDialog.close), findsOneWidget);
    expect(find.text(t.steamPublish.steamcmdDialog.retry), findsOneWidget);
  });

  testWidgets('Retry after error re-invokes downloadAndInstall and can succeed',
      (tester) async {
    var calls = 0;
    when(() => manager.downloadAndInstall(
          onProgress: any(named: 'onProgress'),
        )).thenAnswer((_) async {
      calls++;
      return calls == 1
          ? const Err(SteamServiceException('first fail', code: 'BOOM'))
          : const Ok('C:/steamcmd/steamcmd.exe');
    });

    await pumpDialog(tester);
    await tester.tap(find.text(t.steamPublish.steamcmdDialog.install));
    await tester.pumpAndSettle();

    expect(find.text('first fail'), findsOneWidget);

    await tester.tap(find.text(t.steamPublish.steamcmdDialog.retry));
    await tester.pumpAndSettle();

    expect(find.text(t.steamPublish.steamcmdDialog.successTitle), findsOneWidget);
    verify(() => manager.downloadAndInstall(
          onProgress: any(named: 'onProgress'),
        )).called(2);
  });

  testWidgets('Close in error phase pops the dialog', (tester) async {
    when(() => manager.downloadAndInstall(
          onProgress: any(named: 'onProgress'),
        )).thenAnswer((_) async => const Err(
          SteamServiceException('nope', code: 'BOOM'),
        ));

    await pumpDialog(tester);
    await tester.tap(find.text(t.steamPublish.steamcmdDialog.install));
    await tester.pumpAndSettle();

    expect(find.text(t.steamPublish.steamcmdDialog.errorTitle), findsOneWidget);

    await tester.tap(find.text(t.steamPublish.steamcmdDialog.close));
    await tester.pumpAndSettle();

    expect(find.text(t.steamPublish.steamcmdDialog.title), findsNothing);
  });

  testWidgets('static show returns false when cancelled at confirm',
      (tester) async {
    bool? returned;
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [steamCmdManagerProvider.overrideWithValue(manager)],
        child: MaterialApp(
          theme: ThemeData.light().copyWith(extensions: [slateTokens]),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    returned = await SteamCmdInstallDialog.show(context);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.steamPublish.steamcmdDialog.cancel));
    await tester.pumpAndSettle();

    expect(returned, isFalse);
  });
}
