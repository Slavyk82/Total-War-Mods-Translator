import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/providers/clock_provider.dart';

void main() {
  test('clockProvider default returns a DateTime near the real now', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final before = DateTime.now();
    final clock = container.read(clockProvider);
    final now = clock();
    final after = DateTime.now();

    // The returned DateTime should be bracketed by actual wall clock calls.
    expect(now.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
    expect(now.isBefore(after.add(const Duration(seconds: 1))), isTrue);
  });

  test('clockProvider can be overridden with a fixed DateTime', () {
    final fixed = DateTime(2024, 1, 15, 12, 0, 0);
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(() => fixed),
      ],
    );
    addTearDown(container.dispose);

    final clock = container.read(clockProvider);
    expect(clock(), fixed);
  });
}
