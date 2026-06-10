import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';
import 'package:twmt/features/steam_publish/widgets/steam_id_editing.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

// Regression tests for saveWorkshopId (steam_id_editing.dart).
//
// The repositories return Result and never throw, so the old code's
// try/catch could never observe a failed write: a getById Err silently
// skipped the save and an update Err was discarded, yet the helper still
// invalidated the provider and returned true. The caller (SteamIdCell._save)
// then closed the editor and the refreshed list reverted to the old value —
// the typed Workshop ID silently vanished with a success signal. Every
// Result-level failure must now produce `false` (and an error toast).

class _MockProjectRepository extends Mock implements ProjectRepository {}

Project _baseProject() => Project(
      id: 'p1',
      name: 'P1',
      gameInstallationId: 'g',
      createdAt: 0,
      updatedAt: 0,
    );

ProjectPublishItem _item() => ProjectPublishItem(
      export: null,
      project: _baseProject(),
      languageCodes: const ['en'],
    );

/// Pumps a probe widget exposing a [WidgetRef] + [BuildContext] and invokes
/// [saveWorkshopId] through a button so the call runs inside the widget tree
/// (FluentToast needs an Overlay).
Future<bool?> _invokeSave(
  WidgetTester tester, {
  required _MockProjectRepository repo,
  required String rawInput,
}) async {
  bool? returned;

  await tester.pumpWidget(createThemedTestableWidget(
    Scaffold(
      body: Consumer(
        builder: (context, ref, _) => ElevatedButton(
          onPressed: () async {
            returned = await saveWorkshopId(
              ref: ref,
              context: context,
              item: _item(),
              rawInput: rawInput,
            );
          },
          child: const Text('save'),
        ),
      ),
    ),
    theme: AppTheme.atelierDarkTheme,
    overrides: [projectRepositoryProvider.overrideWithValue(repo)],
  ));
  await tester.pumpAndSettle();

  await tester.tap(find.text('save'));
  // Pump past the toast's 4-second auto-dismiss to drain its pending timer.
  await tester.pumpAndSettle(const Duration(seconds: 5));

  return returned;
}

void main() {
  setUpAll(() {
    registerFallbackValue(_baseProject());
  });

  setUp(() async => TestBootstrap.registerFakes());

  testWidgets(
      'returns false (no success) when projectRepo.getById returns Err',
      (tester) async {
    final repo = _MockProjectRepository();
    when(() => repo.getById('p1')).thenAnswer(
        (_) async => Err(TWMTDatabaseException('Project not found')));

    final returned =
        await _invokeSave(tester, repo: repo, rawInput: '3456789012');

    expect(returned, isFalse,
        reason: 'a getById Err means nothing was saved — reporting success '
            'closes the editor and silently discards the typed ID');
    verifyNever(() => repo.update(any()));
  });

  testWidgets(
      'returns false and surfaces an error toast when projectRepo.update '
      'returns Err', (tester) async {
    final repo = _MockProjectRepository();
    when(() => repo.getById('p1'))
        .thenAnswer((_) async => Ok(_baseProject()));
    when(() => repo.update(any())).thenAnswer(
        (_) async => Err(TWMTDatabaseException('disk I/O error')));

    bool? returned;
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            onPressed: () async {
              returned = await saveWorkshopId(
                ref: ref,
                context: context,
                item: _item(),
                rawInput: '3456789012',
              );
            },
            child: const Text('save'),
          ),
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [projectRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('save'));
    // First pump renders the toast before its auto-dismiss timer fires.
    await tester.pump();
    expect(
      find.textContaining('Failed to save Workshop id'),
      findsOneWidget,
      reason: 'a discarded update Err used to show no feedback at all',
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(returned, isFalse,
        reason: 'an update Err means the DB still holds the old value — '
            'the helper must not report success');
  });

  testWidgets('returns true when getById and update both succeed',
      (tester) async {
    final repo = _MockProjectRepository();
    when(() => repo.getById('p1'))
        .thenAnswer((_) async => Ok(_baseProject()));
    when(() => repo.update(any())).thenAnswer((invocation) async =>
        Ok(invocation.positionalArguments.first as Project));

    final returned =
        await _invokeSave(tester, repo: repo, rawInput: '3456789012');

    expect(returned, isTrue);
    final updated =
        verify(() => repo.update(captureAny())).captured.single as Project;
    expect(updated.publishedSteamId, '3456789012');
  });

  testWidgets('returns false for unparseable input without touching the repo',
      (tester) async {
    final repo = _MockProjectRepository();

    final returned =
        await _invokeSave(tester, repo: repo, rawInput: 'not-a-workshop-id');

    expect(returned, isFalse);
    verifyNever(() => repo.getById(any()));
    verifyNever(() => repo.update(any()));
  });
}
