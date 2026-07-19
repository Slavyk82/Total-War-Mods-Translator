import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/widgets/fluent/fluent_outlined_button.dart';

/// Deterministic explicit colours so state-driven assertions do not depend on
/// the ambient theme.
const Color _fg = Color(0xFF00FF00);
const Color _border = Color(0xFFFF0000);

/// Wraps [child] in a themed MaterialApp. FluentOutlinedButton only reads
/// standard [ThemeData] fields, so a plain themed app is sufficient.
Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData.light(),
      home: Scaffold(body: Center(child: child)),
    );

/// Returns the BoxDecoration of the button's AnimatedContainer.
BoxDecoration _decoration(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byType(FluentOutlinedButton),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return container.decoration as BoxDecoration;
}

BoxConstraints _constraints(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byType(FluentOutlinedButton),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return container.constraints!;
}

void main() {
  group('FluentOutlinedButton rendering', () {
    testWidgets('renders the child label', (tester) async {
      await tester.pumpWidget(
        _wrap(FluentOutlinedButton(
          onPressed: () {},
          child: const Text('Apply'),
        )),
      );
      expect(find.text('Apply'), findsOneWidget);
    });

    testWidgets('renders an icon + child Row when an icon is supplied',
        (tester) async {
      await tester.pumpWidget(
        _wrap(FluentOutlinedButton(
          onPressed: () {},
          icon: const Icon(Icons.filter_alt),
          child: const Text('Filter'),
        )),
      );
      expect(find.byIcon(Icons.filter_alt), findsOneWidget);
      expect(find.text('Filter'), findsOneWidget);
      // The icon variant lays child + icon out in a Row.
      expect(
        find.descendant(
          of: find.byType(FluentOutlinedButton),
          matching: find.byType(Row),
        ),
        findsOneWidget,
      );
    });

    testWidgets('wraps the child in a Center when no icon is supplied',
        (tester) async {
      await tester.pumpWidget(
        _wrap(FluentOutlinedButton(
          onPressed: () {},
          child: const Text('Plain'),
        )),
      );
      expect(
        find.descendant(
          of: find.byType(FluentOutlinedButton),
          matching: find.byType(Row),
        ),
        findsNothing,
      );
    });
  });

  group('FluentOutlinedButton defaults', () {
    testWidgets('applies default sizing, padding, radius and border width',
        (tester) async {
      late ThemeData captured;
      await tester.pumpWidget(
        _wrap(Builder(builder: (context) {
          captured = Theme.of(context);
          return FluentOutlinedButton(
            onPressed: () {},
            child: const Text('Go'),
          );
        })),
      );

      final deco = _decoration(tester);
      final constraints = _constraints(tester);
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(FluentOutlinedButton),
          matching: find.byType(AnimatedContainer),
        ),
      );

      expect(constraints.minWidth, 80.0);
      expect(constraints.minHeight, 32.0);
      expect(container.padding,
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12));
      expect(deco.borderRadius, BorderRadius.circular(4.0));
      expect((deco.border as Border).top.width, 1.5);
      // Default border is the theme divider colour; default foreground is the
      // primary colour with a transparent background at rest.
      expect((deco.border as Border).top.color, captured.dividerColor);
      expect(deco.color, captured.colorScheme.primary.withValues(alpha: 0.0));
    });
  });

  group('FluentOutlinedButton interaction', () {
    testWidgets('invokes onPressed on tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(FluentOutlinedButton(
          onPressed: () => taps++,
          child: const Text('Tap'),
        )),
      );
      await tester.tap(find.byType(FluentOutlinedButton));
      expect(taps, 1);
    });

    testWidgets('at rest uses the supplied border and a transparent fill',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const FluentOutlinedButtonHarness()),
      );
      final deco = _decoration(tester);
      expect((deco.border as Border).top.color, _border);
      expect(deco.color, _fg.withValues(alpha: 0.0));
    });

    testWidgets('on hover switches to the foreground border and 5% fill',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const FluentOutlinedButtonHarness()),
      );

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byType(FluentOutlinedButton)));
      await tester.pump();

      final deco = _decoration(tester);
      expect((deco.border as Border).top.color, _fg);
      expect(deco.color, _fg.withValues(alpha: 0.05));
    });

    testWidgets('while pressed uses the foreground border and 8% fill',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const FluentOutlinedButtonHarness()),
      );

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(FluentOutlinedButton)));
      await tester.pump();

      final deco = _decoration(tester);
      expect((deco.border as Border).top.color, _fg);
      expect(deco.color, _fg.withValues(alpha: 0.08));

      await gesture.up();
      await tester.pump();
      // After release the pressed state clears back to the resting fill.
      expect(_decoration(tester).color, _fg.withValues(alpha: 0.0));
    });

    testWidgets('clears the pressed state when the tap is cancelled',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const FluentOutlinedButtonHarness()),
      );

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(FluentOutlinedButton)));
      await tester.pump();
      expect(_decoration(tester).color, _fg.withValues(alpha: 0.08));

      // Move far away and release -> tap cancel, pressed state resets.
      await gesture.moveTo(const Offset(2000, 2000));
      await gesture.up();
      await tester.pump();
      expect(_decoration(tester).color, _fg.withValues(alpha: 0.0));
    });
  });

  group('FluentOutlinedButton disabled', () {
    testWidgets('does not invoke a callback and dims the border', (tester) async {
      await tester.pumpWidget(
        _wrap(const FluentOutlinedButton(
          onPressed: null,
          borderColor: _border,
          foregroundColor: _fg,
          child: Text('Off'),
        )),
      );

      // Tapping a disabled button is a no-op (no throw / callback to fire).
      await tester.tap(find.byType(FluentOutlinedButton));
      await tester.pump();

      final deco = _decoration(tester);
      // Disabled border is the supplied border colour at 50% opacity, and the
      // fill stays transparent.
      expect((deco.border as Border).top.color, _border.withValues(alpha: 0.5));
      expect(deco.color, _fg.withValues(alpha: 0.0));

      // The cursor falls back to the basic (non-click) cursor when disabled.
      final region = tester.widget<MouseRegion>(
        find.descendant(
          of: find.byType(FluentOutlinedButton),
          matching: find.byType(MouseRegion),
        ),
      );
      expect(region.cursor, SystemMouseCursors.basic);
    });
  });

  group('FluentOutlinedButton customisation', () {
    testWidgets('honours explicit sizing, padding and radius', (tester) async {
      await tester.pumpWidget(
        _wrap(FluentOutlinedButton(
          onPressed: () {},
          padding: const EdgeInsets.all(6),
          borderRadius: 12,
          borderWidth: 3,
          minWidth: 120,
          minHeight: 44,
          child: const Text('Custom'),
        )),
      );

      final deco = _decoration(tester);
      final constraints = _constraints(tester);
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(FluentOutlinedButton),
          matching: find.byType(AnimatedContainer),
        ),
      );

      expect(constraints.minWidth, 120.0);
      expect(constraints.minHeight, 44.0);
      expect(container.padding, const EdgeInsets.all(6));
      expect(deco.borderRadius, BorderRadius.circular(12));
      expect((deco.border as Border).top.width, 3.0);
    });
  });
}

/// Small const harness so the enabled interaction tests share one deterministic
/// button configuration.
class FluentOutlinedButtonHarness extends StatelessWidget {
  const FluentOutlinedButtonHarness({super.key});

  @override
  Widget build(BuildContext context) {
    return FluentOutlinedButton(
      onPressed: () {},
      borderColor: _border,
      foregroundColor: _fg,
      child: const Text('State'),
    );
  }
}
