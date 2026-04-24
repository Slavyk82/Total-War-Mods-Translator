import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/features/projects/providers/bulk_info_card_dismissed_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to false', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(await container.read(bulkInfoCardDismissedProvider.future), false);
  });

  test('dismiss() sets true and persists', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(bulkInfoCardDismissedProvider.future);
    await container.read(bulkInfoCardDismissedProvider.notifier).dismiss();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('projects_bulk_info_dismissed'), true);
    expect(container.read(bulkInfoCardDismissedProvider).value, true);
  });

  test('reset() sets false', () async {
    SharedPreferences.setMockInitialValues({'projects_bulk_info_dismissed': true});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(bulkInfoCardDismissedProvider.future);
    await container.read(bulkInfoCardDismissedProvider.notifier).reset();
    expect(container.read(bulkInfoCardDismissedProvider).value, false);
  });
}
