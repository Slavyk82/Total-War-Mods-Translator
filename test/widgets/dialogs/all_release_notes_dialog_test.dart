// Widget coverage tests for lib/widgets/dialogs/all_release_notes_dialog.dart.
//
// The dialog is a pure StatelessWidget that takes a list of [GitHubRelease]
// entries (no providers) and renders them in a token-themed [TokenDialog]:
// a header + subtitle, a scrollable list of expansion tiles (the first one
// expanded by default rendering markdown + a "View on GitHub" button), an
// empty-state when the list is empty, and a "Got it" close action.
//
// These tests render the multi-entry list, toggle a tile's expansion, exercise
// the empty state, scroll the list, and pop the dialog via the close button.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/domain/github_release.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';
import 'package:twmt/widgets/dialogs/all_release_notes_dialog.dart';

GitHubRelease _release({
  required String tag,
  String name = '',
  String body = 'Some **markdown** body',
  DateTime? publishedAt,
  String htmlUrl = 'https://example.com/release',
}) {
  return GitHubRelease(
    tagName: tag,
    name: name,
    body: body,
    isDraft: false,
    isPrerelease: false,
    publishedAt: publishedAt ?? DateTime(2024, 3, 15),
    htmlUrl: htmlUrl,
    assets: const [],
  );
}

void main() {
  // Swallow url_launcher platform-channel calls so a "View on GitHub" tap
  // does not throw MissingPluginException during the test.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        if (call.method == 'canLaunch') return true;
        if (call.method == 'launch') return true;
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      null,
    );
  });

  Future<void> pumpDialog(
    WidgetTester tester,
    List<GitHubRelease> releases,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.light().copyWith(extensions: [slateTokens]),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => AllReleaseNotesDialog(releases: releases),
                  ),
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
  }

  testWidgets('renders title, plural subtitle, and version badges for a list',
      (tester) async {
    final releases = [
      _release(tag: 'v3.0.0', name: 'Big Release'),
      _release(tag: 'v2.0.0', name: 'Older Release'),
      _release(tag: 'v1.0.0', name: 'Oldest Release'),
    ];

    await pumpDialog(tester, releases);

    expect(
      find.text(t.releaseNotes.dialogs.releaseHistory.title),
      findsOneWidget,
    );
    expect(
      find.text(
        t.releaseNotes.dialogs.releaseHistory.subtitleMany(count: 3),
      ),
      findsOneWidget,
    );

    // Version badges for every entry are rendered.
    expect(find.text('v3.0.0'), findsOneWidget);
    expect(find.text('v2.0.0'), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);

    // Names are shown.
    expect(find.text('Big Release'), findsOneWidget);
    expect(find.text('Older Release'), findsOneWidget);

    // The first tile is expanded by default => its "View on GitHub" button and
    // the formatted date are visible.
    expect(find.text(t.releaseNotes.actions.viewOnGitHub), findsOneWidget);
    expect(find.text('15 Mar 2024'), findsWidgets);
  });

  testWidgets('renders singular subtitle for a single release', (tester) async {
    await pumpDialog(tester, [_release(tag: 'v1.2.3', name: 'Solo')]);

    expect(
      find.text(t.releaseNotes.dialogs.releaseHistory.subtitleOne(count: 1)),
      findsOneWidget,
    );
    expect(find.text('v1.2.3'), findsOneWidget);
  });

  testWidgets('falls back to release prefix when name is empty',
      (tester) async {
    await pumpDialog(tester, [_release(tag: 'v9.9.9', name: '')]);

    expect(
      find.text(
        t.releaseNotes.dialogs.whatsNew.releasePrefix(version: '9.9.9'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('expanding a collapsed tile reveals its body', (tester) async {
    final releases = [
      _release(tag: 'v2.0.0', name: 'First', body: 'first body'),
      _release(tag: 'v1.0.0', name: 'Second', body: 'second body text'),
    ];

    await pumpDialog(tester, releases);

    // Second tile is collapsed initially.
    expect(find.textContaining('second body text'), findsNothing);

    await tester.tap(find.text('Second'));
    await tester.pumpAndSettle();

    expect(find.textContaining('second body text'), findsOneWidget);
  });

  testWidgets('collapsing the first (expanded) tile hides its body',
      (tester) async {
    await pumpDialog(tester, [
      _release(tag: 'v2.0.0', name: 'First', body: 'unique first body'),
    ]);

    expect(find.textContaining('unique first body'), findsOneWidget);

    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();

    expect(find.textContaining('unique first body'), findsNothing);
  });

  testWidgets('expanded tile with empty body shows the fallback notice',
      (tester) async {
    await pumpDialog(tester, [
      _release(tag: 'v1.0.0', name: 'Empty Body', body: ''),
    ]);

    expect(
      find.textContaining(
        t.releaseNotes.dialogs.releaseHistory.noReleasesAvailable,
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping "View on GitHub" does not throw', (tester) async {
    await pumpDialog(tester, [
      _release(tag: 'v1.0.0', name: 'WithLink'),
    ]);

    await tester.tap(find.text(t.releaseNotes.actions.viewOnGitHub));
    await tester.pumpAndSettle();

    // Still rendered, no exception surfaced.
    expect(find.text('v1.0.0'), findsOneWidget);
  });

  testWidgets('renders the empty state when there are no releases',
      (tester) async {
    await pumpDialog(tester, const []);

    expect(
      find.text(t.releaseNotes.dialogs.releaseHistory.noNotes),
      findsOneWidget,
    );
    // No expansion tiles / GitHub buttons in the empty state.
    expect(find.text(t.releaseNotes.actions.viewOnGitHub), findsNothing);
    expect(
      find.text(
        t.releaseNotes.dialogs.releaseHistory.subtitleMany(count: 0),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the release list is scrollable', (tester) async {
    final releases = [
      for (var i = 0; i < 20; i++)
        _release(tag: 'v$i.0.0', name: 'Release number $i'),
    ];

    await pumpDialog(tester, releases);

    expect(find.byType(Scrollable), findsWidgets);
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    // After scrolling the dialog is still present.
    expect(
      find.text(t.releaseNotes.dialogs.releaseHistory.title),
      findsOneWidget,
    );
  });

  testWidgets('the "Got it" button pops the dialog', (tester) async {
    await pumpDialog(tester, [_release(tag: 'v1.0.0', name: 'Closing')]);

    expect(
      find.text(t.releaseNotes.dialogs.releaseHistory.title),
      findsOneWidget,
    );

    await tester.tap(find.text(t.releaseNotes.actions.gotIt));
    await tester.pumpAndSettle();

    expect(
      find.text(t.releaseNotes.dialogs.releaseHistory.title),
      findsNothing,
    );
  });
}
