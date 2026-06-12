import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/settings/widgets/general/workshop_section.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/settings_providers.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

/// Records the persisted workshop path instead of writing to settings.
class _FakeGeneralSettings extends GeneralSettings {
  String? lastWorkshopPath;

  @override
  Future<Map<String, String>> build() async => {};

  @override
  Future<void> updateWorkshopPath(String path) async {
    lastWorkshopPath = path;
  }
}

void main() {
  late _FakeGeneralSettings fake;
  late TextEditingController controller;

  Widget host() {
    fake = _FakeGeneralSettings();
    controller = TextEditingController(text: 'C:/existing/path');
    return ProviderScope(
      overrides: [generalSettingsProvider.overrideWith(() => fake)],
      child: MaterialApp(
        theme: ThemeData.light().copyWith(extensions: [slateTokens]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 700,
              child: WorkshopSection(workshopPathController: controller),
            ),
          ),
        ),
      ),
    );
  }

  tearDown(() => controller.dispose());

  testWidgets('renders the path field with detect and browse actions',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.text('C:/existing/path'), findsOneWidget);
    expect(find.text(t.settings.general.workshop.detectButton), findsOneWidget);
    expect(find.text(t.settings.general.workshop.browseButton), findsOneWidget);
  });

  testWidgets('editing the field persists the new workshop path',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'D:/steam/workshop');
    await tester.pump();

    expect(fake.lastWorkshopPath, 'D:/steam/workshop');
  });
}
