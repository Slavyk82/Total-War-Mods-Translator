// Widget tests for WorkshopOnboardingCard — workflow-improvements · Task 4.
//
// Covers:
// - Default rendering (title, body, checkbox, Dismiss button) when the
//   persisted flag is false.
// - Collapsed rendering (SizedBox.shrink) when the persisted flag is true.
// - Dismiss without ticking the checkbox: hides the card for the current
//   widget instance but does NOT persist.
// - Dismiss with the checkbox ticked: persists
//   [SettingsKeys.workshopOnboardingCardHidden] = true AND hides the card.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:twmt/features/settings/providers/settings_providers.dart'
    hide settingsServiceProvider;
import 'package:twmt/features/steam_publish/widgets/workshop_onboarding_card.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/settings_repository.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// In-memory fake SettingsService covering only the bool API the onboarding
/// card touches. Other methods fall through to the base class which would
/// hit the (unconfigured) repository — that's fine as long as the widget
/// never reaches them.
class _FakeSettingsService extends SettingsService {
  _FakeSettingsService({bool initialHidden = false})
      : _store = {
          if (initialHidden)
            SettingsKeys.workshopOnboardingCardHidden: true,
        },
        super(_UnusedSettingsRepository());

  final Map<String, bool> _store;

  /// Returns the current persisted value for assertion purposes.
  bool? peek(String key) => _store[key];

  @override
  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    return _store[key] ?? defaultValue;
  }

  @override
  Future<Result<void, TWMTDatabaseException>> setBool(
    String key,
    bool value,
  ) async {
    _store[key] = value;
    return const Ok(null);
  }
}

/// The base [SettingsService] constructor takes a repository — we never touch
/// it, but we need *some* instance so the super-ctor runs.
class _UnusedSettingsRepository extends SettingsRepository {}

List<Override> _overrides(_FakeSettingsService fake) => [
      settingsServiceProvider.overrideWithValue(fake),
    ];

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets(
      'renders title, body, checkbox, and Dismiss button when not persisted-hidden',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final fake = _FakeSettingsService();
    await tester.pumpWidget(createThemedTestableWidget(
      const WorkshopOnboardingCard(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _overrides(fake),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Publishing on the Steam Workshop'), findsOneWidget);

    // Body intro explains why the first publish must go through the launcher.
    expect(
      find.textContaining('original game launcher'),
      findsWidgets,
    );

    // Four numbered onboarding steps walk the user through the flow.
    for (final index in const [1, 2, 3, 4]) {
      expect(find.text('$index.'), findsOneWidget);
    }
    expect(
      find.textContaining('Publish the mod once'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Workshop ID assigned by Steam'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Paste that ID'),
      findsOneWidget,
    );
    expect(
      find.textContaining('"Update" button'),
      findsOneWidget,
    );

    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.text("Don't show this again"), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
  });

  testWidgets('renders nothing when the persisted flag is true',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final fake = _FakeSettingsService(initialHidden: true);
    await tester.pumpWidget(createThemedTestableWidget(
      const WorkshopOnboardingCard(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _overrides(fake),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Publishing on the Steam Workshop'), findsNothing);
    expect(find.text('Dismiss'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets(
      'Dismiss without checkbox hides for session but does not persist',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final fake = _FakeSettingsService();
    await tester.pumpWidget(createThemedTestableWidget(
      const WorkshopOnboardingCard(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _overrides(fake),
    ));
    await tester.pumpAndSettle();

    // Sanity: the card is visible.
    expect(find.text('Publishing on the Steam Workshop'), findsOneWidget);

    // Tap Dismiss without ticking the checkbox.
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();

    // The card is no longer on screen in this session.
    expect(find.text('Publishing on the Steam Workshop'), findsNothing);

    // Nothing was persisted.
    expect(fake.peek(SettingsKeys.workshopOnboardingCardHidden), isNull);
  });

  testWidgets('Dismiss with checkbox ticked persists the flag',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final fake = _FakeSettingsService();
    await tester.pumpWidget(createThemedTestableWidget(
      const WorkshopOnboardingCard(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _overrides(fake),
    ));
    await tester.pumpAndSettle();

    // Tick "Don't show this again".
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    // Dismiss.
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();

    // The card is no longer visible.
    expect(find.text('Publishing on the Steam Workshop'), findsNothing);

    // The flag is persisted.
    expect(fake.peek(SettingsKeys.workshopOnboardingCardHidden), isTrue);
  });
}
