import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/game_translation/providers/game_translation_providers.dart';
import 'package:twmt/features/game_translation/widgets/create_game_translation/game_translation_creation_state.dart';
import 'package:twmt/features/game_translation/widgets/create_game_translation/step_select_source.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/services/game/game_localization_service.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

class _FakeSelectedGame extends SelectedGame {
  _FakeSelectedGame(this._value);

  final ConfiguredGame? _value;

  @override
  Future<ConfiguredGame?> build() async => _value;
}

const _game = ConfiguredGame(code: 'wh3', name: 'WH3', path: 'C:/wh3');

DetectedLocalPack _pack(String code, String name) => DetectedLocalPack(
      languageCode: code,
      languageName: name,
      packFilePath: 'local_$code.pack',
      fileSizeBytes: 1024,
      lastModified: DateTime(2026, 1, 1),
    );

Future<void> _pump(
  WidgetTester tester, {
  required GameTranslationCreationState state,
  required List<DetectedLocalPack> packs,
  VoidCallback? onChanged,
}) async {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        selectedGameProvider.overrideWith(() => _FakeSelectedGame(_game)),
        detectedLocalPacksProvider.overrideWith((ref) async => packs),
      ],
      child: MaterialApp(
        theme: ThemeData.light().copyWith(extensions: [slateTokens]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StepSelectSource(
              state: state,
              onStateChanged: onChanged ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the detected packs for the selected game', (tester) async {
    await _pump(
      tester,
      state: GameTranslationCreationState(),
      packs: [_pack('cn', 'Chinese'), _pack('jp', 'Japanese')],
    );

    expect(find.text('Chinese'), findsOneWidget);
    expect(find.text('local_cn.pack'), findsOneWidget);
    expect(find.text('local_jp.pack'), findsOneWidget);
  });

  testWidgets('shows the no-packs warning when none are detected',
      (tester) async {
    await _pump(
      tester,
      state: GameTranslationCreationState(),
      packs: const [],
    );

    expect(find.text(t.gameTranslation.stepSource.noPacks.title), findsOneWidget);
  });

  testWidgets('tapping a pack selects it and notifies the parent',
      (tester) async {
    final state = GameTranslationCreationState();
    var notified = 0;
    final pack = _pack('cn', 'Chinese');

    await _pump(
      tester,
      state: state,
      packs: [pack],
      onChanged: () => notified++,
    );

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();

    expect(state.selectedSourcePack, pack);
    expect(notified, 1);
  });
}
