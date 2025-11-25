import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/translation_editor/widgets/export_translations_dialog.dart';

void main() {
  group('ExportTranslationsDialog', () {
    late List<LanguageSelection> testLanguages;

    setUp(() {
      testLanguages = [
        LanguageSelection(
          languageId: 'lang-en',
          languageCode: 'en',
          languageName: 'English',
          completionPercent: 100.0,
        ),
        LanguageSelection(
          languageId: 'lang-fr',
          languageCode: 'fr',
          languageName: 'French',
          completionPercent: 75.5,
        ),
        LanguageSelection(
          languageId: 'lang-de',
          languageCode: 'de',
          languageName: 'German',
          completionPercent: 50.0,
        ),
      ];
    });

    testWidgets('should display dialog with title', (tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ExportTranslationsDialog(
                projectId: 'project-1',
                projectName: 'Test Project',
                availableLanguages: testLanguages,
              ),
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('Export Translations'), findsOneWidget);
    });

    testWidgets('should display all available languages', (tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ExportTranslationsDialog(
                projectId: 'project-1',
                projectName: 'Test Project',
                availableLanguages: testLanguages,
              ),
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('English'), findsOneWidget);
      expect(find.text('French'), findsOneWidget);
      expect(find.text('German'), findsOneWidget);
    });

    testWidgets('should show completion percentages', (tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ExportTranslationsDialog(
                projectId: 'project-1',
                projectName: 'Test Project',
                availableLanguages: testLanguages,
              ),
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('100.0% complete'), findsOneWidget);
      expect(find.text('75.5% complete'), findsOneWidget);
      expect(find.text('50.0% complete'), findsOneWidget);
    });

    testWidgets('should allow selecting and deselecting languages',
        (tester) async {
      // Arrange
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ExportTranslationsDialog(
                projectId: 'project-1',
                projectName: 'Test Project',
                availableLanguages: testLanguages,
              ),
            ),
          ),
        ),
      );

      // Act - Select English
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();

      // Assert - Should be selected
      final checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile).first,
      );
      expect(checkbox.value, isTrue);
    });

    testWidgets('should have Select All button', (tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ExportTranslationsDialog(
                projectId: 'project-1',
                projectName: 'Test Project',
                availableLanguages: testLanguages,
              ),
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('Select All'), findsOneWidget);
    });

    testWidgets('should have Deselect All button', (tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ExportTranslationsDialog(
                projectId: 'project-1',
                projectName: 'Test Project',
                availableLanguages: testLanguages,
              ),
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('Deselect All'), findsOneWidget);
    });

    testWidgets('should show all export format options', (tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ExportTranslationsDialog(
                projectId: 'project-1',
                projectName: 'Test Project',
                availableLanguages: testLanguages,
              ),
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('Total War .pack file'), findsOneWidget);
      expect(find.text('CSV file'), findsOneWidget);
      expect(find.text('Excel file'), findsOneWidget);
      expect(find.text('TMX file'), findsOneWidget);
    });

    testWidgets('should show validation filter options', (tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ExportTranslationsDialog(
                projectId: 'project-1',
                projectName: 'Test Project',
                availableLanguages: testLanguages,
              ),
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('All translations'), findsOneWidget);
      expect(find.text('Validated only (recommended)'), findsOneWidget);
      expect(find.text('Needs review'), findsOneWidget);
    });

    testWidgets('should have Browse button for output location',
        (tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ExportTranslationsDialog(
                projectId: 'project-1',
                projectName: 'Test Project',
                availableLanguages: testLanguages,
              ),
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('Browse'), findsOneWidget);
    });

    testWidgets('should have Cancel and Export buttons', (tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ExportTranslationsDialog(
                projectId: 'project-1',
                projectName: 'Test Project',
                availableLanguages: testLanguages,
              ),
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
    });

    testWidgets('Export button should be disabled when no languages selected',
        (tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ExportTranslationsDialog(
                projectId: 'project-1',
                projectName: 'Test Project',
                availableLanguages: testLanguages,
              ),
            ),
          ),
        ),
      );

      // Assert
      final exportButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Export'),
      );
      expect(exportButton.onPressed, isNull); // Disabled
    });
  });
}
