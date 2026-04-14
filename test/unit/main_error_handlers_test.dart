import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FlutterError.onError is settable', () {
    final original = FlutterError.onError;
    try {
      FlutterError.onError = (_) {};
      expect(FlutterError.onError, isNotNull);
    } finally {
      FlutterError.onError = original;
    }
  });

  test('PlatformDispatcher.onError is settable', () {
    final original = PlatformDispatcher.instance.onError;
    try {
      PlatformDispatcher.instance.onError = (_, __) => true;
      expect(PlatformDispatcher.instance.onError, isNotNull);
    } finally {
      PlatformDispatcher.instance.onError = original;
    }
  });
}
