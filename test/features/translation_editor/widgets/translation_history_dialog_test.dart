import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/widgets/translation_history_dialog.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/models/domain/translation_version_history.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/translation_version_history_repository.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

class _MockHistoryRepo extends Mock
    implements TranslationVersionHistoryRepository {}

const _versionId = 'version-a';

TranslationVersionHistory _entry({
  required String id,
  required String text,
  required TranslationVersionStatus status,
  required String changedBy,
  String? reason,
}) =>
    TranslationVersionHistory(
      id: id,
      versionId: _versionId,
      translatedText: text,
      status: status,
      changedBy: changedBy,
      changeReason: reason,
      createdAt: 1700000000,
    );

void main() {
  late _MockHistoryRepo repo;

  setUp(() {
    repo = _MockHistoryRepo();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1400, 1600);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const TranslationHistoryDialog(
                versionId: _versionId,
                unitKey: 'greeting',
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        translationVersionHistoryRepositoryProvider.overrideWithValue(repo),
      ],
    ));
    await tester.tap(find.text('open'));
  }

  testWidgets('shows a spinner while history is loading', (tester) async {
    when(() => repo.getByVersion(_versionId)).thenAnswer(
      (_) => Completer<
          Result<List<TranslationVersionHistory>, TWMTDatabaseException>>()
          .future,
    );

    await pumpDialog(tester);
    await tester.pump(); // build dialog
    await tester.pump(const Duration(milliseconds: 200)); // entrance animation

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the empty state when there is no history',
      (tester) async {
    when(() => repo.getByVersion(_versionId)).thenAnswer(
      (_) async =>
          const Ok<List<TranslationVersionHistory>, TWMTDatabaseException>([]),
    );

    await pumpDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text('No history available'), findsOneWidget);
  });

  testWidgets('shows the error state when loading fails', (tester) async {
    when(() => repo.getByVersion(_versionId)).thenAnswer(
      (_) async => Err<List<TranslationVersionHistory>, TWMTDatabaseException>(
        const TWMTDatabaseException('boom'),
      ),
    );

    await pumpDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text('Error loading history'), findsOneWidget);
  });

  testWidgets('renders history entries with status, author, text and reason',
      (tester) async {
    when(() => repo.getByVersion(_versionId)).thenAnswer(
      (_) async => Ok<List<TranslationVersionHistory>, TWMTDatabaseException>([
        _entry(
          id: 'h-1',
          text: 'Bonjour',
          status: TranslationVersionStatus.translated,
          changedBy: 'user',
          reason: 'Manual edit',
        ),
        _entry(
          id: 'h-2',
          text: 'Salut',
          status: TranslationVersionStatus.needsReview,
          changedBy: 'provider_anthropic',
        ),
      ]),
    );

    await pumpDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text('Bonjour'), findsOneWidget);
    expect(find.text('Salut'), findsOneWidget);
    expect(find.text('Translated'), findsOneWidget);
    expect(find.text('Needs Review'), findsOneWidget);
    expect(find.text('User'), findsOneWidget);
    expect(find.text('Anthropic'), findsOneWidget); // provider_ prefix stripped
    expect(find.text('Reason: Manual edit'), findsOneWidget);
  });

  testWidgets('Close button dismisses the dialog', (tester) async {
    when(() => repo.getByVersion(_versionId)).thenAnswer(
      (_) async =>
          const Ok<List<TranslationVersionHistory>, TWMTDatabaseException>([]),
    );

    await pumpDialog(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Translation History'), findsNothing);
  });
}
