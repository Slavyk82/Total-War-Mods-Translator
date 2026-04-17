import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/pack_compilation/screens/pack_compilation_editor_screen.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/wizard_screen_layout.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('new mode renders WizardScreenLayout', (t) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const PackCompilationEditorScreen(compilationId: null),
      theme: AppTheme.atelierDarkTheme,
      overrides: const <Override>[],
    ));
    await t.pump();
    expect(find.byType(WizardScreenLayout), findsOneWidget);
  });

  testWidgets('exposes compilationId field', (t) async {
    const screen = PackCompilationEditorScreen(compilationId: 'c-1');
    expect(screen.compilationId, 'c-1');
  });
}
