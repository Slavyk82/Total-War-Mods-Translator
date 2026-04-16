import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/cards/token_card.dart';
import '../../helpers/test_bootstrap.dart';
import '../../helpers/test_helpers.dart';

void main() {
  setUp(() async => TestBootstrap.registerFakes());

  testWidgets('renders child inside Container', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const TokenCard(child: Text('hello')),
      theme: AppTheme.atelierDarkTheme,
    ));
    expect(find.text('hello'), findsOneWidget);
    expect(find.byType(Container), findsWidgets);
  });

  testWidgets('uses token-driven bg/border/radius', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const TokenCard(child: SizedBox.shrink()),
      theme: AppTheme.atelierDarkTheme,
    ));

    final decoratedBox = tester.widget<Container>(
      find.byKey(const Key('TokenCardContainer')),
    );
    final decoration = decoratedBox.decoration as BoxDecoration;
    expect(decoration.border, isNotNull);
    expect(decoration.borderRadius, isNotNull);
  });
}
