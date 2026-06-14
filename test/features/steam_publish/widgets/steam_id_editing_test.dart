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
import 'package:twmt/repositories/project_publication_repository.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

// Regression tests for saveWorkshopId (steam_id_editing.dart).
//
// The ProjectPublishItem branch now writes to project_publication via
// setSteamId instead of reading and updating the projects table. Every
// Result-level failure must produce `false` (and an error toast).

class _MockProjectPublicationRepository extends Mock
    implements ProjectPublicationRepository {}

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
  required _MockProjectPublicationRepository repo,
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
    overrides: [projectPublicationRepositoryProvider.overrideWithValue(repo)],
  ));
  await tester.pumpAndSettle();

  await tester.tap(find.text('save'));
  // Pump past the toast's 4-second auto-dismiss to drain its pending timer.
  await tester.pumpAndSettle(const Duration(seconds: 5));

  return returned;
}

void main() {
  setUp(() async => TestBootstrap.registerFakes());

  testWidgets('returns false (no success) when setSteamId returns Err',
      (tester) async {
    final repo = _MockProjectPublicationRepository();
    when(() => repo.setSteamId(any(), any(), any())).thenAnswer(
        (_) async => Err(TWMTDatabaseException('disk I/O error')));

    final returned =
        await _invokeSave(tester, repo: repo, rawInput: '3456789012');

    expect(returned, isFalse,
        reason: 'a setSteamId Err means nothing was saved — reporting success '
            'closes the editor and silently discards the typed ID');
  });

  testWidgets(
      'returns false and surfaces an error toast when setSteamId returns Err',
      (tester) async {
    final repo = _MockProjectPublicationRepository();
    when(() => repo.setSteamId(any(), any(), any())).thenAnswer(
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
      overrides: [projectPublicationRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('save'));
    // First pump renders the toast before its auto-dismiss timer fires.
    await tester.pump();
    expect(
      find.textContaining('Failed to save Workshop id'),
      findsOneWidget,
      reason: 'a setSteamId Err must surface an error toast',
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(returned, isFalse,
        reason: 'a setSteamId Err means the DB still holds the old value — '
            'the helper must not report success');
  });

  testWidgets('returns true and calls setSteamId with correct args on success',
      (tester) async {
    final repo = _MockProjectPublicationRepository();
    when(() => repo.setSteamId(any(), any(), any()))
        .thenAnswer((_) async => const Ok(null));

    final returned =
        await _invokeSave(tester, repo: repo, rawInput: '3456789012');

    expect(returned, isTrue);
    verify(() => repo.setSteamId('p1', 'en', '3456789012')).called(1);
  });

  testWidgets('returns false for unparseable input without touching the repo',
      (tester) async {
    final repo = _MockProjectPublicationRepository();

    final returned =
        await _invokeSave(tester, repo: repo, rawInput: 'not-a-workshop-id');

    expect(returned, isFalse);
    verifyNever(() => repo.setSteamId(any(), any(), any()));
  });
}
