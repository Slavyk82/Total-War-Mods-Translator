import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/bulk_action_cluster.dart';

void main() {
  testWidgets('renders count and fires callbacks', (tester) async {
    var accepted = false;
    var rejected = false;
    var deselected = false;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.atelierDarkTheme,
      home: Scaffold(
        body: BulkActionCluster(
          selectedCount: 4,
          onAccept: () => accepted = true,
          onReject: () => rejected = true,
          onDeselect: () => deselected = true,
        ),
      ),
    ));

    expect(find.text('4 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Accept selected'));
    expect(accepted, isTrue);
    await tester.tap(find.byTooltip('Reject selected'));
    expect(rejected, isTrue);
    await tester.tap(find.byTooltip('Deselect all'));
    expect(deselected, isTrue);
  });
}
