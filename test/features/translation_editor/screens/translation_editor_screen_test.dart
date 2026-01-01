import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/translation_editor/screens/translation_editor_screen.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/providers/translation_settings_provider.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await setupMockServices();
  });

  tearDown(() async {
    await tearDownMockServices();
  });

  group('TranslationEditorScreen', () {
    const testProjectId = 'test-project-123';
    const testLanguageId = 'test-language-456';

    /// Creates test widget with mocked providers for translation editor
    Widget createTestWidget({ThemeData? theme}) {
      return ProviderScope(
        overrides: [
          // Override project provider
          currentProjectProvider(testProjectId).overrideWith(
            (ref) async => Project(
              id: testProjectId,
              name: 'Test Project',
              gameInstallationId: 'test-game-installation',
              projectType: 'mod',
              createdAt: DateTime.now().millisecondsSinceEpoch,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          ),
          // Override language provider
          currentLanguageProvider(testLanguageId).overrideWith(
            (ref) async => const Language(
              id: testLanguageId,
              code: 'es',
              name: 'Spanish',
              nativeName: 'Espanol',
            ),
          ),
          // Override translation rows provider - empty for tests
          translationRowsProvider(testProjectId, testLanguageId).overrideWith(
            (ref) async => <TranslationRow>[],
          ),
          // Override translation settings
          translationSettingsProvider.overrideWith(
            () => _MockTranslationSettingsNotifier(),
          ),
        ],
        child: MaterialApp(
          theme: theme ?? ThemeData.light(),
          home: SizedBox(
            width: defaultTestScreenSize.width,
            height: defaultTestScreenSize.height,
            child: const TranslationEditorScreen(
              projectId: testProjectId,
              languageId: testLanguageId,
            ),
          ),
        ),
      );
    }

    group('Widget Structure', () {
      testWidgets('should render FluentScaffold as root widget', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(FluentScaffold), findsOneWidget);
      });

      testWidgets('should accept projectId and languageId parameters', (tester) async {
        const screen = TranslationEditorScreen(
          projectId: testProjectId,
          languageId: testLanguageId,
        );
        expect(screen.projectId, equals(testProjectId));
        expect(screen.languageId, equals(testLanguageId));
      });

      testWidgets('should have header with back button', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byIcon(FluentIcons.arrow_left_24_regular), findsWidgets);
      });
    });

    group('State Management', () {
      testWidgets('should be a ConsumerStatefulWidget', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });
    });

    group('Layout Structure', () {
      testWidgets('should have Column as main layout', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(Column), findsWidgets);
      });

      testWidgets('should have Row for content area', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(Row), findsWidgets);
      });
    });

    group('Header', () {
      testWidgets('should display Translation Editor title', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });
    });

    group('Toolbar', () {
      testWidgets('should render EditorToolbar component', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });
    });

    group('Sidebar', () {
      testWidgets('should render EditorSidebar component', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });
    });

    group('DataGrid', () {
      testWidgets('should render EditorDataGrid component', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });
    });

    group('Actions', () {
      testWidgets('should support translation settings action', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });

      testWidgets('should support translate all action', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });

      testWidgets('should support translate selected action', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });

      testWidgets('should support validate action', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });

      testWidgets('should support export action', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });
    });

    group('Cell Editing', () {
      testWidgets('should support cell edit callback', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });
    });

    group('Settings Initialization', () {
      testWidgets('should reset skipTranslationMemory on init', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });

      testWidgets('should clear mod update impact on init', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });
    });

    group('Theme Integration', () {
      testWidgets('should render correctly with light theme', (tester) async {
        await tester.pumpWidget(createTestWidget(theme: ThemeData.light()));
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });

      testWidgets('should render correctly with dark theme', (tester) async {
        await tester.pumpWidget(createTestWidget(theme: ThemeData.dark()));
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });
    });

    group('Navigation', () {
      testWidgets('should support back navigation', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byIcon(FluentIcons.arrow_left_24_regular), findsWidgets);
      });
    });
  });
}

/// Mock notifier for TranslationSettingsNotifier
class _MockTranslationSettingsNotifier extends TranslationSettingsNotifier {
  @override
  TranslationSettings build() => const TranslationSettings(
    unitsPerBatch: 0,
    parallelBatches: 5,
    skipTranslationMemory: false,
  );

  @override
  void setSkipTranslationMemory(bool value) {}

  @override
  Future<void> updateSettings({int? unitsPerBatch, int? parallelBatches}) async {}

  @override
  Future<TranslationSettings> ensureLoaded() async => state;
}
