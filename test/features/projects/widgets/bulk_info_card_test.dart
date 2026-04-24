import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/features/projects/widgets/bulk_info_card.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders message and dismiss button when not dismissed', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: BulkInfoCard())),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('partially translated'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('hides card when pref is dismissed', (tester) async {
    SharedPreferences.setMockInitialValues({'projects_bulk_info_dismissed': true});
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: BulkInfoCard())),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('partially translated'), findsNothing);
  });
}
