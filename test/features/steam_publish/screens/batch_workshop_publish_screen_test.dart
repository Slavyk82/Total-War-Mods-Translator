import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/steam_publish/screens/batch_workshop_publish_screen.dart';
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
      const BatchWorkshopPublishScreen(),
      theme: AppTheme.atelierDarkTheme,
    ));
    await t.pump();
    // Without staged batch data, the screen renders a simple fallback with
    // DetailScreenToolbar and a "No items" message. With staged data it
    // renders the full WizardScreenLayout.
    expect(
      find.byType(WizardScreenLayout).evaluate().isNotEmpty ||
          find.textContaining('No items').evaluate().isNotEmpty ||
          find.textContaining('No batch').evaluate().isNotEmpty,
      isTrue,
    );
  });
}
