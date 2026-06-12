import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/config/app_constants.dart';
import 'package:twmt/features/settings/widgets/general/pack_prefix_section.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/settings_providers.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

/// Fake settings notifier that records the persisted prefix instead of
/// writing through the real settings service.
class _FakeGeneralSettings extends GeneralSettings {
  String? lastPrefix;

  @override
  Future<Map<String, String>> build() async => {};

  @override
  Future<void> updatePackPrefix(String prefix) async {
    lastPrefix = prefix;
  }
}

void main() {
  late _FakeGeneralSettings fake;

  Widget host(String initialPrefix) {
    fake = _FakeGeneralSettings();
    return ProviderScope(
      overrides: [generalSettingsProvider.overrideWith(() => fake)],
      child: MaterialApp(
        theme: ThemeData.light().copyWith(extensions: [slateTokens]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 600,
              child: PackPrefixSection(initialPrefix: initialPrefix),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders the live preview from the initial prefix',
      (tester) async {
    await tester.pumpWidget(host('abc'));
    await tester.pump();

    expect(find.text('abc_fr_twmt_mod.pack'), findsOneWidget);
    expect(find.text('text/db/abc_fr_twmt_text.loc'), findsOneWidget);
  });

  testWidgets('typing updates the preview and persists the sanitized prefix',
      (tester) async {
    await tester.pumpWidget(host('abc'));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'zz');
    await tester.pump();

    expect(find.text('zz_fr_twmt_mod.pack'), findsOneWidget);
    expect(fake.lastPrefix, 'zz');
  });

  testWidgets('reset restores the default prefix and persists it',
      (tester) async {
    await tester.pumpWidget(host('abc'));
    await tester.pump();

    await tester.tap(find.text(t.settings.general.packPrefix.resetButton));
    await tester.pump();

    final def = AppConstants.defaultPackPrefix;
    expect(find.text('${def}_fr_twmt_mod.pack'), findsOneWidget);
    expect(fake.lastPrefix, def);
  });
}
