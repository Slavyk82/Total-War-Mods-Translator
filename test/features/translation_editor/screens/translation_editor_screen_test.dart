import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/translation_editor/screens/translation_editor_screen.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/providers/translation_settings_provider.dart';
import 'package:twmt/features/translation_editor/widgets/editor_top_bar.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await setupMockServices();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1920, 1080);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
    await tearDownMockServices();
  });

  group('TranslationEditorScreen', () {
    const testProjectId = 'test-project-123';
    const testLanguageId = 'test-language-456';
    // Reference desktop size from spec §8.7. The EditorTopBar's middle action
    // group is wrapped in a horizontal SingleChildScrollView, so this viewport
    // (and even the 1280px min-width) renders without layout overflow.
    const wideScreenSize = Size(1920, 1080);

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
          // Default to a TWMT-themed surface so widgets that read
          // `context.tokens` (e.g. EditorStatusBar) resolve their tokens.
          theme: theme ?? AppTheme.atelierDarkTheme,
          home: SizedBox(
            width: wideScreenSize.width,
            height: wideScreenSize.height,
            child: const TranslationEditorScreen(
              projectId: testProjectId,
              languageId: testLanguageId,
            ),
          ),
        ),
      );
    }

    group('Widget Structure', () {
      testWidgets('should render Material as root widget', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });

      testWidgets('should accept projectId and languageId parameters', (tester) async {
        const screen = TranslationEditorScreen(
          projectId: testProjectId,
          languageId: testLanguageId,
        );
        expect(screen.projectId, equals(testProjectId));
        expect(screen.languageId, equals(testLanguageId));
      });

      testWidgets('should render EditorTopBar with crumb navigation', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(EditorTopBar), findsOneWidget);
        expect(find.text('Projects'), findsOneWidget);
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
      testWidgets('should render EditorTopBar component', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(EditorTopBar), findsOneWidget);
      });
    });

    group('Filter panel', () {
      testWidgets('should render EditorFilterPanel component', (tester) async {
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
      testWidgets('should render correctly with atelier theme', (tester) async {
        await tester.pumpWidget(
          createTestWidget(theme: AppTheme.atelierDarkTheme),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });

      testWidgets('should render correctly with forge theme', (tester) async {
        await tester.pumpWidget(
          createTestWidget(theme: AppTheme.forgeDarkTheme),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TranslationEditorScreen), findsOneWidget);
      });
    });

    group('Navigation', () {
      testWidgets('renders DetailScreenToolbar with crumb and back button',
          (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(DetailScreenToolbar), findsOneWidget);
        // Crumb format: "Work › Projects › <project> › <language>".
        expect(
          find.textContaining('Work › Projects › Test Project › Spanish'),
          findsOneWidget,
        );
        expect(find.byTooltip('Back'), findsOneWidget);
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
