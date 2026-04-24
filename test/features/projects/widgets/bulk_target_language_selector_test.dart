import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/features/projects/providers/bulk_target_language_provider.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/widgets/bulk_target_language_selector.dart';
import 'package:twmt/models/domain/language.dart';

final _fakeLanguages = [
  const Language(
    id: '1',
    code: 'fr',
    name: 'French',
    nativeName: 'Français',
  ),
  const Language(
    id: '2',
    code: 'de',
    name: 'German',
    nativeName: 'Deutsch',
  ),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders a dropdown with language entries', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        allLanguagesProvider.overrideWith((ref) async => _fakeLanguages),
      ],
      child: const MaterialApp(home: Scaffold(body: BulkTargetLanguageSelector())),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownMenu<String>), findsOneWidget);
    expect(find.text('Target language'), findsAtLeastNWidgets(1));
  });

  testWidgets('shows language display names in dropdown entries', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        allLanguagesProvider.overrideWith((ref) async => _fakeLanguages),
      ],
      child: const MaterialApp(home: Scaffold(body: BulkTargetLanguageSelector())),
    ));
    await tester.pumpAndSettle();
    // The DropdownMenu renders entries as text in the widget tree
    expect(find.text('French (Français)'), findsOneWidget);
    expect(find.text('German (Deutsch)'), findsOneWidget);
  });

  testWidgets('selecting a language updates bulkTargetLanguageProvider',
      (tester) async {
    // Build container with overrides
    // Pump widget referencing container
    // Simulate selecting a specific language
    // Expect container.read(bulkTargetLanguageProvider).asData?.value == 'fr'
  }, skip: true);
}
