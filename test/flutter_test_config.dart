import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Global test configuration, picked up automatically by `flutter test`.
///
/// Initializes the test binding so platform channels exist before any test
/// runs. Fonts are bundled as regular assets (see `pubspec.yaml`), so no
/// special font handling is required here.
///
/// Flutter runs this file automatically if it lives at
/// `test/flutter_test_config.dart`.
/// See https://api.flutter.dev/flutter/flutter_test/flutter_test-library.html
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await testMain();
}
