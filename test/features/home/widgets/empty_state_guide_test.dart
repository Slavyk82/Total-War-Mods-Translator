import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/home/widgets/empty_state_guide.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
    // Ensure a desktop-class viewport so the row never reports a horizontal
    // overflow on the default 800x600 test surface.
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize =
        const Size(1920, 1080);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  testWidgets('renders 5 step cards', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const EmptyStateGuide(),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Detect your mods in Sources'), findsOneWidget);
    expect(find.text('Create a project from a mod'), findsOneWidget);
    expect(find.text('Translate the units'), findsOneWidget);
    expect(find.text('Compile your pack'), findsOneWidget);
    expect(find.text('Publish on Steam Workshop'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('step 4 (Compile) is non-clickable', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const EmptyStateGuide(),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    final step4 = find.ancestor(
      of: find.text('Compile your pack'),
      matching: find.byType(GestureDetector),
    );
    expect(tester.widget<GestureDetector>(step4.first).onTap, isNull);
  });

  testWidgets('step 5 (Publish) is non-clickable', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const EmptyStateGuide(),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    final step5 = find.ancestor(
      of: find.text('Publish on Steam Workshop'),
      matching: find.byType(GestureDetector),
    );
    expect(tester.widget<GestureDetector>(step5.first).onTap, isNull);
  });

  testWidgets('step 1 (Detect) is clickable', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const EmptyStateGuide(),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    final step1 = find.ancestor(
      of: find.text('Detect your mods in Sources'),
      matching: find.byType(GestureDetector),
    );
    expect(tester.widget<GestureDetector>(step1.first).onTap, isNotNull);
  });
}
