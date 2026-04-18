// Widget test for the "Reset onboarding hints" control surfaced in the
// General settings tab's Maintenance section — workflow-improvements · Task 5.
//
// The control must write
// [SettingsKeys.workshopOnboardingCardHidden] = `false` so a user who
// permanently dismissed the Workshop onboarding card can bring it back.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:twmt/features/settings/providers/settings_providers.dart'
    hide settingsServiceProvider;
import 'package:twmt/features/settings/widgets/general/maintenance_section.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/settings_repository.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Records the last `setBool` call so the test can assert the key and value
/// the reset-onboarding handler writes.
class _RecordingSettingsService extends SettingsService {
  _RecordingSettingsService() : super(_UnusedSettingsRepository());

  String? lastBoolKey;
  bool? lastBoolValue;

  @override
  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    return defaultValue;
  }

  @override
  Future<Result<void, TWMTDatabaseException>> setBool(
    String key,
    bool value,
  ) async {
    lastBoolKey = key;
    lastBoolValue = value;
    return const Ok(null);
  }
}

/// The base [SettingsService] constructor needs *some* repository instance —
/// it's never hit because every method we call is overridden.
class _UnusedSettingsRepository extends SettingsRepository {}

List<Override> _overrides(_RecordingSettingsService fake) => [
      settingsServiceProvider.overrideWithValue(fake),
    ];

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets(
      'tapping "Reset onboarding hints" writes workshopOnboardingCardHidden=false',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final fake = _RecordingSettingsService();

    await tester.pumpWidget(createThemedTestableWidget(
      const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: MaintenanceSection(),
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: _overrides(fake),
    ));
    await tester.pumpAndSettle();

    // The label must be exact so users can find it.
    final button = find.text('Reset onboarding hints');
    expect(button, findsOneWidget,
        reason: 'Reset onboarding hints control must be present');

    // Scroll it into the viewport if needed, then tap.
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    // Let the async handler run and the toast open, without using
    // pumpAndSettle which would hang on the toast's 4s auto-dismiss timer.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fake.lastBoolKey, SettingsKeys.workshopOnboardingCardHidden);
    expect(fake.lastBoolValue, isFalse);

    // Drain the toast's auto-dismiss timer so the test binding doesn't
    // complain about pending timers during teardown.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
