import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/game_translation/providers/game_translation_providers.dart';
import 'package:twmt/features/game_translation/widgets/create_game_translation/create_game_translation_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/services/game/game_localization_service.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

class _FakeSelectedGame extends SelectedGame {
  _FakeSelectedGame(this._value);

  final ConfiguredGame? _value;

  @override
  Future<ConfiguredGame?> build() async => _value;
}

const _game = ConfiguredGame(code: 'wh3', name: 'WH3', path: 'C:/wh3');

DetectedLocalPack _pack(String code) => DetectedLocalPack(
      languageCode: code,
      languageName: code.toUpperCase(),
      packFilePath: 'local_$code.pack',
      fileSizeBytes: 1024,
      lastModified: DateTime(2026, 1, 1),
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<DetectedLocalPack> packs,
}) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        selectedGameProvider.overrideWith(() => _FakeSelectedGame(_game)),
        detectedLocalPacksProvider.overrideWith((ref) async => packs),
        // Step 2 watches this; override so it never reaches the real repo/GetIt.
        allLanguagesProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp(
        theme: ThemeData.light().copyWith(extensions: [slateTokens]),
        home: const Scaffold(body: CreateGameTranslationDialog()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on step 1 with the wizard title and footer actions',
      (tester) async {
    await _pump(tester, packs: [_pack('cn')]);

    expect(find.text(t.gameTranslation.wizard.title), findsOneWidget);
    expect(find.text(t.gameTranslation.wizard.steps.selectSource), findsOneWidget);
    expect(find.text(t.gameTranslation.wizard.actions.next), findsOneWidget);
    expect(find.text(t.gameTranslation.wizard.actions.cancel), findsOneWidget);
    // No Back button on the first step.
    expect(find.text(t.gameTranslation.wizard.actions.back), findsNothing);
  });

  testWidgets('Next without a selected source pack surfaces a validation error',
      (tester) async {
    await _pump(tester, packs: [_pack('cn')]);

    await tester.tap(find.text(t.gameTranslation.wizard.actions.next));
    await tester.pumpAndSettle();

    expect(
      find.text(t.gameTranslation.wizard.errors.selectSourcePack),
      findsOneWidget,
    );
    // Still on step 1 (did not advance to targets).
    expect(find.text(t.gameTranslation.wizard.steps.selectSource), findsOneWidget);
  });

  testWidgets('selecting a pack then Next advances to the targets step',
      (tester) async {
    await _pump(tester, packs: [_pack('cn')]);

    // Select the source pack by tapping its row (identified by the pack
    // filename, to avoid the header's close button).
    await tester.tap(
      find
          .ancestor(
            of: find.text('local_cn.pack'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.gameTranslation.wizard.actions.next));
    await tester.pumpAndSettle();

    expect(find.text(t.gameTranslation.wizard.steps.selectTargets), findsOneWidget);
    // The Create action replaces Next on the final step.
    expect(find.text(t.gameTranslation.wizard.actions.create), findsOneWidget);
    expect(find.text(t.gameTranslation.wizard.actions.back), findsOneWidget);
  });
}
