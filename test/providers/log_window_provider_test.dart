import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/providers/log_window_provider.dart';

void main() {
  late ProviderContainer container;
  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  LogWindowController ctrl() =>
      container.read(logWindowControllerProvider.notifier);
  LogWindowVisibility state() => container.read(logWindowControllerProvider);

  test('starts closed', () {
    expect(state(), LogWindowVisibility.closed);
  });

  test('toggleOpen opens then closes', () {
    ctrl().toggleOpen();
    expect(state(), LogWindowVisibility.open);
    ctrl().toggleOpen();
    expect(state(), LogWindowVisibility.closed);
  });

  test('minimize then restore', () {
    ctrl().open();
    ctrl().minimize();
    expect(state(), LogWindowVisibility.minimized);
    ctrl().restore();
    expect(state(), LogWindowVisibility.open);
  });

  test('toggleOpen from minimized opens (not closes)', () {
    ctrl().minimize();
    ctrl().toggleOpen();
    expect(state(), LogWindowVisibility.open);
  });

  test('close from open', () {
    ctrl().open();
    ctrl().close();
    expect(state(), LogWindowVisibility.closed);
  });
}
