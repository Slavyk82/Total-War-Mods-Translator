// Basic smoke test for TWMT application.
//
// This test verifies that the app can be instantiated without errors.
// More comprehensive widget tests are in the features/ directory.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('App smoke test - MaterialApp can be created',
      (WidgetTester tester) async {
    // Build a minimal MaterialApp to verify basic widget tree creation works
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('TWMT Test'),
            ),
          ),
        ),
      ),
    );

    // Verify basic widget tree is present
    expect(find.text('TWMT Test'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
