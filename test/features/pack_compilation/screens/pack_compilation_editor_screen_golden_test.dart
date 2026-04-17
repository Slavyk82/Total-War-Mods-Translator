import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/pack_compilation/screens/pack_compilation_editor_screen.dart';
import 'package:twmt/theme/app_theme.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pump(WidgetTester t, ThemeData theme) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const PackCompilationEditorScreen(compilationId: null),
      theme: theme,
    ));
    await t.pumpAndSettle();
  }

  testWidgets('pack compilation editor atelier empty form', (t) async {
    await pump(t, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(PackCompilationEditorScreen),
      matchesGoldenFile('../goldens/pack_compilation_editor_atelier.png'),
    );
  });

  testWidgets('pack compilation editor forge empty form', (t) async {
    await pump(t, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(PackCompilationEditorScreen),
      matchesGoldenFile('../goldens/pack_compilation_editor_forge.png'),
    );
  });
}
