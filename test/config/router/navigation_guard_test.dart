import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/config/router/navigation_guard.dart';
import 'package:twmt/features/pack_compilation/providers/pack_compilation_providers.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';

void main() {
  Widget host(void Function(WidgetRef) capture) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (ctx, ref, _) {
              capture(ref);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
  }

  testWidgets('returns true when no operation is in progress', (t) async {
    late WidgetRef captured;
    await t.pumpWidget(host((ref) => captured = ref));
    await t.pumpAndSettle();
    expect(
      canNavigateNow(captured.context, captured),
      isTrue,
    );
  });

  testWidgets('returns false when translation is in progress', (t) async {
    late WidgetRef captured;
    // `translationInProgressProvider` is a Notifier-based provider generated
    // by `riverpod_generator`. Its generated class exposes `overrideWithValue`
    // rather than the functional `overrideWith((ref) => value)` form, so we
    // use the former here (same pattern used in main_layout_router_test.dart).
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          translationInProgressProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (ctx, ref, _) {
                captured = ref;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      canNavigateNow(captured.context, captured),
      isFalse,
    );
  });

  testWidgets('returns false when compilation is in progress', (t) async {
    late WidgetRef captured;
    // `compilationInProgressProvider` is a plain `Provider<bool>`, so the
    // functional `overrideWith((ref) => true)` form matches its signature.
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          compilationInProgressProvider.overrideWith((ref) => true),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (ctx, ref, _) {
                captured = ref;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      canNavigateNow(captured.context, captured),
      isFalse,
    );
  });
}
