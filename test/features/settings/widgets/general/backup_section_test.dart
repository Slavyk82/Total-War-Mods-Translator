import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/settings/providers/backup_providers.dart';
import 'package:twmt/features/settings/widgets/general/backup_section.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

/// Fake notifier exposing a fixed [BackupState] so render branches can be
/// exercised without the real notifier reading backup/logging services.
class _FakeBackupNotifier extends BackupStateNotifier {
  _FakeBackupNotifier(this._state);

  final BackupState _state;

  @override
  BackupState build() => _state;
}

Widget _host(BackupState state) => ProviderScope(
      overrides: [
        backupStateProvider.overrideWith(() => _FakeBackupNotifier(state)),
      ],
      child: MaterialApp(
        theme: ThemeData.light().copyWith(extensions: [slateTokens]),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 600, child: BackupSection()),
          ),
        ),
      ),
    );

void main() {
  testWidgets('idle state shows both export and import actions',
      (tester) async {
    await tester.pumpWidget(_host(const BackupState()));
    await tester.pump();

    expect(find.text(t.settings.general.backup.exportTitle), findsOneWidget);
    expect(find.text(t.settings.general.backup.importTitle), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('in-progress state shows a spinner and hides the actions',
      (tester) async {
    await tester.pumpWidget(_host(
      const BackupState(isExporting: true, progressMessage: 'Creating backup...'),
    ));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Creating backup...'), findsOneWidget);
    expect(find.text(t.settings.general.backup.exportTitle), findsNothing);
  });

  testWidgets('a successful result renders the success message and path',
      (tester) async {
    await tester.pumpWidget(_host(
      BackupState(lastResult: BackupResult.exportSuccess('C:/backups/db.zip')),
    ));
    await tester.pump();

    expect(find.byIcon(FluentIcons.checkmark_circle_24_regular), findsOneWidget);
    expect(find.text('Backup created successfully'), findsOneWidget);
    expect(find.text('C:/backups/db.zip'), findsOneWidget);
  });

  testWidgets('a failed result renders the error message', (tester) async {
    await tester.pumpWidget(_host(
      const BackupState(
        lastResult: BackupResult(success: false, message: 'disk full'),
      ),
    ));
    await tester.pump();

    expect(find.byIcon(FluentIcons.error_circle_24_regular), findsOneWidget);
    expect(find.text('disk full'), findsOneWidget);
  });
}
