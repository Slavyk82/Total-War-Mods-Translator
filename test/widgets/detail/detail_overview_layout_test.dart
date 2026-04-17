import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/detail/detail_overview_layout.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('renders main + rail side-by-side above breakpoint', (t) async {
    await t.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(wrap(
      const DetailOverviewLayout(
        main: Text('MAIN'),
        rail: Text('RAIL'),
      ),
    ));

    final mainRect = t.getRect(find.text('MAIN'));
    final railRect = t.getRect(find.text('RAIL'));
    expect(mainRect.left, lessThan(railRect.left),
        reason: 'main must be to the left of rail');
    expect(mainRect.top, closeTo(railRect.top, 2),
        reason: 'main and rail share a row');
  });

  testWidgets('stacks main + rail in a column below breakpoint', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(wrap(
      const DetailOverviewLayout(
        main: Text('MAIN'),
        rail: Text('RAIL'),
      ),
    ));

    final mainRect = t.getRect(find.text('MAIN'));
    final railRect = t.getRect(find.text('RAIL'));
    expect(mainRect.top, lessThan(railRect.top),
        reason: 'main above rail when stacked');
  });

  testWidgets('rail receives railWidth above breakpoint', (t) async {
    await t.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(wrap(
      const DetailOverviewLayout(
        main: SizedBox.shrink(),
        rail: SizedBox.shrink(key: Key('rail')),
        railWidth: 320,
      ),
    ));

    final railBox = t.getSize(find.byKey(const Key('rail')));
    expect(railBox.width, 320);
  });
}
