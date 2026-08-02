import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/backup/backup_progress.dart';
import 'package:twmt/providers/backup/auto_backup_progress_provider.dart';
// slateTokens lives in tokens/, NOT in twmt_theme_tokens.dart -- that file
// declares the TwmtThemeTokens class and the context.tokens extension only.
import 'package:twmt/theme/tokens/slate_tokens.dart';
import 'package:twmt/widgets/backup/auto_backup_progress_card.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.light().copyWith(extensions: [slateTokens]),
          home: const Stack(children: [AutoBackupProgressCard()]),
        ),
      ),
    );
  }

  AutoBackupStatus notifier() =>
      container.read(autoBackupStatusProvider.notifier);

  testWidgets('renders nothing when idle', (tester) async {
    await pumpCard(tester);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('backup', findRichText: true), findsNothing);
  });

  testWidgets('shows the snapshot phase with a byte counter', (tester) async {
    notifier().report(
      const BackupProgress(phase: BackupPhase.snapshot, bytesDone: 1536),
    );
    await pumpCard(tester);

    expect(find.textContaining('Snapshotting'), findsOneWidget);
    expect(find.textContaining('1.5 KB'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the compressing phase with a byte counter',
      (tester) async {
    notifier().report(
      const BackupProgress(
        phase: BackupPhase.compressing,
        bytesDone: 5 * 1024 * 1024,
      ),
    );
    await pumpCard(tester);

    expect(find.textContaining('Compressing'), findsOneWidget);
    expect(find.textContaining('5.0 MB'), findsOneWidget);
  });

  testWidgets('the progress bar is always indeterminate', (tester) async {
    notifier().report(
      const BackupProgress(phase: BackupPhase.compressing, bytesDone: 10),
    );
    await pumpCard(tester);

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(
      bar.value,
      isNull,
      reason: 'no honest denominator exists for either phase',
    );
  });

  testWidgets('holds "done" briefly, then dismisses itself', (tester) async {
    notifier().succeeded();
    await pumpCard(tester);
    expect(find.byKey(const Key('autoBackupCard')), findsOneWidget);

    // Still visible just before the hold elapses.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byKey(const Key('autoBackupCard')), findsOneWidget);

    // Gone after it elapses (plus the fade).
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(container.read(autoBackupStatusProvider), isA<AutoBackupIdle>());
    expect(find.byKey(const Key('autoBackupCard')), findsNothing);
  });

  testWidgets('the error state persists and is not auto-dismissed',
      (tester) async {
    notifier().failed('disk on fire');
    await pumpCard(tester);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));

    expect(find.byKey(const Key('autoBackupCard')), findsOneWidget);
    expect(find.textContaining('disk on fire'), findsOneWidget);
    expect(container.read(autoBackupStatusProvider), isA<AutoBackupError>());
  });

  testWidgets('the error state is dismissed by its close button',
      (tester) async {
    notifier().failed('disk on fire');
    await pumpCard(tester);

    await tester.tap(find.byKey(const Key('autoBackupDismiss')));
    await tester.pumpAndSettle();

    expect(container.read(autoBackupStatusProvider), isA<AutoBackupIdle>());
  });

  testWidgets(
      'cancels the "done" hold timer on dispose, so it never fires after '
      'the widget tree is gone', (tester) async {
    notifier().succeeded();
    await pumpCard(tester);
    expect(find.byKey(const Key('autoBackupCard')), findsOneWidget);

    // Unmount while the ~1.5 s hold timer is still pending. If dispose()
    // did not cancel it, flutter_test's own pending-timer invariant fails
    // this test at tearDown with "A Timer is still pending even after the
    // widget tree was disposed" -- no explicit expect needed.
    await tester.pumpWidget(const SizedBox());
  });
}
