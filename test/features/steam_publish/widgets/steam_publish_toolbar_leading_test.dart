import 'package:flutter_test/flutter_test.dart';

import 'package:twmt/features/steam_publish/widgets/steam_publish_toolbar.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async => TestBootstrap.registerFakes());

  testWidgets('SteamPublishToolbarLeading does not show subs segment when subsTotal is 0',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const SteamPublishToolbarLeading(
        totalItems: 5,
        filteredItems: 5,
        selectedCount: 0,
        searchActive: false,
        subsTotal: 0,
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('subs'), findsNothing);
  });

  testWidgets(
      'SteamPublishToolbarLeading shows formatted subs segment when subsTotal > 0',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const SteamPublishToolbarLeading(
        totalItems: 10,
        filteredItems: 10,
        selectedCount: 0,
        searchActive: false,
        subsTotal: 4567,
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('4 567 subs'), findsOneWidget);
  });

  testWidgets(
      'SteamPublishToolbarLeading shows correct combined label with selected and subs',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const SteamPublishToolbarLeading(
        totalItems: 12,
        filteredItems: 12,
        selectedCount: 3,
        searchActive: false,
        subsTotal: 4567,
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    // The count label is one combined Text widget in ListToolbarLeading.
    // It should contain packs count, selected segment, and subs segment in order.
    expect(find.textContaining('12 packs · 3 selected · 4 567 subs'), findsOneWidget);
  });
}
