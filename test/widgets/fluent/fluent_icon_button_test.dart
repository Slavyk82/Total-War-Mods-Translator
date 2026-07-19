import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/widgets/fluent/fluent_icon_button.dart';

const Color _iconColor = Color(0xFF00FF00);
const Color _bgColor = Color(0xFF0000FF);

/// Wraps [child] in a themed MaterialApp. FluentIconButton only reads standard
/// [ThemeData] fields, so a plain themed app is sufficient.
Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData.light(),
      home: Scaffold(body: Center(child: child)),
    );

AnimatedContainer _animatedContainer(WidgetTester tester) {
  return tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byType(FluentIconButton),
      matching: find.byType(AnimatedContainer),
    ),
  );
}

BoxDecoration _decoration(WidgetTester tester) =>
    _animatedContainer(tester).decoration as BoxDecoration;

/// The single IconTheme the widget wraps around its icon.
IconThemeData _iconTheme(WidgetTester tester) {
  return tester
      .widget<IconTheme>(
        find.descendant(
          of: find.byType(FluentIconButton),
          matching: find.byType(IconTheme),
        ),
      )
      .data;
}

void main() {
  group('FluentIconButton rendering', () {
    testWidgets('renders the supplied icon', (tester) async {
      await tester.pumpWidget(
        _wrap(FluentIconButton(
          icon: const Icon(Icons.delete),
          onPressed: () {},
        )),
      );
      expect(find.byIcon(Icons.delete), findsOneWidget);
    });

    testWidgets('applies default size and icon size', (tester) async {
      await tester.pumpWidget(
        _wrap(FluentIconButton(
          icon: const Icon(Icons.close),
          onPressed: () {},
        )),
      );
      // width/height (32) are set directly on the AnimatedContainer, which
      // resolves them to a tight 32x32 constraint.
      expect(
        _animatedContainer(tester).constraints,
        BoxConstraints.tight(const Size(32, 32)),
      );
      expect(_iconTheme(tester).size, 20.0);
    });

    testWidgets('square shape uses a 4px radius', (tester) async {
      await tester.pumpWidget(
        _wrap(FluentIconButton(
          icon: const Icon(Icons.close),
          onPressed: () {},
        )),
      );
      expect(_decoration(tester).borderRadius, BorderRadius.circular(4.0));
    });

    testWidgets('circle shape uses a half-size radius', (tester) async {
      await tester.pumpWidget(
        _wrap(FluentIconButton(
          icon: const Icon(Icons.close),
          onPressed: () {},
          size: 40,
          shape: FluentIconButtonShape.circle,
        )),
      );
      expect(_decoration(tester).borderRadius, BorderRadius.circular(20.0));
    });

    testWidgets('honours custom size and icon size', (tester) async {
      await tester.pumpWidget(
        _wrap(FluentIconButton(
          icon: const Icon(Icons.close),
          onPressed: () {},
          size: 48,
          iconSize: 28,
        )),
      );
      expect(
        _animatedContainer(tester).constraints,
        BoxConstraints.tight(const Size(48, 48)),
      );
      expect(_iconTheme(tester).size, 28.0);
    });
  });

  group('FluentIconButton tooltip', () {
    testWidgets('wraps the button in a Tooltip when a tooltip is supplied',
        (tester) async {
      await tester.pumpWidget(
        _wrap(FluentIconButton(
          icon: const Icon(Icons.delete),
          onPressed: () {},
          tooltip: 'Delete item',
        )),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'Delete item',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders no Tooltip when tooltip is null', (tester) async {
      await tester.pumpWidget(
        _wrap(FluentIconButton(
          icon: const Icon(Icons.delete),
          onPressed: () {},
        )),
      );
      expect(find.byType(Tooltip), findsNothing);
    });
  });

  group('FluentIconButton colours', () {
    testWidgets('defaults icon and background to the onSurface colour',
        (tester) async {
      late ThemeData captured;
      await tester.pumpWidget(
        _wrap(Builder(builder: (context) {
          captured = Theme.of(context);
          return FluentIconButton(
            icon: const Icon(Icons.close),
            onPressed: () {},
          );
        })),
      );
      // Enabled icon is fully opaque onSurface; resting fill is transparent
      // onSurface.
      expect(_iconTheme(tester).color,
          captured.colorScheme.onSurface.withValues(alpha: 1.0));
      expect(_decoration(tester).color,
          captured.colorScheme.onSurface.withValues(alpha: 0.0));
    });

    testWidgets('honours explicit icon and background colours', (tester) async {
      await tester.pumpWidget(
        _wrap(const _IconButtonHarness()),
      );
      expect(_iconTheme(tester).color, _iconColor.withValues(alpha: 1.0));
      expect(_decoration(tester).color, _bgColor.withValues(alpha: 0.0));
    });
  });

  group('FluentIconButton interaction', () {
    testWidgets('invokes onPressed on tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(FluentIconButton(
          icon: const Icon(Icons.check),
          onPressed: () => taps++,
        )),
      );
      await tester.tap(find.byType(FluentIconButton));
      expect(taps, 1);
    });

    testWidgets('on hover shows an 8% fill', (tester) async {
      await tester.pumpWidget(_wrap(const _IconButtonHarness()));

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byType(FluentIconButton)));
      await tester.pump();

      expect(_decoration(tester).color, _bgColor.withValues(alpha: 0.08));
    });

    testWidgets('while pressed shows a 10% fill and resets on release',
        (tester) async {
      await tester.pumpWidget(_wrap(const _IconButtonHarness()));

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(FluentIconButton)));
      await tester.pump();
      expect(_decoration(tester).color, _bgColor.withValues(alpha: 0.10));

      await gesture.up();
      await tester.pump();
      expect(_decoration(tester).color, _bgColor.withValues(alpha: 0.0));
    });

    testWidgets('clears the pressed state on tap cancel', (tester) async {
      await tester.pumpWidget(_wrap(const _IconButtonHarness()));

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(FluentIconButton)));
      await tester.pump();
      expect(_decoration(tester).color, _bgColor.withValues(alpha: 0.10));

      await gesture.moveTo(const Offset(2000, 2000));
      await gesture.up();
      await tester.pump();
      expect(_decoration(tester).color, _bgColor.withValues(alpha: 0.0));
    });
  });

  group('FluentIconButton disabled', () {
    testWidgets('does not fire, dims the icon and uses the basic cursor',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const FluentIconButton(
          icon: Icon(Icons.close),
          onPressed: null,
          iconColor: _iconColor,
          iconSize: 18,
        )),
      );

      // A disabled tap is a no-op.
      await tester.tap(find.byType(FluentIconButton));
      await tester.pump();

      // Disabled icon renders at 50% opacity of the supplied colour.
      expect(_iconTheme(tester).color, _iconColor.withValues(alpha: 0.5));

      final region = tester.widget<MouseRegion>(
        find.descendant(
          of: find.byType(FluentIconButton),
          matching: find.byType(MouseRegion),
        ),
      );
      expect(region.cursor, SystemMouseCursors.basic);
    });

    testWidgets('does not paint a hover fill when disabled', (tester) async {
      await tester.pumpWidget(
        _wrap(const FluentIconButton(
          icon: Icon(Icons.close),
          onPressed: null,
          backgroundColor: _bgColor,
        )),
      );

      // Disabled buttons have null hover handlers, so a mouse enter cannot
      // change the resting transparent fill.
      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byType(FluentIconButton)));
      await tester.pump();

      expect(_decoration(tester).color, _bgColor.withValues(alpha: 0.0));
    });
  });
}

/// Const harness sharing one deterministic enabled configuration across the
/// interaction and colour tests.
class _IconButtonHarness extends StatelessWidget {
  const _IconButtonHarness();

  @override
  Widget build(BuildContext context) {
    return FluentIconButton(
      icon: const Icon(Icons.settings),
      onPressed: () {},
      iconColor: _iconColor,
      backgroundColor: _bgColor,
    );
  }
}
