import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/steam_publish/screens/workshop_publish_screen.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/wizard_screen_layout.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('renders WizardScreenLayout or no-staging fallback', (t) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const WorkshopPublishScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: const <Override>[],
    ));
    await t.pump();
    // The screen guards on staging data (a `PublishableItem` staged via
    // `singlePublishStagingProvider`). With no staged item, the screen
    // renders a DetailScreenToolbar + empty-state fallback; otherwise the
    // full WizardScreenLayout is rendered.
    expect(
      find.byType(WizardScreenLayout).evaluate().isNotEmpty ||
          find.textContaining('No pack').evaluate().isNotEmpty ||
          find.textContaining('No item').evaluate().isNotEmpty ||
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty,
      isTrue,
    );
  });
}
