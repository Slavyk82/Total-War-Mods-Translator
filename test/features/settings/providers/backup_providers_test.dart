import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/settings/providers/backup_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/backup/database_backup_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

// Regression tests for BackupStateNotifier (autoDispose).
//
// exportBackup / importBackup used to write `state` after the long-running
// createBackup/restoreBackup awaits without checking `ref.mounted`. The
// provider's only watcher is the Backup section on the General settings tab
// and the UI is not modal during the operation; switching tabs or leaving
// Settings disposes the provider mid-await. The state write then threw
// UnmountedRefException, the catch block's own state write rethrew it, and
// importBackup never returned its bool — an unhandled async error right
// after a destructive DB restore. The backup/restore work itself must still
// run to completion — only the state writes are guarded.

class _MockBackupService extends Mock implements DatabaseBackupService {}

void main() {
  late _MockBackupService backupService;
  late ProviderContainer container;

  setUp(() {
    backupService = _MockBackupService();

    container = ProviderContainer(overrides: [
      databaseBackupServiceProvider.overrideWithValue(backupService),
      loggingServiceProvider.overrideWithValue(FakeLogger()),
    ]);
    addTearDown(container.dispose);
  });

  group('exportBackup', () {
    test('updates state with success result while watched', () async {
      when(() => backupService.createBackup(any()))
          .thenAnswer((_) async => const Ok('C:/backups/twmt.zip'));

      final subscription = container.listen(backupStateProvider, (_, _) {});
      addTearDown(subscription.close);
      final notifier = container.read(backupStateProvider.notifier);

      await notifier.exportBackup('C:/backups/twmt.zip');

      final state = container.read(backupStateProvider);
      expect(state.isExporting, isFalse);
      expect(state.lastResult!.success, isTrue);
      expect(state.lastResult!.filePath, 'C:/backups/twmt.zip');
    });

    test(
        'completes without UnmountedRefException when the provider is '
        'disposed mid-backup, and still runs the backup to completion',
        () async {
      final backupStarted = Completer<void>();
      final releaseBackup = Completer<void>();
      var backupCompleted = false;

      when(() => backupService.createBackup(any())).thenAnswer((_) async {
        backupStarted.complete();
        await releaseBackup.future;
        backupCompleted = true;
        return const Ok('C:/backups/twmt.zip');
      });

      // The Backup section watching the provider.
      final subscription = container.listen(backupStateProvider, (_, _) {});
      final notifier = container.read(backupStateProvider.notifier);

      final operation = notifier.exportBackup('C:/backups/twmt.zip');

      await backupStarted.future;

      // User switches settings tab: the section unmounts, removing the last
      // listener of this autoDispose provider.
      subscription.close();
      await container.pump();

      releaseBackup.complete();

      // Must complete without an UnmountedRefException.
      await operation;

      expect(backupCompleted, isTrue,
          reason: 'the backup itself must not be abandoned');
    });

    test(
        'error branch after dispose does not throw (service returns Err)',
        () async {
      final backupStarted = Completer<void>();
      final releaseBackup = Completer<void>();

      when(() => backupService.createBackup(any())).thenAnswer((_) async {
        backupStarted.complete();
        await releaseBackup.future;
        return const Err(BackupException('disk full'));
      });

      final subscription = container.listen(backupStateProvider, (_, _) {});
      final notifier = container.read(backupStateProvider.notifier);

      final operation = notifier.exportBackup('C:/backups/twmt.zip');

      await backupStarted.future;
      subscription.close();
      await container.pump();
      releaseBackup.complete();

      await operation;
    });

    test(
        'catch block is dispose-safe when the service throws after dispose',
        () async {
      final backupStarted = Completer<void>();
      final releaseBackup = Completer<void>();

      when(() => backupService.createBackup(any())).thenAnswer((_) async {
        backupStarted.complete();
        await releaseBackup.future;
        throw Exception('unexpected I/O failure');
      });

      final subscription = container.listen(backupStateProvider, (_, _) {});
      final notifier = container.read(backupStateProvider.notifier);

      final operation = notifier.exportBackup('C:/backups/twmt.zip');

      await backupStarted.future;
      subscription.close();
      await container.pump();
      releaseBackup.complete();

      await operation;
    });
  });

  group('importBackup', () {
    test('updates state and returns true on success while watched', () async {
      when(() => backupService.restoreBackup(any()))
          .thenAnswer((_) async => const Ok(null));

      final subscription = container.listen(backupStateProvider, (_, _) {});
      addTearDown(subscription.close);
      final notifier = container.read(backupStateProvider.notifier);

      final restored = await notifier.importBackup('C:/backups/twmt.zip');

      expect(restored, isTrue);
      final state = container.read(backupStateProvider);
      expect(state.isImporting, isFalse);
      expect(state.lastResult!.success, isTrue);
    });

    test('updates state and returns false on failure while watched',
        () async {
      when(() => backupService.restoreBackup(any())).thenAnswer((_) async =>
          const Err(BackupException('corrupt zip', requiresRestart: true)));

      final subscription = container.listen(backupStateProvider, (_, _) {});
      addTearDown(subscription.close);
      final notifier = container.read(backupStateProvider.notifier);

      final restored = await notifier.importBackup('C:/backups/twmt.zip');

      expect(restored, isFalse);
      final state = container.read(backupStateProvider);
      expect(state.lastResult!.success, isFalse);
      expect(state.lastResult!.requiresRestart, isTrue);
    });

    test(
        'returns true without UnmountedRefException when the provider is '
        'disposed mid-restore, and still runs the restore to completion',
        () async {
      final restoreStarted = Completer<void>();
      final releaseRestore = Completer<void>();
      var restoreCompleted = false;

      when(() => backupService.restoreBackup(any())).thenAnswer((_) async {
        restoreStarted.complete();
        await releaseRestore.future;
        restoreCompleted = true;
        return const Ok(null);
      });

      final subscription = container.listen(backupStateProvider, (_, _) {});
      final notifier = container.read(backupStateProvider.notifier);

      final operation = notifier.importBackup('C:/backups/twmt.zip');

      await restoreStarted.future;
      subscription.close();
      await container.pump();
      releaseRestore.complete();

      // Must complete with its bool result, not an UnmountedRefException.
      final restored = await operation;

      expect(restored, isTrue,
          reason: 'the restore succeeded; the caller must learn that');
      expect(restoreCompleted, isTrue,
          reason: 'the restore itself must not be abandoned');
    });

    test('returns false without throwing when restore fails after dispose',
        () async {
      final restoreStarted = Completer<void>();
      final releaseRestore = Completer<void>();

      when(() => backupService.restoreBackup(any())).thenAnswer((_) async {
        restoreStarted.complete();
        await releaseRestore.future;
        return const Err(BackupException('corrupt zip'));
      });

      final subscription = container.listen(backupStateProvider, (_, _) {});
      final notifier = container.read(backupStateProvider.notifier);

      final operation = notifier.importBackup('C:/backups/twmt.zip');

      await restoreStarted.future;
      subscription.close();
      await container.pump();
      releaseRestore.complete();

      final restored = await operation;

      expect(restored, isFalse);
    });

    test(
        'catch block is dispose-safe and returns false when the service '
        'throws after dispose', () async {
      final restoreStarted = Completer<void>();
      final releaseRestore = Completer<void>();

      when(() => backupService.restoreBackup(any())).thenAnswer((_) async {
        restoreStarted.complete();
        await releaseRestore.future;
        throw Exception('unexpected I/O failure');
      });

      final subscription = container.listen(backupStateProvider, (_, _) {});
      final notifier = container.read(backupStateProvider.notifier);

      final operation = notifier.importBackup('C:/backups/twmt.zip');

      await restoreStarted.future;
      subscription.close();
      await container.pump();
      releaseRestore.complete();

      final restored = await operation;

      expect(restored, isFalse);
    });
  });
}
