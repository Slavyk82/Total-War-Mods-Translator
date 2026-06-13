// Widget coverage tests for
// lib/features/steam_publish/widgets/workshop_publish_settings_dialog.dart.
//
// The dialog is a token-themed popup that configures the default Workshop
// publish templates. On `initState` it reads the saved title template,
// description template and default-visibility name from the `SettingsService`
// (mocked here), shows a loading spinner while reading, then renders a title
// TextField, a multiline description TextField and a visibility dropdown.
// Tapping Save writes all three values back through the service and pops
// `true`; Cancel pops `false`.
//
// These tests override the shared `settingsServiceProvider` with a mocktail
// `SettingsService`, drive the empty-store and pre-filled-store paths, edit
// each field, change the visibility dropdown, and assert the popped result and
// the exact `setString` arguments for both the save and cancel flows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/config/settings_keys.dart';
import 'package:twmt/features/steam_publish/widgets/workshop_publish_settings_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/services/steam/models/workshop_publish_params.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

class MockSettingsService extends Mock implements SettingsService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSettingsService settings;

  /// Records of every `setString(key, value)` the dialog performs on save.
  late List<(String, String)> writes;

  setUp(() {
    settings = MockSettingsService();
    writes = <(String, String)>[];

    // Default read stubs: empty store.
    when(() => settings.getString(any(),
        defaultValue: any(named: 'defaultValue'))).thenAnswer((_) async => '');

    when(() => settings.setString(any(), any())).thenAnswer((invocation) async {
      writes.add((
        invocation.positionalArguments[0] as String,
        invocation.positionalArguments[1] as String,
      ));
      return const Ok<void, TWMTDatabaseException>(null);
    });
  });

  // Order inside the body Column: 0 = title template, 1 = description template.
  Finder titleField() => find.byType(TextField).at(0);
  Finder descriptionField() => find.byType(TextField).at(1);

  Future<void> pumpHost(
    WidgetTester tester,
    List<bool> resultHolder,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      createThemedTestableWidget(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await WorkshopPublishSettingsDialog.show(context);
                resultHolder.add(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
        theme: AppTheme.atelierDarkTheme,
        overrides: [
          settingsServiceProvider.overrideWithValue(settings),
        ],
      ),
    );
  }

  /// Open the dialog (via `useRootNavigator: false` semantics through `show`)
  /// and settle past the async settings read.
  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<bool> resultHolder,
  }) async {
    await pumpHost(tester, resultHolder);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the loading spinner before templates are read',
      (tester) async {
    await pumpHost(tester, <bool>[]);

    await tester.tap(find.text('open'));
    // One frame: the dialog mounts with _loading == true, before the async
    // settings read resolves.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.text(t.steamPublish.settingsDialog.titleTemplateLabel),
      findsNothing,
    );

    await tester.pumpAndSettle();
  });

  testWidgets('renders all fields once the (empty) store is read',
      (tester) async {
    await pumpDialog(tester, resultHolder: <bool>[]);

    expect(find.text(t.steamPublish.settingsDialog.title), findsOneWidget);
    expect(
      find.text(t.steamPublish.settingsDialog.titleTemplateLabel),
      findsOneWidget,
    );
    expect(
      find.text(t.steamPublish.settingsDialog.descriptionTemplateLabel),
      findsOneWidget,
    );
    expect(
      find.text(t.steamPublish.settingsDialog.defaultVisibilityLabel),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byType(DropdownButtonFormField<WorkshopVisibility?>),
        findsOneWidget);

    // Empty store -> blank title field.
    expect(
      tester.widget<TextField>(titleField()).controller?.text,
      isEmpty,
    );
  });

  testWidgets('pre-fills title/description and selects the stored visibility',
      (tester) async {
    when(() => settings.getString(SettingsKeys.workshopTitleTemplate,
            defaultValue: any(named: 'defaultValue')))
        .thenAnswer((_) async => r'$modName - FR');
    when(() => settings.getString(SettingsKeys.workshopDescriptionTemplate,
            defaultValue: any(named: 'defaultValue')))
        .thenAnswer((_) async => r'FR translation for $modName');
    when(() => settings.getString(SettingsKeys.workshopDefaultVisibility,
            defaultValue: any(named: 'defaultValue')))
        .thenAnswer((_) async => WorkshopVisibility.unlisted.name);

    await pumpDialog(tester, resultHolder: <bool>[]);

    expect(
      tester.widget<TextField>(titleField()).controller?.text,
      r'$modName - FR',
    );
    expect(
      tester.widget<TextField>(descriptionField()).controller?.text,
      r'FR translation for $modName',
    );
    // The dropdown shows the stored visibility's label.
    expect(find.text(WorkshopVisibility.unlisted.label), findsOneWidget);
  });

  testWidgets('falls back to Public when stored visibility is unknown',
      (tester) async {
    when(() => settings.getString(SettingsKeys.workshopDefaultVisibility,
            defaultValue: any(named: 'defaultValue')))
        .thenAnswer((_) async => 'not_a_real_visibility');

    await pumpDialog(tester, resultHolder: <bool>[]);

    expect(find.text(WorkshopVisibility.public_.label), findsOneWidget);
  });

  testWidgets('cancel pops false and writes nothing', (tester) async {
    final results = <bool>[];
    await pumpDialog(tester, resultHolder: results);

    await tester.tap(find.text(t.steamPublish.settingsDialog.cancel));
    await tester.pumpAndSettle();

    expect(find.text(t.steamPublish.settingsDialog.title), findsNothing);
    expect(results, hasLength(1));
    expect(results.single, isFalse);
    expect(writes, isEmpty);
  });

  testWidgets('editing the fields and saving writes the edited values + pops',
      (tester) async {
    final results = <bool>[];
    await pumpDialog(tester, resultHolder: results);

    await tester.enterText(titleField(), r'$modName [EN]');
    await tester.enterText(descriptionField(), 'Translated description');
    await tester.pump();

    await tester.tap(find.text(t.steamPublish.settingsDialog.save));
    await tester.pumpAndSettle();

    // Dialog popped with true.
    expect(find.text(t.steamPublish.settingsDialog.title), findsNothing);
    expect(results, hasLength(1));
    expect(results.single, isTrue);

    // All three keys were written with the edited values.
    final writeMap = {for (final w in writes) w.$1: w.$2};
    expect(writeMap[SettingsKeys.workshopTitleTemplate], r'$modName [EN]');
    expect(
      writeMap[SettingsKeys.workshopDescriptionTemplate],
      'Translated description',
    );
    // Default visibility was Public when nothing stored.
    expect(
      writeMap[SettingsKeys.workshopDefaultVisibility],
      WorkshopVisibility.public_.name,
    );
  });

  testWidgets('changing the visibility dropdown persists the chosen value',
      (tester) async {
    final results = <bool>[];
    await pumpDialog(tester, resultHolder: results);

    // Open the dropdown and pick "Friends Only".
    await tester.tap(
      find.byType(DropdownButtonFormField<WorkshopVisibility?>),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(WorkshopVisibility.friendsOnly.label).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.steamPublish.settingsDialog.save));
    await tester.pumpAndSettle();

    final writeMap = {for (final w in writes) w.$1: w.$2};
    expect(
      writeMap[SettingsKeys.workshopDefaultVisibility],
      WorkshopVisibility.friendsOnly.name,
    );
    expect(results.single, isTrue);
  });

  testWidgets('selecting "No default" persists an empty visibility name',
      (tester) async {
    // Start with a stored visibility so the dropdown is non-null first.
    when(() => settings.getString(SettingsKeys.workshopDefaultVisibility,
            defaultValue: any(named: 'defaultValue')))
        .thenAnswer((_) async => WorkshopVisibility.private_.name);

    final results = <bool>[];
    await pumpDialog(tester, resultHolder: results);

    await tester.tap(
      find.byType(DropdownButtonFormField<WorkshopVisibility?>),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.steamPublish.settingsDialog.noDefault).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.steamPublish.settingsDialog.save));
    await tester.pumpAndSettle();

    final writeMap = {for (final w in writes) w.$1: w.$2};
    // `_defaultVisibility?.name ?? ''` -> empty string for the null option.
    expect(writeMap[SettingsKeys.workshopDefaultVisibility], '');
    expect(results.single, isTrue);
  });

  testWidgets('static show returns false when the dialog is dismissed null',
      (tester) async {
    // Drive the barrier-dismiss path: show() returns null -> false.
    final results = <bool>[];
    await pumpDialog(tester, resultHolder: results);

    // Tap the modal barrier outside the dialog to dismiss it.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text(t.steamPublish.settingsDialog.title), findsNothing);
    expect(results, hasLength(1));
    expect(results.single, isFalse);
  });
}
