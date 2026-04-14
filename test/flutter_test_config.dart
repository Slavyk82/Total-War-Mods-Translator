import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:twmt/theme/tokens/atelier_tokens.dart';
import 'package:twmt/theme/tokens/forge_tokens.dart';

/// Global test configuration, picked up automatically by `flutter test`.
///
/// Why: `TwmtThemeTokens` instances (`atelierTokens`, `forgeTokens`, …) call
/// `GoogleFonts.*()` factories at top-level initialization. Those factories
/// schedule async font loads against the asset bundle, which fail under a
/// bare test binding — either by throwing "Binding has not yet been
/// initialized" or by reporting errors because the fonts are not bundled as
/// test assets and runtime fetching is disabled.
///
/// If those async loads fire inside a per-test zone (i.e. the first test
/// that touches a tokens instance), `flutter_test` will fail that test even
/// though the assertion itself passed. This harness prevents that by:
///
/// 1. Initializing `TestWidgetsFlutterBinding` so the platform channel
///    exists during font factory resolution.
/// 2. Disabling runtime font fetching so `google_fonts` never attempts an
///    HTTP call during tests (CI-friendly, deterministic).
/// 3. Installing a `FlutterError.onError` filter that swallows the expected
///    "font X was not found in the application assets" errors raised by
///    `google_fonts`. All other errors fall through to the default handler
///    so real regressions still fail the suite.
/// 4. Pre-touching each shared tokens instance inside a guarded zone, so
///    the async font loads are scheduled (and their errors absorbed) from
///    this outer zone rather than from the first test that inspects the
///    tokens. The assertions in individual test files only read palette /
///    radius / bool fields, which are already resolved synchronously before
///    the font load fails.
///
/// Flutter runs this file automatically if it lives at
/// `test/flutter_test_config.dart`.
/// See https://api.flutter.dev/flutter/flutter_test/flutter_test-library.html
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final previousOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (_isGoogleFontsAssetMiss(details.exception)) {
      return;
    }
    previousOnError?.call(details);
  };

  await runZonedGuarded(
    () async {
      // Force module initialization inside this guarded zone so the async
      // google_fonts loads (and their expected failures) are scheduled
      // here rather than inside a per-test zone. Add new tokens instances
      // to this list as they are introduced (e.g. forgeTokens, …).
      atelierTokens.bg;
      forgeTokens.bg;

      await testMain();
    },
    (error, stack) {
      if (_isGoogleFontsAssetMiss(error)) {
        return;
      }
      // Surface any other unexpected async error so we do not hide real
      // regressions.
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
  );
}

bool _isGoogleFontsAssetMiss(Object error) {
  final message = error.toString();
  return message.contains('GoogleFonts.config.allowRuntimeFetching is false') ||
      message.contains('was not found in the application assets');
}
