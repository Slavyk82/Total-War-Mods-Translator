import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/settings/widgets/dialogs/backup_restore_confirmation_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

/// Pumps a button that opens the dialog and records its pop result.
Future<List<bool?>> _openDialog(WidgetTester tester) async {
  final results = <bool?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light().copyWith(extensions: [slateTokens]),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              results.add(await showDialog<bool>(
                context: context,
                builder: (_) => const BackupRestoreConfirmationDialog(
                  backupFileName: 'twmt_backup.zip',
                ),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('shows the backup filename and the destructive warning',
      (tester) async {
    await _openDialog(tester);

    expect(find.text('twmt_backup.zip'), findsOneWidget);
    expect(find.text(t.settings.backupRestoreDialog.warningTitle), findsOneWidget);
  });

  testWidgets('Restore pops true', (tester) async {
    final results = await _openDialog(tester);

    await tester.tap(find.text(t.settings.backupRestoreDialog.restore));
    await tester.pumpAndSettle();

    expect(results.single, isTrue);
  });

  testWidgets('Cancel pops false', (tester) async {
    final results = await _openDialog(tester);

    await tester.tap(find.text(t.settings.backupRestoreDialog.cancel));
    await tester.pumpAndSettle();

    expect(results.single, isFalse);
  });
}
