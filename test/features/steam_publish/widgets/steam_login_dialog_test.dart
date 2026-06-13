// Widget coverage tests for
// lib/features/steam_publish/widgets/steam_login_dialog.dart.
//
// The dialog is a self-contained credentials popup: on `initState` it reads any
// saved username/password from `flutter_secure_storage` (mocked here via the
// `plugins.it_nomads.com/flutter_secure_storage` MethodChannel), renders a
// loading spinner while reading, then shows username / password / Steam-Guard
// fields and a "remember credentials" toggle. Submitting validates the form,
// writes-or-clears the saved credentials, and pops a
// `(username, password, steamGuardCode?)` tuple. Cancel pops `null`.
//
// These tests drive the secure-storage channel to exercise the empty-store and
// pre-filled-store paths, type into every field (located by render order:
// 0 = username, 1 = password, 2 = Steam-Guard), toggle the obscure-password
// and remember toggles, assert validation errors, and verify the popped result
// for both the cancel and submit (with/without a valid Guard code) flows.
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:twmt/config/settings_keys.dart';
import 'package:twmt/features/steam_publish/widgets/steam_login_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The channel the flutter_secure_storage platform implementation talks to.
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  // Mutable in-memory store backing the mocked channel. Tests pre-seed it and
  // inspect the writes/deletes the dialog performs.
  late Map<String, String?> store;
  late List<MethodCall> calls;

  setUp(() {
    store = <String, String?>{};
    calls = <MethodCall>[];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      calls.add(call);
      final args = (call.arguments as Map?) ?? const {};
      final key = args['key'] as String? ?? '';
      switch (call.method) {
        case 'read':
          return store[key];
        case 'write':
          store[key] = args['value'] as String?;
          return null;
        case 'delete':
          store.remove(key);
          return null;
        case 'readAll':
          return Map<String, String?>.from(store);
        case 'deleteAll':
          store.clear();
          return null;
        case 'containsKey':
          return store.containsKey(key);
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  // Fields by render order inside the Form.
  Finder usernameField() => find.byType(TextFormField).at(0);
  Finder passwordField() => find.byType(TextFormField).at(1);
  Finder guardField() => find.byType(TextFormField).at(2);

  Future<void> pumpHost(
    WidgetTester tester,
    List<Object?> resultHolder,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.light().copyWith(extensions: [slateTokens]),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final r = await SteamLoginDialog.show(context);
                    resultHolder.add(r);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Open the dialog and settle past the async secure-storage read.
  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<Object?> resultHolder,
  }) async {
    await pumpHost(tester, resultHolder);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the loading spinner before credentials are read',
      (tester) async {
    await pumpHost(tester, <Object?>[]);

    await tester.tap(find.text('open'));
    // One frame: the dialog mounts with _loading == true, before the async
    // secure-storage read resolves.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(t.steamPublish.loginDialog.usernameLabel), findsNothing);

    await tester.pumpAndSettle();
  });

  testWidgets('renders all fields once the (empty) store is read',
      (tester) async {
    await pumpDialog(tester, resultHolder: <Object?>[]);

    expect(find.text(t.steamPublish.loginDialog.title), findsOneWidget);
    expect(find.text(t.steamPublish.loginDialog.description), findsOneWidget);
    expect(find.text(t.steamPublish.loginDialog.usernameLabel), findsOneWidget);
    expect(find.text(t.steamPublish.loginDialog.passwordLabel), findsOneWidget);
    expect(
        find.text(t.steamPublish.loginDialog.steamGuardSection), findsOneWidget);
    expect(find.text(t.steamPublish.loginDialog.steamGuardCodeLabel),
        findsOneWidget);
    expect(find.text(t.steamPublish.loginDialog.rememberCredentials),
        findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(3));

    // Empty store: username field starts blank.
    expect(tester.widget<TextFormField>(usernameField()).controller?.text,
        isEmpty);
  });

  testWidgets('pre-fills username/password and checks remember when stored',
      (tester) async {
    store[SettingsKeys.steamUsername] = 'saved_user';
    store[SettingsKeys.steamPassword] = 'saved_pass';

    await pumpDialog(tester, resultHolder: <Object?>[]);

    expect(tester.widget<TextFormField>(usernameField()).controller?.text,
        'saved_user');

    // The pre-filled "remember" toggle shows the checked (filled) checkbox.
    expect(find.byIcon(FluentIcons.checkbox_checked_24_filled), findsOneWidget);
  });

  testWidgets('submitting with empty fields surfaces validation errors',
      (tester) async {
    await pumpDialog(tester, resultHolder: <Object?>[]);

    await tester.tap(find.text(t.steamPublish.loginDialog.login));
    await tester.pumpAndSettle();

    expect(find.text(t.steamPublish.loginDialog.errors.usernameRequired),
        findsOneWidget);
    expect(find.text(t.steamPublish.loginDialog.errors.passwordRequired),
        findsOneWidget);
    // Dialog stays open (validation failed -> no pop).
    expect(find.text(t.steamPublish.loginDialog.title), findsOneWidget);
  });

  testWidgets('cancel pops null', (tester) async {
    final results = <Object?>[];
    await pumpDialog(tester, resultHolder: results);

    await tester.tap(find.text(t.steamPublish.loginDialog.cancel));
    await tester.pumpAndSettle();

    expect(find.text(t.steamPublish.loginDialog.title), findsNothing);
    expect(results, hasLength(1));
    expect(results.single, isNull);
  });

  testWidgets('toggling obscure-password swaps the eye icon', (tester) async {
    await pumpDialog(tester, resultHolder: <Object?>[]);

    // Initially obscured -> "eye" icon shown.
    expect(find.byIcon(FluentIcons.eye_24_regular), findsOneWidget);

    await tester.tap(find.byIcon(FluentIcons.eye_24_regular));
    await tester.pumpAndSettle();

    expect(find.byIcon(FluentIcons.eye_off_24_regular), findsOneWidget);
  });

  testWidgets(
      'valid submit (no guard code) pops trimmed credentials and clears store',
      (tester) async {
    final results = <Object?>[];
    await pumpDialog(tester, resultHolder: results);

    await tester.enterText(usernameField(), '  user1  ');
    await tester.enterText(passwordField(), 'pass1');
    await tester.pump();

    await tester.tap(find.text(t.steamPublish.loginDialog.login));
    await tester.pumpAndSettle();

    expect(results, hasLength(1));
    final tuple = results.single as (String, String, String?);
    expect(tuple.$1, 'user1'); // trimmed
    expect(tuple.$2, 'pass1');
    expect(tuple.$3, isNull); // no 5-char guard code

    // Remember was off -> credentials deleted from the store.
    expect(calls.where((c) => c.method == 'delete'), isNotEmpty);
    expect(store.containsKey(SettingsKeys.steamUsername), isFalse);
  });

  testWidgets('valid submit with remember on writes credentials to the store',
      (tester) async {
    final results = <Object?>[];
    await pumpDialog(tester, resultHolder: results);

    await tester.enterText(usernameField(), 'remember_me');
    await tester.enterText(passwordField(), 'secret');
    await tester.pump();

    // Turn on the remember toggle.
    await tester.tap(find.text(t.steamPublish.loginDialog.rememberCredentials));
    await tester.pump();

    await tester.tap(find.text(t.steamPublish.loginDialog.login));
    await tester.pumpAndSettle();

    expect(store[SettingsKeys.steamUsername], 'remember_me');
    expect(store[SettingsKeys.steamPassword], 'secret');
    expect(results.single, isNotNull);
  });

  testWidgets('5-char guard code is upper-cased and returned in the tuple',
      (tester) async {
    final results = <Object?>[];
    await pumpDialog(tester, resultHolder: results);

    await tester.enterText(usernameField(), 'guarduser');
    await tester.enterText(passwordField(), 'pw');
    await tester.enterText(guardField(), 'abcde');
    await tester.pump();

    await tester.tap(find.text(t.steamPublish.loginDialog.login));
    await tester.pumpAndSettle();

    final tuple = results.single as (String, String, String?);
    expect(tuple.$3, 'ABCDE'); // upper-cased, length 5 kept
  });

  testWidgets('submitting via the password field onFieldSubmitted works',
      (tester) async {
    final results = <Object?>[];
    await pumpDialog(tester, resultHolder: results);

    await tester.enterText(usernameField(), 'enteruser');
    await tester.enterText(passwordField(), 'enterpw');
    await tester.pump();

    // Trigger onFieldSubmitted (TextInputAction.done) on the focused password.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(results, hasLength(1));
    final tuple = results.single as (String, String, String?);
    expect(tuple.$1, 'enteruser');
  });

  testWidgets('submitting via the Steam-Guard field onFieldSubmitted works',
      (tester) async {
    final results = <Object?>[];
    await pumpDialog(tester, resultHolder: results);

    await tester.enterText(usernameField(), 'guardsubmit');
    await tester.enterText(passwordField(), 'pw2');
    // Focus the Steam-Guard field last, then fire its TextInputAction.done.
    await tester.enterText(guardField(), 'zzzzz');
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(results, hasLength(1));
    final tuple = results.single as (String, String, String?);
    expect(tuple.$1, 'guardsubmit');
    expect(tuple.$3, 'ZZZZZ');
  });

  testWidgets('getSavedCredentials returns null when nothing is stored',
      (tester) async {
    final saved = await SteamLoginDialog.getSavedCredentials();
    expect(saved, isNull);
  });

  testWidgets('getSavedCredentials returns the tuple when stored',
      (tester) async {
    store[SettingsKeys.steamUsername] = 'persisted';
    store[SettingsKeys.steamPassword] = 'persistedpw';

    final saved = await SteamLoginDialog.getSavedCredentials();
    expect(saved, isNotNull);
    expect(saved!.$1, 'persisted');
    expect(saved.$2, 'persistedpw');
    expect(saved.$3, isNull);
  });
}
