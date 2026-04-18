// Regression test for decision 4 of the workflow-improvements spec.
//
// The Create-Project wizard (3 steps: Basic info -> Target languages ->
// Translation settings) must refuse to advance past the Target-languages step
// unless at least one language is selected. This guarantee is enforced in
// [CreateProjectDialog._validateCurrentStep] and surfaced via the exact error
// message below. If a future refactor deletes the check (or silently changes
// the copy), this test fails fast.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/widgets/create_project/create_project_dialog.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../../helpers/fakes/fake_logger.dart';
import '../../../../helpers/test_bootstrap.dart';

/// Active target language seeded into [allLanguagesProvider] so the Target
/// Languages step renders real tiles but the test never taps one — the wizard
/// must reject advancing with zero selections regardless of how many are
/// available.
const Language _french = Language(
  id: 'lang-fr',
  code: 'fr',
  name: 'French',
  nativeName: 'Français',
  isActive: true,
  isCustom: false,
);

/// Detected-mod fixture. Passing a non-null [DetectedMod] to the wizard
/// pre-fills Basic Info and starts the wizard on step 1 (Target Languages),
/// which is exactly the screen we want to exercise.
const DetectedMod _detectedMod = DetectedMod(
  workshopId: '123456',
  name: 'Test Mod',
  packFilePath: r'C:\fake\mod.pack',
);

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets(
      'CreateProjectDialog blocks advance past Target Languages '
      'with an empty selection', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        loggingServiceProvider.overrideWithValue(FakeLogger()),
        allLanguagesProvider.overrideWith((_) async => const [_french]),
      ],
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: const Scaffold(
          body: Center(child: CreateProjectDialog(detectedMod: _detectedMod)),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Sanity: wizard opened on step 2 of 3 (Target Languages) because a
    // DetectedMod was supplied, so Basic Info was auto-skipped.
    expect(find.text('Target languages'), findsOneWidget);
    // Pre-condition: the validation error is not on screen yet.
    expect(
      find.text('Please select at least one target language'),
      findsNothing,
    );

    // Attempt to advance to step 3 without selecting any language.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // The wizard must stay on the Target Languages step and surface the
    // exact error copy required by decision 4 of the spec.
    expect(
      find.text('Please select at least one target language'),
      findsOneWidget,
      reason: 'Decision 4: at least one target language is mandatory before '
          'the wizard can proceed to Translation settings.',
    );
    expect(find.text('Target languages'), findsOneWidget);
  });
}
